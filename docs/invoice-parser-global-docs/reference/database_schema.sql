-- Conceptual PostgreSQL reference. Active Record migrations are authoritative.
create extension if not exists pgcrypto;

create table tenants (
  id uuid primary key default gen_random_uuid(),
  name varchar(200) not null,
  hosting_region varchar(64) not null,
  allowed_processor_regions jsonb not null default '[]'::jsonb,
  enabled_region_profiles jsonb not null default '["global_generic_v1"]'::jsonb,
  retention_policy jsonb not null,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create table batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id),
  status varchar(32) not null,
  locale_hints jsonb not null default '{}'::jsonb,
  raw_delete_after timestamptz not null,
  export_delete_after timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create table documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id),
  batch_id uuid not null references batches(id),
  source_sha256 char(64) not null,
  status varchar(32) not null,
  source_format_family varchar(64),
  source_format_profile varchar(128),
  source_format_version varchar(64),
  route varchar(32),
  page_count integer,
  document_language varchar(64),
  supplier_country char(2),
  buyer_country char(2),
  currency_code char(3),
  supplier_identifier_key varchar(256),
  supplier_name_key varchar(512),
  buyer_identifier_key varchar(256),
  document_number_key varchar(256),
  issue_date date,
  payable_amount numeric(24,8),
  approved_revision_id uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique(tenant_id, source_sha256)
);

create table document_revisions (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references documents(id),
  revision_no integer not null,
  origin varchar(32) not null,
  canonical_schema_version varchar(32) not null,
  canonical_json jsonb not null,
  capability_profile varchar(128) not null,
  region_pack_id varchar(128) not null,
  region_pack_version varchar(64) not null,
  approved boolean not null default false,
  created_by varchar(128),
  created_at timestamptz not null,
  unique(document_id, revision_no)
);

alter table documents add constraint documents_approved_revision_fk
  foreign key (approved_revision_id) references document_revisions(id);

create table processing_attempts (
  id bigserial primary key,
  document_id uuid not null references documents(id),
  route varchar(32) not null,
  provider_or_parser varchar(128) not null,
  version varchar(128) not null,
  prompt_hash char(64),
  format_registry_version varchar(64) not null,
  region_pack_id varchar(128),
  region_pack_version varchar(64),
  processing_region varchar(64),
  status varchar(32) not null,
  latency_ms bigint,
  input_tokens bigint,
  output_tokens bigint,
  cost_usd numeric(14,8),
  error_code varchar(128),
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create table validation_findings (
  id bigserial primary key,
  document_revision_id uuid not null references document_revisions(id),
  code varchar(128) not null,
  severity varchar(16) not null,
  field_paths jsonb not null default '[]'::jsonb,
  pack_id varchar(128) not null,
  pack_version varchar(64) not null,
  resolution varchar(32) not null default 'open',
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create table review_events (
  id bigserial primary key,
  document_id uuid not null references documents(id),
  from_revision_id uuid references document_revisions(id),
  to_revision_id uuid references document_revisions(id),
  actor_id varchar(128) not null,
  action varchar(32) not null,
  changed_fields jsonb not null default '[]'::jsonb,
  reason_code varchar(128),
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create table export_artifacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id),
  batch_id uuid not null references batches(id),
  export_type varchar(64) not null,
  mapping_version varchar(64) not null,
  revision_ids jsonb not null,
  status varchar(32) not null,
  checksum_sha256 char(64),
  delete_after timestamptz not null,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create table capability_profiles (
  id varchar(128) primary key,
  status varchar(32) not null,
  schema_version varchar(32) not null,
  profile_json jsonb not null,
  benchmark_report_hash char(64),
  activated_at timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create index documents_batch_status_idx on documents(batch_id, status);
create index documents_duplicate_lookup_idx on documents(
  tenant_id, supplier_identifier_key, document_number_key, issue_date, currency_code, payable_amount
);
create index revisions_document_idx on document_revisions(document_id, revision_no desc);
create index findings_open_idx on validation_findings(severity, resolution);

-- Active Storage and Solid Queue tables are installed and maintained by Rails.
