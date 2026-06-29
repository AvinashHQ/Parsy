from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import shutil
from copy import deepcopy
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

import fitz
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageOps
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4, LETTER
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    PageBreak,
    KeepTogether,
)

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "samples" / "synthetic_corpus"
PDF_DIR = CORPUS / "documents" / "pdf"
IMG_DIR = CORPUS / "documents" / "images"
STRUCT_DIR = CORPUS / "documents" / "structured"
UNSAFE_DIR = CORPUS / "documents" / "unsafe"
GT_DIR = CORPUS / "ground_truth"
FIND_DIR = CORPUS / "expected_findings"
MODEL_DIR = CORPUS / "model_outputs"
EXPORT_DIR = CORPUS / "exports"
for d in [PDF_DIR, IMG_DIR, STRUCT_DIR, UNSAFE_DIR, GT_DIR, FIND_DIR, MODEL_DIR, EXPORT_DIR]:
    d.mkdir(parents=True, exist_ok=True)

TODAY = date(2026, 6, 29)
MONEY_Q = Decimal("0.00000001")

CURRENCY_SYMBOLS = {
    "USD": "$", "GBP": "£", "EUR": "€", "INR": "₹", "JPY": "¥",
    "KWD": "KD ", "AED": "AED ", "CAD": "C$", "MXN": "MX$"
}
MINOR = {"JPY": 0, "KWD": 3}


def q(value: Decimal, currency: str) -> Decimal:
    places = MINOR.get(currency, 2)
    quantum = Decimal(1).scaleb(-places)
    return value.quantize(quantum, rounding=ROUND_HALF_UP)


def dec(value) -> Decimal:
    return Decimal(str(value))


def dstr(value: Decimal, currency: str | None = None, keep_rate=False) -> str:
    if keep_rate:
        text = format(value.normalize(), "f")
        return text if "." in text else text
    if currency:
        value = q(value, currency)
        places = MINOR.get(currency, 2)
        return f"{value:.{places}f}"
    return format(value.normalize(), "f")


def money(value: Decimal, currency: str) -> str:
    places = MINOR.get(currency, 2)
    sym = CURRENCY_SYMBOLS.get(currency, currency + " ")
    return f"{sym}{value:,.{places}f}"


def party(name, country, city, postal, identifier_scheme, identifier_value, address_line):
    return {
        "display_name": name,
        "legal_name": name,
        "trading_name": None,
        "identifiers": [{
            "scheme": identifier_scheme,
            "value": identifier_value,
            "issuing_country": country,
            "purpose": "tax" if identifier_scheme in {"VAT", "GSTIN", "EIN", "BN", "TRN", "RFC"} else "business",
        }],
        "address": {
            "lines": [address_line],
            "city": city,
            "subdivision": None,
            "postal_code": postal,
            "country_code": country,
        },
        "electronic_addresses": [],
    }


def make_spec(
    fixture_id: str,
    title: str,
    supplier: dict,
    buyer: dict | None,
    invoice_number: str | None,
    currency: str | None,
    lines: list[dict],
    tax_components: list[dict],
    document_type="invoice",
    issue_date=TODAY,
    due_days=30,
    references=None,
    allowance=Decimal("0"),
    charge=Decimal("0"),
    prepaid=Decimal("0"),
    withholding=Decimal("0"),
    rounding=Decimal("0"),
    payment_terms="Payment due in 30 days",
    notes=None,
    display_invoice_numbers=None,
    force_payable=None,
    layout="standard",
):
    currency_for_math = currency or "USD"
    line_total = sum(dec(x["quantity"]) * dec(x["unit_price"]) for x in lines)
    line_total = q(line_total, currency_for_math)
    tax_breakdowns = []
    total_tax_add = Decimal("0")
    total_tax_withheld = Decimal("0")
    for t in tax_components:
        base = dec(t.get("taxable_amount", line_total))
        rate = dec(t.get("rate", 0))
        amount = dec(t.get("tax_amount", q(base * rate / 100, currency_for_math)))
        effect = t.get("payable_effect", "add")
        if effect == "subtract":
            total_tax_withheld += amount
        else:
            total_tax_add += amount
        tax_breakdowns.append({**t, "taxable_amount": base, "tax_amount": amount})
    tax_exclusive = line_total - allowance + charge
    tax_inclusive = tax_exclusive + total_tax_add
    payable = tax_inclusive - prepaid - withholding - total_tax_withheld + rounding
    if force_payable is not None:
        payable = dec(force_payable)
    return {
        "fixture_id": fixture_id,
        "title": title,
        "supplier": supplier,
        "buyer": buyer,
        "invoice_number": invoice_number,
        "display_invoice_numbers": display_invoice_numbers or ([invoice_number] if invoice_number else []),
        "currency": currency,
        "lines": lines,
        "tax_breakdowns": tax_breakdowns,
        "document_type": document_type,
        "issue_date": issue_date,
        "due_date": issue_date + timedelta(days=due_days) if due_days is not None else None,
        "references": references or [],
        "allowance": allowance,
        "charge": charge,
        "prepaid": prepaid,
        "withholding": withholding,
        "rounding": rounding,
        "line_total": line_total,
        "tax_exclusive": tax_exclusive,
        "total_tax_add": total_tax_add,
        "total_tax_withheld": total_tax_withheld,
        "tax_inclusive": tax_inclusive,
        "payable": payable,
        "payment_terms": payment_terms,
        "notes": notes or [],
        "layout": layout,
    }


SUPPLIERS = {
    "US": party("Blue Mesa Office Supply LLC", "US", "Austin", "78701", "EIN", "84-7392011", "401 Congress Avenue"),
    "GB": party("Northstar Services Ltd", "GB", "London", "EC1A 1AA", "VAT", "GB123456789", "10 Example Street"),
    "DE": party("Rhein Data GmbH", "DE", "Berlin", "10115", "VAT", "DE321654987", "22 Lindenstrasse"),
    "IN": party("Saffron Cloud Solutions Pvt Ltd", "IN", "Bengaluru", "560001", "GSTIN", "29ABCDE1234F1Z5", "15 Residency Road"),
    "JP": party("Hikari Office Systems KK", "JP", "Tokyo", "100-0005", "BUSINESS_ID", "JP-HOS-2026", "2-7 Marunouchi"),
    "KW": party("Pearl Gulf Trading WLL", "KW", "Kuwait City", "13001", "BUSINESS_ID", "KW-PT-77881", "Sharq, Block 4"),
    "AE": party("Desert Byte Technologies FZ-LLC", "AE", "Dubai", "00000", "TRN", "100234567800003", "Dubai Internet City"),
    "CA": party("Maple Ridge Equipment Inc", "CA", "Toronto", "M5V 2T6", "BN", "812345678RT0001", "120 King Street West"),
    "MX": party("Luz Verde Consultoria SA de CV", "MX", "Mexico City", "06600", "RFC", "LVC260101AB1", "Paseo de la Reforma 120"),
}
BUYERS = {
    "US": party("Cobalt Workshop Inc", "US", "Seattle", "98101", "EIN", "91-4920071", "81 Pine Street"),
    "FR": party("Example Buyer SAS", "FR", "Paris", "75001", "VAT", "FRXX123456789", "20 Rue Exemple"),
    "IN": party("Riverstone Retail LLP", "IN", "Bengaluru", "560038", "GSTIN", "29AAECR0000A1Z2", "44 Indiranagar Main Road"),
    "JP": party("Aoba Design Studio", "JP", "Yokohama", "220-0012", "BUSINESS_ID", "JP-ADS-4420", "1-1 Minatomirai"),
    "AE": party("Harbour Analytics LLC", "AE", "Abu Dhabi", "00000", "TRN", "100987654300003", "Al Maryah Island"),
    "CA": party("Northern Trail Foods Ltd", "CA", "Vancouver", "V6B 1A1", "BN", "701234567RT0001", "55 Water Street"),
    "MX": party("Orion Logistics Mexico SA", "MX", "Monterrey", "64000", "RFC", "OLM260110ZZ4", "Avenida Hidalgo 88"),
}

SPECS = []
SPECS.append(make_spec("INV-001", "US office supplies with sales tax", SUPPLIERS["US"], BUYERS["US"], "US-260629-001", "USD", [
    {"description": "Ergonomic keyboard", "quantity": 2, "unit_price": "89.50", "unit_code": "EA"},
    {"description": "USB-C docking station", "quantity": 1, "unit_price": "179.00", "unit_code": "EA"},
], [{"tax_type": "SALES_TAX", "component": None, "jurisdiction_code": "US-TX", "category_code": "STANDARD", "rate": "8.25", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "Texas sales tax 8.25%"}], references=[("purchase_order", "PO-9821")]))
SPECS.append(make_spec("INV-002", "UK VAT services invoice", SUPPLIERS["GB"], BUYERS["FR"], "INV-2026-1042", "GBP", [
    {"description": "Monthly bookkeeping services", "quantity": 1, "unit_price": "1250.00", "unit_code": "MON"},
], [{"tax_type": "VAT", "component": None, "jurisdiction_code": "GB", "category_code": "S", "rate": "20", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "VAT 20%"}], references=[("purchase_order", "PO-8842")]))
SPECS.append(make_spec("INV-003", "EU cross-border reverse-charge invoice", SUPPLIERS["DE"], BUYERS["FR"], "RD-2026-771", "EUR", [
    {"description": "Data migration consultancy", "quantity": 16, "unit_price": "110.00", "unit_code": "HUR"},
], [{"tax_type": "VAT", "component": None, "jurisdiction_code": "EU", "category_code": "AE", "rate": "0", "tax_amount": "0", "payable_effect": "add", "exemption_code": "REVERSE_CHARGE", "exemption_reason": "Reverse charge - customer accounts for VAT", "reverse_charge": True, "source_label": "VAT reverse charge"}], references=[("contract", "MSA-2026-11")]))
SPECS.append(make_spec("INV-004", "India GST goods invoice", SUPPLIERS["IN"], BUYERS["IN"], "SC-4521", "INR", [
    {"description": "Wi-Fi 6 access point", "quantity": 4, "unit_price": "8500.00", "unit_code": "EA", "classification": ("HSN", "851762")},
    {"description": "Installation service", "quantity": 1, "unit_price": "6000.00", "unit_code": "EA", "classification": ("SAC", "998713")},
], [
    {"tax_type": "GST", "component": "CGST", "jurisdiction_code": "IN-KA", "category_code": "STANDARD", "rate": "9", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "CGST 9%"},
    {"tax_type": "GST", "component": "SGST", "jurisdiction_code": "IN-KA", "category_code": "STANDARD", "rate": "9", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "SGST 9%"},
], references=[("purchase_order", "PO-IN-224")]))
SPECS.append(make_spec("INV-005", "Japan JPY zero-decimal invoice", SUPPLIERS["JP"], BUYERS["JP"], "HOS-8841", "JPY", [
    {"description": "Office printer maintenance", "quantity": 1, "unit_price": "28500", "unit_code": "EA"},
    {"description": "Replacement toner", "quantity": 2, "unit_price": "6400", "unit_code": "EA"},
], [], payment_terms="Payable within 14 days"))
SPECS.append(make_spec("INV-006", "KWD three-decimal currency invoice", SUPPLIERS["KW"], BUYERS["AE"], "PG-000981", "KWD", [
    {"description": "Industrial sensor module", "quantity": 3, "unit_price": "47.375", "unit_code": "EA"},
    {"description": "Calibration certificate", "quantity": 1, "unit_price": "12.250", "unit_code": "EA"},
], [], charge=Decimal("3.500"), payment_terms="Payment due within 21 days"))
SPECS.append(make_spec("INV-007", "UAE VAT invoice", SUPPLIERS["AE"], BUYERS["AE"], "DBT-2026-611", "AED", [
    {"description": "Cloud monitoring subscription", "quantity": 3, "unit_price": "800.00", "unit_code": "MON"},
], [{"tax_type": "VAT", "component": None, "jurisdiction_code": "AE", "category_code": "STANDARD", "rate": "5", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "VAT 5%"}]))
SPECS.append(make_spec("INV-008", "Canada HST invoice", SUPPLIERS["CA"], BUYERS["CA"], "MRE-22671", "CAD", [
    {"description": "Commercial mixer replacement part", "quantity": 2, "unit_price": "345.00", "unit_code": "EA"},
    {"description": "Courier freight", "quantity": 1, "unit_price": "48.00", "unit_code": "EA"},
], [{"tax_type": "GST", "component": "HST", "jurisdiction_code": "CA-ON", "category_code": "STANDARD", "rate": "13", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "HST 13%"}]))
SPECS.append(make_spec("INV-009", "EUR credit note", SUPPLIERS["DE"], BUYERS["FR"], "CN-2026-044", "EUR", [
    {"description": "Credit for overbilled consultancy hour", "quantity": -2, "unit_price": "110.00", "unit_code": "HUR"},
], [{"tax_type": "VAT", "component": None, "jurisdiction_code": "EU", "category_code": "AE", "rate": "0", "tax_amount": "0", "payable_effect": "add", "exemption_code": "REVERSE_CHARGE", "exemption_reason": "Reverse charge", "reverse_charge": True, "source_label": "VAT reverse charge"}], document_type="credit_note", references=[("original_invoice", "RD-2026-771")], payment_terms="Credit applied to customer account"))
SPECS.append(make_spec("INV-010", "Simple retail receipt", SUPPLIERS["US"], None, "R-884201", "USD", [
    {"description": "Notebook", "quantity": 2, "unit_price": "6.50", "unit_code": "EA"},
    {"description": "Gel pen pack", "quantity": 1, "unit_price": "9.25", "unit_code": "EA"},
], [{"tax_type": "SALES_TAX", "component": None, "jurisdiction_code": "US-TX", "category_code": "STANDARD", "rate": "8.25", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "Sales tax 8.25%"}], document_type="receipt", due_days=None, payment_terms="Paid by card"))
SPECS.append(make_spec("INV-011", "Multi-page line-item invoice", SUPPLIERS["DE"], BUYERS["FR"], "RD-2026-889", "EUR", [
    {"description": f"Migration work package {i:02d}", "quantity": 1 + (i % 3), "unit_price": str(75 + i * 8), "unit_code": "HUR"} for i in range(1, 43)
], [{"tax_type": "VAT", "component": None, "jurisdiction_code": "DE", "category_code": "S", "rate": "19", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "VAT 19%"}], references=[("project", "MIGRATION-ALPHA")], layout="multipage"))
SPECS.append(make_spec("INV-012", "Invoice with allowance and charge", SUPPLIERS["GB"], BUYERS["FR"], "NS-2606-99", "GBP", [
    {"description": "Quarterly accounting support", "quantity": 1, "unit_price": "2100.00", "unit_code": "QTR"},
], [{"tax_type": "VAT", "component": None, "jurisdiction_code": "GB", "category_code": "S", "rate": "20", "taxable_amount": "2000.00", "tax_amount": "400.00", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "VAT 20%"}], allowance=Decimal("150.00"), charge=Decimal("50.00"), notes=["Loyalty allowance: 150.00", "Expedited reporting charge: 50.00"]))
SPECS.append(make_spec("INV-013", "Mexico VAT and withholding invoice", SUPPLIERS["MX"], BUYERS["MX"], "LVC-2026-321", "MXN", [
    {"description": "Professional advisory services", "quantity": 1, "unit_price": "18000.00", "unit_code": "EA"},
], [
    {"tax_type": "VAT", "component": "IVA", "jurisdiction_code": "MX", "category_code": "STANDARD", "rate": "16", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "IVA 16%"},
    {"tax_type": "WITHHOLDING", "component": "ISR", "jurisdiction_code": "MX", "category_code": "WITHHELD", "rate": "10", "tax_amount": "1800.00", "payable_effect": "subtract", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "ISR withholding 10%"},
], payment_terms="Bank transfer within 10 days"))
SPECS.append(make_spec("INV-014", "Arithmetic mismatch invoice", SUPPLIERS["US"], BUYERS["US"], "US-260629-ERR", "USD", [
    {"description": "Laptop stand", "quantity": 3, "unit_price": "42.00", "unit_code": "EA"},
], [{"tax_type": "SALES_TAX", "component": None, "jurisdiction_code": "US-WA", "category_code": "STANDARD", "rate": "10", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "Sales tax 10%"}], force_payable="151.00", notes=["Intentionally wrong payable total for validator testing"] ))
SPECS.append(make_spec("INV-015", "Missing currency invoice", SUPPLIERS["GB"], BUYERS["FR"], "NS-NOCUR-15", None, [
    {"description": "Monthly payroll support", "quantity": 1, "unit_price": "900.00", "unit_code": "MON"},
], [{"tax_type": "VAT", "component": None, "jurisdiction_code": "GB", "category_code": "S", "rate": "20", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "VAT 20%"}], notes=["Currency symbol and ISO code intentionally omitted"] ))
SPECS.append(make_spec("INV-016", "Ambiguous invoice number", SUPPLIERS["AE"], BUYERS["AE"], None, "AED", [
    {"description": "Network assessment", "quantity": 1, "unit_price": "3500.00", "unit_code": "EA"},
], [{"tax_type": "VAT", "component": None, "jurisdiction_code": "AE", "category_code": "STANDARD", "rate": "5", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "VAT 5%"}], display_invoice_numbers=["Reference DBT-778", "Tax invoice 2026/0616"], notes=["Two plausible invoice identifiers intentionally shown"] ))
DUP_BASE = make_spec("INV-017A", "Duplicate candidate original", SUPPLIERS["CA"], BUYERS["CA"], "MRE-DUP-1007", "CAD", [
    {"description": "Replacement belt assembly", "quantity": 4, "unit_price": "88.00", "unit_code": "EA"},
], [{"tax_type": "GST", "component": "HST", "jurisdiction_code": "CA-ON", "category_code": "STANDARD", "rate": "13", "payable_effect": "add", "exemption_code": None, "exemption_reason": None, "reverse_charge": False, "source_label": "HST 13%"}])
SPECS.append(DUP_BASE)
DUP_COPY = deepcopy(DUP_BASE); DUP_COPY["fixture_id"] = "INV-017B"; DUP_COPY["title"] = "Duplicate candidate copy"; DUP_COPY["notes"] = ["Same business invoice as INV-017A; different file identity"]
SPECS.append(DUP_COPY)


def page_header(canvas, doc, title):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#64748B"))
    canvas.drawRightString(doc.pagesize[0] - 18 * mm, 10 * mm, f"Synthetic test fixture - {title} - Page {doc.page}")
    canvas.restoreState()


def render_invoice_pdf(spec: dict, out: Path):
    pagesize = A4 if spec["fixture_id"] not in {"INV-001", "INV-010"} else LETTER
    doc = BaseDocTemplate(str(out), pagesize=pagesize, leftMargin=18*mm, rightMargin=18*mm, topMargin=14*mm, bottomMargin=16*mm)
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="normal")
    doc.addPageTemplates([PageTemplate(id="invoice", frames=frame, onPage=lambda c,d: page_header(c,d,spec["fixture_id"]))])
    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(name="InvoiceTitle", parent=styles["Title"], fontName="Helvetica-Bold", fontSize=22, leading=26, textColor=colors.HexColor("#17324D"), alignment=TA_RIGHT))
    styles.add(ParagraphStyle(name="Small", parent=styles["Normal"], fontSize=8.5, leading=11))
    styles.add(ParagraphStyle(name="RightSmall", parent=styles["Small"], alignment=TA_RIGHT))
    styles.add(ParagraphStyle(name="Section", parent=styles["Heading3"], fontSize=10, textColor=colors.HexColor("#2856A8"), spaceBefore=5, spaceAfter=4))
    story = []
    doc_label = {"invoice":"INVOICE", "tax_invoice":"TAX INVOICE", "receipt":"RECEIPT", "credit_note":"CREDIT NOTE", "debit_note":"DEBIT NOTE"}.get(spec["document_type"], spec["document_type"].upper())
    supplier_lines = [f"<b>{spec['supplier']['display_name']}</b>", *spec['supplier']['address']['lines'], f"{spec['supplier']['address']['city']} {spec['supplier']['address']['postal_code']}", spec['supplier']['address']['country_code']]
    for ident in spec['supplier']['identifiers']:
        supplier_lines.append(f"{ident['scheme']}: {ident['value']}")
    meta_lines = [f"<b>{doc_label}</b>"]
    for label in spec["display_invoice_numbers"]:
        if label:
            meta_lines.append(f"Invoice/Ref: {label}")
    meta_lines += [f"Issue date: {spec['issue_date'].isoformat()}"]
    if spec["due_date"]:
        meta_lines.append(f"Due date: {spec['due_date'].isoformat()}")
    if spec["currency"]:
        meta_lines.append(f"Currency: {spec['currency']}")
    header = Table([[Paragraph("<br/>".join(supplier_lines), styles["Small"]), Paragraph("<br/>".join(meta_lines), styles["RightSmall"])]], colWidths=[doc.width*0.58, doc.width*0.42])
    header.setStyle(TableStyle([("VALIGN", (0,0), (-1,-1), "TOP"), ("BOTTOMPADDING", (0,0), (-1,-1), 8)]))
    story += [header, Spacer(1, 4*mm)]
    if spec["buyer"]:
        b = spec["buyer"]
        buyer_text = [f"<b>Bill to</b>", b["display_name"], *b["address"]["lines"], f"{b['address']['city']} {b['address']['postal_code']}", b['address']['country_code']]
        for ident in b["identifiers"]:
            buyer_text.append(f"{ident['scheme']}: {ident['value']}")
        story += [Paragraph("<br/>".join(buyer_text), styles["Small"]), Spacer(1, 4*mm)]
    if spec["references"]:
        story.append(Paragraph(" | ".join(f"{t.replace('_',' ').title()}: {v}" for t,v in spec["references"]), styles["Small"]))
        story.append(Spacer(1, 3*mm))
    data = [["#", "Description", "Qty", "Unit", "Unit price", "Line net"]]
    currency_display = spec["currency"] or ""
    for idx, line in enumerate(spec["lines"], start=1):
        qty = dec(line["quantity"]); price = dec(line["unit_price"]); net = q(qty*price, spec["currency"] or "USD")
        desc = line["description"]
        if line.get("classification"):
            desc += f"\n{line['classification'][0]}: {line['classification'][1]}"
        data.append([str(idx), desc, dstr(qty, keep_rate=True), line.get("unit_code", "EA"), f"{currency_display} {dstr(price, spec['currency'] or 'USD')}", f"{currency_display} {dstr(net, spec['currency'] or 'USD')}"])
    table = Table(data, repeatRows=1, colWidths=[10*mm, doc.width-82*mm, 15*mm, 16*mm, 22*mm, 24*mm])
    table.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,0), colors.HexColor("#2856A8")),
        ("TEXTCOLOR", (0,0), (-1,0), colors.white),
        ("FONTNAME", (0,0), (-1,0), "Helvetica-Bold"),
        ("FONTSIZE", (0,0), (-1,-1), 8),
        ("GRID", (0,0), (-1,-1), 0.4, colors.HexColor("#CBD5E1")),
        ("VALIGN", (0,0), (-1,-1), "TOP"),
        ("ALIGN", (2,1), (-1,-1), "RIGHT"),
        ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, colors.HexColor("#F8FAFC")]),
        ("TOPPADDING", (0,0), (-1,-1), 5),
        ("BOTTOMPADDING", (0,0), (-1,-1), 5),
    ]))
    story += [table, Spacer(1, 5*mm)]
    ccy = spec["currency"] or ""
    summary = [
        ["Line subtotal", f"{ccy} {dstr(spec['line_total'], spec['currency'] or 'USD')}"]
    ]
    if spec["allowance"]:
        summary.append(["Allowance", f"- {ccy} {dstr(spec['allowance'], spec['currency'] or 'USD')}"])
    if spec["charge"]:
        summary.append(["Charges", f"{ccy} {dstr(spec['charge'], spec['currency'] or 'USD')}"])
    for tax in spec["tax_breakdowns"]:
        sign = "- " if tax["payable_effect"] == "subtract" else ""
        summary.append([tax["source_label"], f"{sign}{ccy} {dstr(tax['tax_amount'], spec['currency'] or 'USD')}"])
    if spec["prepaid"]:
        summary.append(["Prepaid", f"- {ccy} {dstr(spec['prepaid'], spec['currency'] or 'USD')}"])
    if spec["rounding"]:
        summary.append(["Rounding", f"{ccy} {dstr(spec['rounding'], spec['currency'] or 'USD')}"])
    summary.append(["AMOUNT DUE", f"{ccy} {dstr(spec['payable'], spec['currency'] or 'USD')}"])
    sum_table = Table(summary, colWidths=[55*mm, 38*mm], hAlign="RIGHT")
    sum_table.setStyle(TableStyle([
        ("ALIGN", (1,0), (1,-1), "RIGHT"),
        ("FONTNAME", (0,-1), (-1,-1), "Helvetica-Bold"),
        ("FONTSIZE", (0,0), (-1,-1), 9),
        ("LINEABOVE", (0,-1), (-1,-1), 1, colors.HexColor("#17324D")),
        ("TOPPADDING", (0,0), (-1,-1), 4),
        ("BOTTOMPADDING", (0,0), (-1,-1), 4),
    ]))
    story.append(sum_table)
    story.append(Spacer(1, 5*mm))
    story.append(Paragraph(f"<b>Payment terms:</b> {spec['payment_terms']}", styles["Small"]))
    for note in spec["notes"]:
        story.append(Paragraph(note, styles["Small"]))
    story.append(Spacer(1, 4*mm))
    story.append(Paragraph("This document is synthetic and contains no real customer or financial data.", styles["Small"]))
    doc.build(story)


def canonical_from_spec(spec: dict, source_family="visual_pdf", route="visual_model", mime="application/pdf", page_count=1, profile=None, has_embedded=False):
    ccy = spec["currency"]
    math_ccy = ccy or "USD"
    line_items = []
    for idx, line in enumerate(spec["lines"], start=1):
        qty = dec(line["quantity"]); price = dec(line["unit_price"]); net = q(qty*price, math_ccy)
        line_tax = []
        for tax in spec["tax_breakdowns"]:
            base_ratio = Decimal("0") if spec["line_total"] == 0 else net/spec["line_total"]
            tax_amount = q(tax["tax_amount"]*base_ratio, math_ccy)
            line_tax.append({
                "tax_type": tax["tax_type"], "component": tax.get("component"), "jurisdiction_code": tax.get("jurisdiction_code"),
                "category_code": tax.get("category_code"), "rate": dstr(dec(tax.get("rate",0)), keep_rate=True),
                "taxable_amount": dstr(net, math_ccy), "tax_amount": dstr(tax_amount, math_ccy),
                "payable_effect": tax.get("payable_effect","add"), "exemption_code": tax.get("exemption_code"),
                "exemption_reason": tax.get("exemption_reason"), "reverse_charge": bool(tax.get("reverse_charge",False)),
                "source_label": tax.get("source_label"),
            })
        classifications=[]
        if line.get("classification"):
            classifications=[{"scheme":line["classification"][0],"value":line["classification"][1]}]
        line_gross = net + sum((dec(x["tax_amount"]) if x["payable_effect"]=="add" else -dec(x["tax_amount"])) for x in line_tax)
        line_items.append({
            "line_id": f"line_{idx}", "line_no": idx, "description": line["description"], "item_name": line["description"],
            "seller_item_id": None, "buyer_item_id": None, "classifications": classifications,
            "quantity": dstr(qty, keep_rate=True), "unit_code": line.get("unit_code","EA"),
            "unit_price": dstr(price, math_ccy), "price_base_quantity": "1", "allowances_charges": [],
            "line_net_amount": dstr(net, math_ccy), "tax_breakdowns": line_tax,
            "line_gross_amount": dstr(q(line_gross, math_ccy), math_ccy), "service_period": None,
        })
    tax_breakdowns=[]
    for tax in spec["tax_breakdowns"]:
        tax_breakdowns.append({
            "tax_type": tax["tax_type"], "component": tax.get("component"), "jurisdiction_code": tax.get("jurisdiction_code"),
            "category_code": tax.get("category_code"), "rate": dstr(dec(tax.get("rate",0)), keep_rate=True),
            "taxable_amount": dstr(dec(tax["taxable_amount"]), math_ccy), "tax_amount": dstr(dec(tax["tax_amount"]), math_ccy),
            "payable_effect": tax.get("payable_effect","add"), "exemption_code": tax.get("exemption_code"),
            "exemption_reason": tax.get("exemption_reason"), "reverse_charge": bool(tax.get("reverse_charge",False)),
            "source_label": tax.get("source_label"),
        })
    allowances=[]
    if spec["allowance"]:
        allowances.append({"charge_indicator":False,"amount":dstr(spec["allowance"],math_ccy),"base_amount":dstr(spec["line_total"],math_ccy),"percentage":None,"reason_code":None,"reason":"Invoice allowance"})
    if spec["charge"]:
        allowances.append({"charge_indicator":True,"amount":dstr(spec["charge"],math_ccy),"base_amount":dstr(spec["line_total"],math_ccy),"percentage":None,"reason_code":None,"reason":"Invoice charge"})
    supplier_country=spec["supplier"]["address"]["country_code"]
    buyer_country=spec["buyer"]["address"]["country_code"] if spec["buyer"] else None
    evidence=[]
    if spec["display_invoice_numbers"]:
        evidence.append({"field_path":"/invoice/number","source_kind":"visual" if route!="structured_parser" else "standalone_structured","page":1 if route!="structured_parser" else None,"source_path":None if route!="structured_parser" else "/Invoice/ID","text":" | ".join(spec["display_invoice_numbers"]),"bbox":None})
    evidence.extend([
        {"field_path":"/invoice/issue_date","source_kind":"visual" if route!="structured_parser" else "standalone_structured","page":1 if route!="structured_parser" else None,"source_path":None if route!="structured_parser" else "/Invoice/IssueDate","text":spec["issue_date"].isoformat(),"bbox":None},
        {"field_path":"/totals/payable_amount","source_kind":"visual" if route!="structured_parser" else "standalone_structured","page":page_count if route!="structured_parser" else None,"source_path":None if route!="structured_parser" else "/Invoice/LegalMonetaryTotal/PayableAmount","text":f"{ccy or ''} {dstr(spec['payable'],math_ccy)}".strip(),"bbox":None},
    ])
    uncertainties=[]
    if not spec["invoice_number"]:
        uncertainties.append({"code":"AMBIGUOUS_INVOICE_NUMBER","field_paths":["/invoice/number"],"message":"Multiple plausible document identifiers are visible.","candidate_values":spec["display_invoice_numbers"]})
    if not ccy:
        uncertainties.append({"code":"MISSING_CURRENCY","field_paths":["/invoice/currency"],"message":"No currency symbol or ISO code is present.","candidate_values":[]})
    return {
        "schema_version":"2.0", "document_id":f"synthetic_{spec['fixture_id'].lower().replace('-','_')}", "document_type":spec["document_type"],
        "source":{"family":source_family,"route":route,"mime_type":mime,"profile":profile,"profile_version":None,"page_count":page_count,"has_embedded_structured_data":has_embedded},
        "locale":{"document_language":"en","script":"Latn","supplier_country":supplier_country,"buyer_country":buyer_country,"jurisdiction_candidates":list(dict.fromkeys(x for x in [supplier_country,buyer_country] if x)),"applied_region_pack":{"id":"global_generic_v1","version":"1.0.0","resolution":"generic_fallback"}},
        "supplier":spec["supplier"], "buyer":spec["buyer"], "payee":None,
        "invoice":{"number":spec["invoice_number"],"issue_date":spec["issue_date"].isoformat(),"due_date":spec["due_date"].isoformat() if spec["due_date"] else None,"tax_point_date":None,"currency":ccy,"tax_currency":None,"service_period":None,"payment_terms_text":spec["payment_terms"]},
        "references":[{"type":t,"value":v,"scheme":None,"issue_date":None} for t,v in spec["references"]],
        "allowances_charges":allowances,
        "totals":{"line_extension_amount":dstr(spec["line_total"],math_ccy),"allowance_total_amount":dstr(spec["allowance"],math_ccy),"charge_total_amount":dstr(spec["charge"],math_ccy),"tax_exclusive_amount":dstr(spec["tax_exclusive"],math_ccy),"total_tax_amount":dstr(spec["total_tax_add"],math_ccy),"tax_inclusive_amount":dstr(spec["tax_inclusive"],math_ccy),"prepaid_amount":dstr(spec["prepaid"],math_ccy),"withholding_total_amount":dstr(spec["withholding"]+spec["total_tax_withheld"],math_ccy),"rounding_amount":dstr(spec["rounding"],math_ccy),"payable_amount":dstr(spec["payable"],math_ccy)},
        "tax_breakdowns":tax_breakdowns, "line_items":line_items,
        "payment":{"means":[{"type_code":"30","type_label":"Credit transfer","payment_reference":spec["invoice_number"],"account_last4":None,"iban_last4":None,"bic":None}],"terms_text":spec["payment_terms"]} if spec["document_type"]!="receipt" else {"means":[{"type_code":"48","type_label":"Payment card","payment_reference":spec["invoice_number"],"account_last4":"4242","iban_last4":None,"bic":None}],"terms_text":"Paid"},
        "evidence":evidence, "uncertainties":uncertainties,
    }


def expected_findings(spec: dict):
    findings=[]
    if spec["fixture_id"]=="INV-014":
        findings.append({"code":"PAYABLE_AMOUNT_MISMATCH","severity":"CRITICAL","field_paths":["/totals/payable_amount"],"expected":"138.60","observed":"151.00","resolution":"operator_correction_required"})
    if spec["fixture_id"]=="INV-015":
        findings.append({"code":"CURRENCY_REQUIRED","severity":"CRITICAL","field_paths":["/invoice/currency"],"resolution":"operator_confirmation_required"})
    if spec["fixture_id"]=="INV-016":
        findings.append({"code":"AMBIGUOUS_INVOICE_NUMBER","severity":"HIGH","field_paths":["/invoice/number"],"resolution":"operator_confirmation_required"})
    if spec["fixture_id"]=="INV-017B":
        findings.append({"code":"DUPLICATE_CANDIDATE","severity":"HIGH","field_paths":["/supplier/identifiers","/invoice/number","/totals/payable_amount"],"duplicate_of":"INV-017A","resolution":"operator_confirmation_required"})
    if not findings:
        findings.append({"code":"REGIONAL_SEMANTICS_NOT_APPLIED","severity":"INFO","field_paths":[],"resolution":"none"})
    return findings


def pdf_to_image(pdf_path: Path, page=0, dpi=170) -> Image.Image:
    doc=fitz.open(pdf_path); p=doc.load_page(page); pix=p.get_pixmap(matrix=fitz.Matrix(dpi/72,dpi/72), alpha=False); doc.close()
    return Image.frombytes("RGB", [pix.width,pix.height], pix.samples)


def image_to_pdf(image_path: Path, out: Path):
    img=Image.open(image_path).convert("RGB")
    img.save(out, "PDF", resolution=150.0)


def add_embedded_file(pdf_path: Path, attachment_path: Path, out: Path):
    doc=fitz.open(pdf_path)
    doc.embfile_add(attachment_path.name, attachment_path.read_bytes(), filename=attachment_path.name, ufilename=attachment_path.name, desc="Synthetic UBL payload")
    doc.save(out)
    doc.close()


def make_ubl(spec: dict, out: Path):
    ccy=spec["currency"] or "USD"
    lines=[]
    for i,line in enumerate(spec["lines"],start=1):
        qty=dstr(dec(line["quantity"]),keep_rate=True); price=dstr(dec(line["unit_price"]),ccy); net=dstr(q(dec(line["quantity"])*dec(line["unit_price"]),ccy),ccy)
        lines.append(f'''  <cac:InvoiceLine>\n    <cbc:ID>{i}</cbc:ID>\n    <cbc:InvoicedQuantity unitCode="{line.get('unit_code','EA')}">{qty}</cbc:InvoicedQuantity>\n    <cbc:LineExtensionAmount currencyID="{ccy}">{net}</cbc:LineExtensionAmount>\n    <cac:Item><cbc:Description>{line['description']}</cbc:Description></cac:Item>\n    <cac:Price><cbc:PriceAmount currencyID="{ccy}">{price}</cbc:PriceAmount></cac:Price>\n  </cac:InvoiceLine>''')
    xml=f'''<?xml version="1.0" encoding="UTF-8"?>\n<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">\n  <cbc:CustomizationID>urn:synthetic:global-invoice:1</cbc:CustomizationID>\n  <cbc:ID>{spec['invoice_number']}</cbc:ID>\n  <cbc:IssueDate>{spec['issue_date'].isoformat()}</cbc:IssueDate>\n  <cbc:DocumentCurrencyCode>{ccy}</cbc:DocumentCurrencyCode>\n  <cac:AccountingSupplierParty><cac:Party><cac:PartyName><cbc:Name>{spec['supplier']['display_name']}</cbc:Name></cac:PartyName></cac:Party></cac:AccountingSupplierParty>\n  <cac:AccountingCustomerParty><cac:Party><cac:PartyName><cbc:Name>{spec['buyer']['display_name'] if spec['buyer'] else 'Cash Customer'}</cbc:Name></cac:PartyName></cac:Party></cac:AccountingCustomerParty>\n  <cac:LegalMonetaryTotal>\n    <cbc:LineExtensionAmount currencyID="{ccy}">{dstr(spec['line_total'],ccy)}</cbc:LineExtensionAmount>\n    <cbc:TaxExclusiveAmount currencyID="{ccy}">{dstr(spec['tax_exclusive'],ccy)}</cbc:TaxExclusiveAmount>\n    <cbc:TaxInclusiveAmount currencyID="{ccy}">{dstr(spec['tax_inclusive'],ccy)}</cbc:TaxInclusiveAmount>\n    <cbc:PayableAmount currencyID="{ccy}">{dstr(spec['payable'],ccy)}</cbc:PayableAmount>\n  </cac:LegalMonetaryTotal>\n{os.linesep.join(lines)}\n</Invoice>\n'''
    out.write_text(xml,encoding="utf-8")


def sha(path: Path):
    h=hashlib.sha256();
    with path.open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""):h.update(chunk)
    return h.hexdigest()


def main():
    manifest=[]
    spec_by_id={s["fixture_id"]:s for s in SPECS}
    for spec in SPECS:
        pdf=PDF_DIR/f"{spec['fixture_id'].lower()}_{spec['title'].lower().replace(' ','_').replace('/','_')}.pdf"
        render_invoice_pdf(spec,pdf)
        doc=fitz.open(pdf); pages=doc.page_count; doc.close()
        canonical=canonical_from_spec(spec,page_count=pages)
        (GT_DIR/f"{spec['fixture_id']}.json").write_text(json.dumps(canonical,indent=2,ensure_ascii=False),encoding="utf-8")
        (FIND_DIR/f"{spec['fixture_id']}.json").write_text(json.dumps(expected_findings(spec),indent=2),encoding="utf-8")
        manifest.append({"fixture_id":spec["fixture_id"],"file":str(pdf.relative_to(CORPUS)),"kind":"visual_pdf","split":"functional","document_type":spec["document_type"],"currency":spec["currency"] or "UNKNOWN","country":spec["supplier"]["address"]["country_code"],"expected_route":"visual_model","expected_status":"needs_review" if spec["fixture_id"] in {"INV-014","INV-015","INV-016","INV-017B"} else "ready_for_approval","ground_truth":f"ground_truth/{spec['fixture_id']}.json","expected_findings":f"expected_findings/{spec['fixture_id']}.json","notes":spec["title"]})

    # Image variants from representative PDFs
    source_map={s["fixture_id"]: next(PDF_DIR.glob(f"{s['fixture_id'].lower()}_*.pdf")) for s in SPECS}
    variants=[]
    # Low-quality blurred scan
    img=pdf_to_image(source_map["INV-002"],dpi=110).resize((900,1160)); img=img.filter(ImageFilter.GaussianBlur(1.6)); img=ImageEnhance.Contrast(img).enhance(0.82)
    p=IMG_DIR/"IMG-001_blurred_low_resolution_scan.jpg"; img.save(p,quality=48)
    image_to_pdf(p,PDF_DIR/"IMG-001_blurred_low_resolution_scan.pdf")
    variants.append(("IMG-001",p,"INV-002","image","visual_model","needs_review","LOW_IMAGE_QUALITY"))
    # Rotated image
    img=pdf_to_image(source_map["INV-003"],dpi=150).rotate(90,expand=True)
    p=IMG_DIR/"IMG-002_rotated_90_degrees.png"; img.save(p)
    variants.append(("IMG-002",p,"INV-003","image","visual_model","needs_review","ROTATION_DETECTED"))
    # Phone photo effect
    base=pdf_to_image(source_map["INV-004"],dpi=130); base.thumbnail((1000,1300))
    canvas=Image.new("RGB",(1300,1700),(64,73,80)); shadow=Image.new("RGBA",(base.width+80,base.height+80),(0,0,0,0)); sd=ImageDraw.Draw(shadow); sd.rounded_rectangle((30,30,base.width+50,base.height+50),radius=18,fill=(0,0,0,110)); shadow=shadow.filter(ImageFilter.GaussianBlur(14)); canvas.paste(shadow,(110,120),shadow); tilted=base.rotate(-4,expand=True,fillcolor="white"); canvas.paste(tilted,(150,150)); p=IMG_DIR/"IMG-003_phone_photo_skew.jpg"; canvas.save(p,quality=82)
    variants.append(("IMG-003",p,"INV-004","image","visual_model","needs_review","PERSPECTIVE_SKEW"))
    # PNG receipt
    img=pdf_to_image(source_map["INV-010"],dpi=150); p=IMG_DIR/"IMG-004_receipt.png"; img.save(p)
    variants.append(("IMG-004",p,"INV-010","image","visual_model","ready_for_approval",None))
    # Multi-page TIFF
    d=fitz.open(source_map["INV-011"]); tiff_pages=[]
    for i in range(d.page_count):
        pix=d.load_page(i).get_pixmap(matrix=fitz.Matrix(1.6,1.6),alpha=False)
        tiff_pages.append(Image.frombytes("RGB",[pix.width,pix.height],pix.samples))
    d.close(); p=IMG_DIR/"IMG-005_multipage_invoice.tiff"; tiff_pages[0].save(p,save_all=True,append_images=tiff_pages[1:],compression="tiff_deflate")
    variants.append(("IMG-005",p,"INV-011","image","visual_model","ready_for_approval",None))
    for vid,p,base_id,kind,route,status,warning in variants:
        base_c=json.loads((GT_DIR/f"{base_id}.json").read_text())
        base_c["document_id"]=f"synthetic_{vid.lower().replace('-','_')}"; base_c["source"]["family"]="image"; base_c["source"]["mime_type"]={".jpg":"image/jpeg",".png":"image/png",".tiff":"image/tiff"}[p.suffix.lower()]; base_c["source"]["page_count"]=len(tiff_pages) if vid=="IMG-005" else 1
        (GT_DIR/f"{vid}.json").write_text(json.dumps(base_c,indent=2,ensure_ascii=False),encoding="utf-8")
        findings=[] if warning is None else [{"code":warning,"severity":"MEDIUM","field_paths":[],"resolution":"normalize_or_review"}]
        (FIND_DIR/f"{vid}.json").write_text(json.dumps(findings,indent=2),encoding="utf-8")
        manifest.append({"fixture_id":vid,"file":str(p.relative_to(CORPUS)),"kind":kind,"split":"functional","document_type":base_c["document_type"],"currency":base_c["invoice"]["currency"] or "UNKNOWN","country":base_c["locale"]["supplier_country"],"expected_route":route,"expected_status":status,"ground_truth":f"ground_truth/{vid}.json","expected_findings":f"expected_findings/{vid}.json","notes":warning or "clean image fixture"})

    # Structured UBL and hybrid
    ubl_spec=spec_by_id["INV-003"]
    ubl_path=STRUCT_DIR/"XML-001_synthetic_ubl_invoice.xml"; make_ubl(ubl_spec,ubl_path)
    ubl_c=canonical_from_spec(ubl_spec,source_family="ubl",route="structured_parser",mime="application/xml",page_count=1,profile="synthetic_ubl_subset")
    ubl_c["document_id"]="synthetic_xml_001"
    (GT_DIR/"XML-001.json").write_text(json.dumps(ubl_c,indent=2,ensure_ascii=False),encoding="utf-8")
    (FIND_DIR/"XML-001.json").write_text(json.dumps([{"code":"STRUCTURED_PROFILE_NOT_OFFICIALLY_CONFORMANT","severity":"INFO","field_paths":[],"resolution":"functional_fixture_only"}],indent=2),encoding="utf-8")
    manifest.append({"fixture_id":"XML-001","file":str(ubl_path.relative_to(CORPUS)),"kind":"ubl_xml","split":"functional","document_type":"invoice","currency":"EUR","country":"DE","expected_route":"structured_parser","expected_status":"ready_for_approval","ground_truth":"ground_truth/XML-001.json","expected_findings":"expected_findings/XML-001.json","notes":"Synthetic UBL-shaped functional fixture; not an official conformance sample"})
    unknown=STRUCT_DIR/"XML-002_unknown_profile.xml"; unknown.write_text('<?xml version="1.0"?><VendorInvoice version="7"><Number>X-771</Number><Total>42.00</Total></VendorInvoice>\n',encoding="utf-8")
    (FIND_DIR/"XML-002.json").write_text(json.dumps([{"code":"UNSUPPORTED_STRUCTURED_PROFILE","severity":"HIGH","field_paths":[],"resolution":"quarantine"}],indent=2),encoding="utf-8")
    manifest.append({"fixture_id":"XML-002","file":str(unknown.relative_to(CORPUS)),"kind":"unknown_xml","split":"negative","document_type":"unknown","currency":"UNKNOWN","country":"UNKNOWN","expected_route":"quarantine","expected_status":"quarantined","ground_truth":"","expected_findings":"expected_findings/XML-002.json","notes":"Unknown XML must not silently fall back to vision"})
    hybrid=PDF_DIR/"HYB-001_hybrid_pdf_with_embedded_ubl.pdf"; add_embedded_file(source_map["INV-003"],ubl_path,hybrid)
    hybrid_c=canonical_from_spec(ubl_spec,source_family="hybrid_pdf_xml",route="hybrid_compare",mime="application/pdf",page_count=1,profile="synthetic_ubl_subset",has_embedded=True); hybrid_c["document_id"]="synthetic_hyb_001"
    (GT_DIR/"HYB-001.json").write_text(json.dumps(hybrid_c,indent=2,ensure_ascii=False),encoding="utf-8")
    (FIND_DIR/"HYB-001.json").write_text(json.dumps([{"code":"HYBRID_VISUAL_STRUCTURED_MATCH","severity":"INFO","field_paths":[],"resolution":"none"}],indent=2),encoding="utf-8")
    manifest.append({"fixture_id":"HYB-001","file":str(hybrid.relative_to(CORPUS)),"kind":"hybrid_pdf_xml","split":"functional","document_type":"invoice","currency":"EUR","country":"DE","expected_route":"hybrid_compare","expected_status":"ready_for_approval","ground_truth":"ground_truth/HYB-001.json","expected_findings":"expected_findings/HYB-001.json","notes":"PDF with embedded synthetic UBL attachment"})

    # Unsafe / rejection fixtures
    protected=UNSAFE_DIR/"BAD-001_password_protected.pdf"
    src=fitz.open(source_map["INV-001"]); src.save(protected,encryption=fitz.PDF_ENCRYPT_AES_256,owner_pw="owner-test",user_pw="open-test",permissions=0); src.close()
    corrupted=UNSAFE_DIR/"BAD-002_truncated_corrupt.pdf"; b=source_map["INV-001"].read_bytes(); corrupted.write_bytes(b[:max(400,len(b)//3)])
    mismatch=UNSAFE_DIR/"BAD-003_extension_mismatch.pdf"; mismatch.write_text("This is plain text, not a PDF.\n",encoding="utf-8")
    bads=[
        ("BAD-001",protected,"PASSWORD_PROTECTED","Password-protected PDF must be rejected without password cracking"),
        ("BAD-002",corrupted,"CORRUPT_PDF","Truncated PDF must fail safely"),
        ("BAD-003",mismatch,"MIME_MAGIC_MISMATCH","Extension and magic bytes disagree"),
    ]
    for bid,path,code,note in bads:
        (FIND_DIR/f"{bid}.json").write_text(json.dumps([{"code":code,"severity":"HIGH","field_paths":[],"resolution":"quarantine"}],indent=2),encoding="utf-8")
        manifest.append({"fixture_id":bid,"file":str(path.relative_to(CORPUS)),"kind":"unsafe_input","split":"negative","document_type":"unknown","currency":"UNKNOWN","country":"UNKNOWN","expected_route":"quarantine","expected_status":"quarantined","ground_truth":"","expected_findings":f"expected_findings/{bid}.json","notes":note})

    # Model output and repair examples
    good=json.loads((GT_DIR/"INV-002.json").read_text()); (MODEL_DIR/"qwen3_vl_valid_candidate.json").write_text(json.dumps(good,indent=2,ensure_ascii=False),encoding="utf-8")
    bad=deepcopy(good); bad["totals"]["payable_amount"]="1500.00"; bad["evidence"]=[e for e in bad["evidence"] if e["field_path"]!="/totals/payable_amount"]
    (MODEL_DIR/"qwen3_vl_semantically_invalid_candidate.json").write_text(json.dumps(bad,indent=2,ensure_ascii=False),encoding="utf-8")
    layout={"page":1,"width":1275,"height":1650,"blocks":[{"type":"text","bbox":[0.68,0.10,0.94,0.18],"text":"Invoice/Ref: INV-2026-1042"},{"type":"table","bbox":[0.08,0.40,0.92,0.66],"rows":2,"columns":6},{"type":"text","bbox":[0.70,0.74,0.94,0.82],"text":"AMOUNT DUE GBP 1500.00"}]}
    (MODEL_DIR/"paddleocr_vl_layout_example.json").write_text(json.dumps(layout,indent=2),encoding="utf-8")
    repair_req={"document_id":good["document_id"],"schema_version":"2.0","failed_rules":["PAYABLE_AMOUNT_MISMATCH","MISSING_EVIDENCE"],"repairable_paths":["/totals/payable_amount"],"current_value":"1500.00","source_page":1,"instruction":"Return only the corrected field and evidence. Do not rewrite unrelated fields."}
    (MODEL_DIR/"targeted_repair_request.json").write_text(json.dumps(repair_req,indent=2),encoding="utf-8")
    repair_resp={"field_path":"/totals/payable_amount","value":"1500.00","evidence":{"page":1,"text":"AMOUNT DUE GBP 1,500.00","bbox":[0.70,0.74,0.94,0.82]},"decision":"unchanged_document_value"}
    (MODEL_DIR/"targeted_repair_response.json").write_text(json.dumps(repair_resp,indent=2),encoding="utf-8")

    # Batch export examples from first 8 valid docs
    approved=[]
    for mid in ["INV-001","INV-002","INV-003","INV-004","INV-005","INV-006","INV-007","INV-008"]:
        approved.append(json.loads((GT_DIR/f"{mid}.json").read_text()))
    (EXPORT_DIR/"approved_batch.jsonl").write_text("\n".join(json.dumps(x,ensure_ascii=False) for x in approved)+"\n",encoding="utf-8")
    with (EXPORT_DIR/"approved_invoices.csv").open("w",newline="",encoding="utf-8") as f:
        fields=["document_id","document_type","supplier_name","buyer_name","invoice_number","issue_date","currency","tax_exclusive_amount","total_tax_amount","withholding_total_amount","payable_amount","source_family","review_status"]
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader()
        for x in approved:
            w.writerow({"document_id":x["document_id"],"document_type":x["document_type"],"supplier_name":x["supplier"]["display_name"],"buyer_name":x["buyer"]["display_name"] if x["buyer"] else "","invoice_number":x["invoice"]["number"],"issue_date":x["invoice"]["issue_date"],"currency":x["invoice"]["currency"],"tax_exclusive_amount":x["totals"]["tax_exclusive_amount"],"total_tax_amount":x["totals"]["total_tax_amount"],"withholding_total_amount":x["totals"]["withholding_total_amount"],"payable_amount":x["totals"]["payable_amount"],"source_family":x["source"]["family"],"review_status":"APPROVED"})

    # Manifest and checksums
    with (CORPUS/"manifest.csv").open("w",newline="",encoding="utf-8") as f:
        fields=["fixture_id","file","kind","split","document_type","currency","country","expected_route","expected_status","ground_truth","expected_findings","notes","sha256"]
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader()
        for row in manifest:
            row["sha256"]=sha(CORPUS/row["file"])
            w.writerow(row)
    with (CORPUS/"checksums.sha256").open("w",encoding="utf-8") as f:
        for p in sorted((CORPUS/"documents").rglob("*")):
            if p.is_file(): f.write(f"{sha(p)}  {p.relative_to(CORPUS)}\n")
    print(f"Generated {len(manifest)} fixtures")

if __name__ == "__main__":
    main()
