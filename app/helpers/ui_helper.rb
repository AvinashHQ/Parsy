# frozen_string_literal: true

# UiHelper centralizes the small design-system primitives used across the app:
# an inline-SVG icon set (Lucide-style, stroke-based) plus semantic mappings for
# document/finding state. Keeping these here means views stay declarative and the
# visual language stays consistent.
module UiHelper
  # Curated Lucide-style icon paths (24x24, stroke="currentColor"). Add sparingly.
  ICONS = {
    "check" => %(<path d="M20 6 9 17l-5-5"/>),
    "x" => %(<path d="M18 6 6 18"/><path d="m6 6 12 12"/>),
    "chevron-down" => %(<path d="m6 9 6 6 6-6"/>),
    "chevron-right" => %(<path d="m9 18 6-6-6-6"/>),
    "chevron-left" => %(<path d="m15 18-6-6 6-6"/>),
    "arrow-right" => %(<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>),
    "arrow-left" => %(<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>),
    "sun" => %(<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>),
    "moon" => %(<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>),
    "log-out" => %(<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/>),
    "triangle-alert" => %(<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/>),
    "info" => %(<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>),
    "circle-check" => %(<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>),
    "circle-x" => %(<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>),
    "circle-alert" => %(<circle cx="12" cy="12" r="10"/><line x1="12" x2="12" y1="8" y2="12"/><line x1="12" x2="12.01" y1="16" y2="16"/>),
    "shield" => %(<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>),
    "file-text" => %(<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/>),
    "layers" => %(<path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m6.08 9.5-3.49 1.59a1 1 0 0 0 0 1.83l8.59 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83L17.92 9.5"/><path d="m6.08 14.5-3.49 1.59a1 1 0 0 0 0 1.83l8.59 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83l-3.49-1.6"/>),
    "download" => %(<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/>),
    "search" => %(<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>),
    "clock" => %(<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>),
    "external-link" => %(<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>),
    "building" => %(<rect width="16" height="20" x="4" y="2" rx="2"/><path d="M9 22v-4h6v4"/><path d="M8 6h.01"/><path d="M16 6h.01"/><path d="M12 6h.01"/><path d="M12 10h.01"/><path d="M12 14h.01"/><path d="M16 10h.01"/><path d="M16 14h.01"/><path d="M8 10h.01"/><path d="M8 14h.01"/>),
    "user" => %(<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>),
    "save" => %(<path d="M15.2 3a2 2 0 0 1 1.4.6l3.8 3.8a2 2 0 0 1 .6 1.4V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M17 21v-7a1 1 0 0 0-1-1H8a1 1 0 0 0-1 1v7"/><path d="M7 3v4a1 1 0 0 0 1 1h7"/>),
    "eye" => %(<path d="M2.06 12.35a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 19.88 0 1 1 0 0 1 0 .7 10.75 10.75 0 0 1-19.88 0"/><circle cx="12" cy="12" r="3"/>),
    "copy" => %(<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>),
    "refresh" => %(<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>),
    "filter" => %(<polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/>),
    "trash" => %(<path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/>),
    "pencil" => %(<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/><path d="m15 5 4 4"/>),
    "list" => %(<path d="M3 12h.01"/><path d="M3 18h.01"/><path d="M3 6h.01"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M8 6h13"/>),
    "map-pin" => %(<path d="M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/>),
    "git-branch" => %(<line x1="6" x2="6" y1="3" y2="15"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M18 9a9 9 0 0 1-9 9"/>),
    "circle-dot" => %(<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="1"/>),
    "loader" => %(<path d="M12 2v4"/><path d="m16.2 7.8 2.9-2.9"/><path d="M18 12h4"/><path d="m16.2 16.2 2.9 2.9"/><path d="M12 18v4"/><path d="m4.9 19.1 2.9-2.9"/><path d="M2 12h4"/><path d="m4.9 4.9 2.9 2.9"/>),
    "scale" => %(<path d="m16 16 3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1Z"/><path d="m2 16 3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1Z"/><path d="M7 21h10"/><path d="M12 3v18"/><path d="M3 7h2c2 0 5-1 7-2 2 1 5 2 7 2h2"/>)
  }.freeze

  # Renders an inline SVG icon. Pass `class:` for sizing/color (defaults to size-4).
  def icon(name, **opts)
    inner = ICONS[name.to_s]
    unless inner
      Rails.logger.warn("[ui] missing icon: #{name}")
      inner = %(<circle cx="12" cy="12" r="9"/>)
    end
    opts[:class] = opts[:class] || "size-4"
    tag.svg(inner.html_safe,
            xmlns: "http://www.w3.org/2000/svg",
            viewBox: "0 0 24 24",
            fill: "none",
            stroke: "currentColor",
            "stroke-width": opts.delete(:stroke) || 2,
            "stroke-linecap": "round",
            "stroke-linejoin": "round",
            "aria-hidden": "true",
            focusable: "false",
            **opts)
  end

  # --- Semantic colour maps (literal class strings so Tailwind's scanner keeps them) ---
  TONE_BADGE = {
    "danger" => "bg-danger-subtle text-danger-fg border-danger-line",
    "caution" => "bg-caution-subtle text-caution-fg border-caution-line",
    "warning" => "bg-warning-subtle text-warning-fg border-warning-line",
    "info" => "bg-info-subtle text-info-fg border-info-line",
    "success" => "bg-success-subtle text-success-fg border-success-line",
    "plain" => "bg-plain-subtle text-plain-fg border-plain-line"
  }.freeze

  TONE_DOT = {
    "danger" => "bg-danger", "caution" => "bg-caution", "warning" => "bg-warning",
    "info" => "bg-info", "success" => "bg-success", "plain" => "bg-plain"
  }.freeze

  TONE_TEXT = {
    "danger" => "text-danger-fg", "caution" => "text-caution-fg", "warning" => "text-warning-fg",
    "info" => "text-info-fg", "success" => "text-success-fg", "plain" => "text-plain-fg"
  }.freeze

  SEVERITY_TONE = {
    "critical" => "danger", "high" => "caution", "medium" => "warning",
    "low" => "info", "info" => "plain"
  }.freeze

  STATUS_TONE = {
    "approved" => "success", "exported" => "success", "completed" => "success",
    "ready_for_approval" => "info", "uploaded" => "info", "inspecting" => "info",
    "extracting" => "info", "validating" => "info", "routed_structured" => "info",
    "routed_visual" => "info", "processing" => "info",
    "needs_review" => "warning", "review" => "warning",
    "rejected" => "danger", "failed" => "danger",
    "quarantined" => "plain", "purged" => "plain"
  }.freeze

  STATUS_ICON = {
    "approved" => "circle-check", "exported" => "download", "completed" => "circle-check",
    "ready_for_approval" => "clock", "needs_review" => "triangle-alert",
    "rejected" => "circle-x", "failed" => "circle-x",
    "quarantined" => "shield", "purged" => "shield"
  }.freeze

  # Pill for a validation-finding severity (critical/high/medium/low/info).
  def severity_badge(severity)
    tone = SEVERITY_TONE[severity.to_s.downcase] || "plain"
    tag.span(class: "badge #{TONE_BADGE[tone]}") do
      safe_join([tag.span("", class: "badge-dot #{TONE_DOT[tone]}"), severity.to_s.humanize])
    end
  end

  # Pill for a document/batch status, with a matching icon.
  def status_badge(status)
    key = status.to_s.downcase
    tone = STATUS_TONE[key] || "plain"
    tag.span(class: "badge #{TONE_BADGE[tone]}") do
      safe_join([icon(STATUS_ICON[key] || "circle-dot", class: "size-3.5"), status.to_s.humanize])
    end
  end

  # Monospace risk-score chip, banded high/mid/low.
  def risk_chip(score)
    s = score.to_i
    tone = s >= 70 ? "danger" : (s >= 30 ? "warning" : "success")
    tag.span(s,
             class: "inline-flex min-w-[2.25rem] items-center justify-center rounded-md border px-1.5 py-0.5 font-mono text-xs #{TONE_BADGE[tone]}",
             title: "Risk score #{s}")
  end

  # Page header with optional breadcrumbs/subtitle and an actions block (right-aligned).
  def page_header(title, subtitle: nil, breadcrumbs: [], &block)
    crumbs = if breadcrumbs.present?
      items = breadcrumbs.each_with_index.map do |(label, path), i|
        sep = i.zero? ? "".html_safe : icon("chevron-right", class: "size-3.5 text-faint")
        link = path ? link_to(label, path, class: "text-muted no-underline hover:text-ink hover:no-underline") : tag.span(label, class: "text-ink")
        safe_join([sep, link])
      end
      tag.nav(safe_join(items), class: "mb-2 flex items-center gap-1.5 text-xs", "aria-label": "Breadcrumb")
    end
    actions = block ? capture(&block) : nil
    tag.div(class: "mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between") do
      safe_join([
        tag.div(safe_join([
          crumbs,
          tag.h1(title, class: "text-xl font-medium tracking-tight text-ink"),
          (subtitle ? tag.p(subtitle, class: "mt-1 text-sm text-muted") : nil)
        ].compact)),
        (actions ? tag.div(actions, class: "flex shrink-0 flex-wrap items-center gap-2") : nil)
      ].compact)
    end
  end

  # Compact stat card for summary metrics.
  def metric_card(label, value, tone: nil)
    tag.div(class: "rounded-xl bg-subtle px-4 py-3") do
      safe_join([
        tag.p(label, class: "text-xs font-medium text-muted"),
        tag.p(value, class: "mt-1 text-2xl font-medium #{tone ? TONE_TEXT[tone] : 'text-ink'}")
      ])
    end
  end

  # Accent-filled progress bar (0-100).
  def progress_bar(percent)
    pct = [[percent.to_i, 0].max, 100].min
    tag.div(class: "h-2 w-full overflow-hidden rounded-full bg-subtle",
            role: "progressbar", "aria-valuenow": pct, "aria-valuemin": 0, "aria-valuemax": 100) do
      tag.div("", class: "h-full rounded-full bg-accent transition-[width] duration-500", style: "width: #{pct}%")
    end
  end

  # Centered empty state inside a card.
  def empty_state(icon_name, title, message = nil)
    tag.div(class: "card flex flex-col items-center justify-center gap-3 px-6 py-14 text-center") do
      safe_join([
        tag.div(icon(icon_name, class: "size-6 text-muted"), class: "grid size-12 place-items-center rounded-full bg-subtle"),
        tag.div(safe_join([
          tag.p(title, class: "text-sm font-medium text-ink"),
          (message ? tag.p(message, class: "mt-1 text-sm text-muted") : nil)
        ].compact))
      ])
    end
  end
end
