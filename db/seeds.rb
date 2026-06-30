# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

tenant = Tenant.find_or_create_by!(slug: "default-tenant") do |t|
  t.name = "Default Tenant"
  t.allowed_processing_regions = [ "eu-west-2" ]
  t.allowed_providers = [ "fixture" ]
  t.monthly_spend_limit_cents = 100_00 # $100.00
end

user = User.find_or_initialize_by(email: "operator@example.com") do |u|
  u.tenant = tenant
  u.name = "Operator"
  u.role = "operator"
end

if user.new_record?
  user.operator_token = "operator-token"
  user.save!
  puts "Created default user operator@example.com with token operator-token"
else
  puts "Default user operator@example.com already exists"
end

# Each sample fixture is paired with a real, renderable invoice from the synthetic
# corpus so the side-by-side review screen shows an actual document in the source pane.
corpus = Rails.root.join("docs/invoice-parser-post-m2-5-final/samples/synthetic_corpus/documents")
sample_fixtures = [
  { filename: "fix_001_minimal_visual_usd.json", name: "Minimal USD Invoice",     source: "images/IMG-004_receipt.png",                             mime: "image/png" },
  { filename: "fix_002_credit_note_gbp.json",    name: "Credit Note GBP",         source: "pdf/inv-009_eur_credit_note.pdf",                        mime: "application/pdf" },
  { filename: "fix_005_generic_vat_eur.json",    name: "Generic VAT EUR Invoice", source: "pdf/inv-003_eu_cross-border_reverse-charge_invoice.pdf",  mime: "application/pdf" }
]

# The ingester derives source_sha256 from the canonical hash, so it is deterministic
# and lets us re-find a seeded document on later runs to back-fill its source file.
seed_source_sha = ->(filename) do
  Digest::SHA256.hexdigest(JSON.parse(Rails.root.join("test/fixtures/files/canonical", filename).read).to_json)
end

# Seed the sample batch + documents once.
if tenant.review_batches.empty?
  puts "Seeding sample review batches and documents..."
  batch = tenant.review_batches.create!(name: "Sample Invoice Intake Batch")

  sample_fixtures.each do |fixture_info|
    path = Rails.root.join("test/fixtures/files/canonical", fixture_info[:filename])
    invoice_hash = JSON.parse(path.read)

    invoice = Canonical::Invoice.from_hash(invoice_hash)

    attempt = Struct.new(:schema_version, :route, :region, :provider, :provider_version, :model, :model_version, :prompt_sha256, :latency_ms, :repair_attempt, keyword_init: true).new(
      schema_version: "2.0",
      route: "visual_model",
      region: "global_generic_v1",
      provider: "fixture",
      provider_version: "1.0",
      model: "fixture-model",
      model_version: "1.0",
      prompt_sha256: Digest::SHA256.hexdigest(fixture_info[:filename]),
      latency_ms: 350,
      repair_attempt: 0
    )

    result = Struct.new(:candidate, :attempts, :idempotency_key, keyword_init: true) do
      def success? = true
    end.new(
      candidate: invoice,
      attempts: [ attempt ],
      idempotency_key: "seed-#{fixture_info[:filename]}"
    )

    Review::ProviderResultIngester.call(
      batch: batch,
      source_sha256: Digest::SHA256.hexdigest(invoice_hash.to_json),
      result: result,
      source_metadata: {
        "filename" => fixture_info[:filename],
        "mime_type" => fixture_info[:mime],
        "page_count" => 1
      }
    )
    puts "Ingested #{fixture_info[:name]} into batch."
  end

  puts "Seeding complete!"
end

# Attach a real source document to each seeded document (idempotent — safe to re-run),
# so the review screen renders an actual PDF rather than a broken preview.
sample_fixtures.each do |fixture_info|
  document = Review::Document.find_by(source_sha256: seed_source_sha.call(fixture_info[:filename]))
  next if document.nil?

  source_path = corpus.join(fixture_info[:source])
  unless source_path.exist?
    puts "Skipped source for #{fixture_info[:name]} (missing #{fixture_info[:source]})."
    next
  end

  desired = File.basename(source_path)
  next if document.source_file.attached? && document.source_file.filename.to_s == desired

  document.source_file.purge if document.source_file.attached?
  document.source_file.attach(io: File.open(source_path), filename: desired, content_type: fixture_info[:mime])
  puts "Attached source #{desired} → #{fixture_info[:name]}."
end
