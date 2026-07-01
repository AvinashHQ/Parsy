# frozen_string_literal: true

require "json"

module Extraction
  # Provider-neutral prompt/text composition shared by every vision extraction
  # client (LocalExtraction::OllamaClient and RemoteVision::GeminiClient). ADR-026
  # requires the extraction prompt to embed the Canonical Invoice v2 field
  # contract + worked example regardless of provider, so the wrapping around that
  # shared prompt — the JSON-only reminder, the document-context block, and the
  # machine-readable text — lives here once instead of being copied per client.
  #
  # Mixed in with `include`; the methods are private so they don't widen a
  # client's public surface. The provider-specific parts (how images are
  # attached, how the HTTP call is made, how the response is unwrapped) stay in
  # each client.
  module VisionDocumentContext
    MAX_TEXT_BYTES = 24_000

    private

    # Wraps the shared prompt (which already carries the field contract + worked
    # example) with the JSON-only reminder, document context, and extracted text.
    def compose_prompt(request)
      base = request["prompt"].to_s
      document = request["document"] || {}
      text = extracted_text(request)

      <<~PROMPT
        #{base}

        Output the single JSON object described above — no prose, no markdown fences. Use null (or []
        for arrays) for anything the document does not provide; do not invent values.
        #{image_instructions(request)}
        Document context — family/route/profile/page_count feed the "source" object, which must
        contain only its seven contract keys (never add sha256 or byte_size from this block):
        #{JSON.pretty_generate(document)}

        Extracted document text:
        #{text.empty? ? '(no machine-readable text was available)' : text}
      PROMPT
    end

    def image_instructions(request)
      return "" if Array(request["images_bytes"]).empty?

      "\nA page image is attached. Read it directly for any field the extracted text below is missing or got wrong.\n"
    end

    # Pulls text out of both the digital-parser output and the OCR output —
    # whichever is present — so a scanned/photographed page that only has OCR
    # text still reaches the model. Bounded so an enormous text layer can't blow
    # up the request.
    def extracted_text(request, max_bytes: MAX_TEXT_BYTES)
      texts = page_texts(request["parser_output"]) + page_texts(request["ocr_output"])
      texts.compact.map(&:to_s).reject(&:empty?).uniq.join("\n").byteslice(0, max_bytes).to_s
    end

    def page_texts(output)
      return [] unless output.is_a?(Hash)

      texts = [ output["text"] ]
      Array(output["pages"]).each do |page|
        next unless page.is_a?(Hash)

        texts << page["text"]
        Array(page["layout"]).each { |block| texts << block["text"] if block.is_a?(Hash) }
      end
      texts
    end
  end
end
