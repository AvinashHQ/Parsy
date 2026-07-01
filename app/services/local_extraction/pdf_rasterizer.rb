# frozen_string_literal: true

require "open3"
require "base64"

module LocalExtraction
  # Renders page 1 of a PDF to PNG bytes for documents that have no
  # extractable text layer (scanned/photographed invoices saved as PDF), so
  # they can be handed to an OCR/vision model instead of producing no usable
  # content at all.
  #
  # Mirrors the existing script/run_llm_benchmark.rb pattern of shelling out
  # to a fixed python3 -c script with no interpolated input: the PDF bytes
  # travel over stdin and the PNG bytes travel back over stdout as base64, so
  # no untrusted data ever reaches the command line or the script body.
  class PdfRasterizer
    RENDER_SCRIPT = <<~PYTHON.freeze
      import sys, base64
      import fitz

      data = sys.stdin.buffer.read()
      doc = fitz.open(stream=data, filetype="pdf")
      if doc.page_count == 0:
          sys.exit(1)
      page = doc[0]
      pix = page.get_pixmap(matrix=fitz.Matrix(2.0, 2.0))
      sys.stdout.write(base64.b64encode(pix.tobytes("png")).decode())
    PYTHON

    def call(bytes:)
      stdout, _stderr, status = Open3.capture3("python3", "-c", RENDER_SCRIPT, stdin_data: bytes.to_s.b)
      return nil unless status.success?

      decoded = Base64.decode64(stdout)
      decoded.empty? ? nil : decoded
    rescue StandardError
      nil
    end
  end
end
