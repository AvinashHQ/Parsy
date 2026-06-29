# Rails Codebase Map

```text
app/
  controllers/
    batches_controller.rb
    documents_controller.rb
    reviews_controller.rb
    exports_controller.rb
    admin/capability_profiles_controller.rb
    api/v1/
  models/
    tenant.rb
    user.rb
    batch.rb
    document.rb
    document_revision.rb
    processing_attempt.rb
    validation_finding.rb
    review_event.rb
    export_artifact.rb
    capability_profile.rb
  jobs/
    inspect_document_job.rb
    extract_visual_document_job.rb
    parse_structured_document_job.rb
    repair_extraction_job.rb
    validate_revision_job.rb
    generate_batch_export_job.rb
    purge_expired_data_job.rb
    reconcile_orphaned_blobs_job.rb
  domain/
    canonical/
      decimal_value.rb
      schema_validator.rb
      normalizer.rb
    intake/
      file_inspector.rb
      format_detector.rb
    extraction/
      provider.rb
      pipeline.rb
      providers/
    structured/
      router.rb
      ubl_adapter.rb
      cii_adapter.rb
    validation/
      universal_engine.rb
      finding.rb
      rules/
    region_packs/
      base.rb
      registry.rb
      global_generic/
      india_gst/
    acceptance/
      policy.rb
    exports/
      canonical_json.rb
      normalized_csv.rb
      workbook.rb
    retention/
      purge_batch.rb
      reconcile_objects.rb
  views/
    batches/
    documents/
    reviews/
    exports/
  javascript/controllers/
    review_shortcuts_controller.js
    evidence_focus_controller.js
    split_pane_controller.js
config/
  format_registry.yml
  region_profiles.yml
  currency_registry.yml
  validation_rules.yml
contracts/
  invoice.schema.json
  region_profile.schema.json
prompts/
  extraction_system.txt
  extraction_user_template.txt
  repair_system.txt
```

## Placement rules

| Change | Location |
|---|---|
| Canonical field/schema | `contracts/`, `domain/canonical/`, migration/version ADR |
| Universal accounting invariant | `domain/validation/rules/` |
| Country/tax semantics | `domain/region_packs/<pack>/` |
| Source XML/PDF syntax | `domain/structured/` or `domain/intake/` |
| New model provider | `domain/extraction/providers/` |
| New export format | `domain/exports/` or isolated adapter namespace |
| Async orchestration | `app/jobs/`, delegating to domain service |
| UI behavior | ERB/Turbo first, Stimulus for browser-only interaction |
| Persisted metadata | migration, model, index, retention/privacy review |
| External API | `controllers/api/v1/` plus OpenAPI update |

## Forbidden coupling

- Region packs must not know Rails controllers/views.
- Providers must not return ERP-specific objects.
- Structured adapters must not apply jurisdiction rules.
- Models/callbacks must not call external services.
- Controllers must not perform parsing or accounting arithmetic.
- Export adapters must read immutable approved revisions, not raw provider responses.
- Core schema must not gain a country field when an identifier/tax/reference extension can represent it.
