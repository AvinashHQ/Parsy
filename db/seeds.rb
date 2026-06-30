# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

tenant = Tenant.find_or_create_by!(slug: "default-tenant") do |t|
  t.name = "Default Tenant"
  t.allowed_processing_regions = ["eu-west-2"]
  t.allowed_providers = ["fixture"]
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

# Seed some sample batches and documents if they don't exist
if tenant.review_batches.empty?
  puts "Seeding sample review batches and documents..."
  
  # Batch 1: Sample Invoices
  batch = tenant.review_batches.create!(name: "Sample Invoice Intake Batch")
  
  fixtures = [
    { filename: "fix_001_minimal_visual_usd.json", name: "Minimal USD Invoice" },
    { filename: "fix_002_credit_note_gbp.json", name: "Credit Note GBP" },
    { filename: "fix_005_generic_vat_eur.json", name: "Generic VAT EUR Invoice" }
  ]
  
  fixtures.each do |fixture_info|
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
      attempts: [attempt],
      idempotency_key: "seed-#{fixture_info[:filename]}"
    )
    
    document = Review::ProviderResultIngester.call(
      batch: batch,
      source_sha256: Digest::SHA256.hexdigest(invoice_hash.to_json),
      result: result,
      source_metadata: {
        "filename" => fixture_info[:filename],
        "mime_type" => "application/pdf",
        "page_count" => 1,
        "safe_preview_path" => "https://example.com/preview/#{fixture_info[:filename]}"
      }
    )
    puts "Ingested #{fixture_info[:name]} into batch."
  end
  
  puts "Seeding complete!"
end


