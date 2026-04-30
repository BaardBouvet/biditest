{#
  ingest_contacts()
  ─────────────────────────────────────────────────────────────────────────────
  Implements Step 4 of the worked example: load seed rows into pg_ripple using
  ingest_json(..., mode => 'diff') so each field gets a per-triple
  prov:generatedAtTime annotation derived from the row's lastModified column.

  Call after the seeds have been loaded:
    dbt seed
    dbt run-operation ingest_contacts

  The macro is idempotent: re-delivering the same payload with the same
  lastModified is a no-op (diff mode returns 0 changed triples).
#}

{% macro ingest_contacts() %}

  {{ log("Ingesting CRM contacts …", info=True) }}

  {% set crm_rows = run_query(
      "SELECT id, email, name, last_modified FROM raw.crm_contacts"
  ) %}

  {% for row in crm_rows.rows %}
    {# Build the JSON payload that matches the crm_contact @context #}
    {% set payload = {
        "id":           row[0] | string,
        "email":        row[1] | string,
        "name":         row[2] | string,
        "lastModified": row[3] | string
    } %}

    {% set subject_iri = "https://crm.example.com/contacts/" ~ row[0] %}

    {% set sql %}
      SELECT pg_ripple.ingest_json(
          payload     => $json${{ tojson(payload) }}$json$::jsonb,
          subject_iri => '{{ subject_iri }}',
          mapping     => 'crm_contact',
          graph_iri   => '<urn:source:crm>',
          mode        => 'diff'
      );
    {% endset %}
    {% do run_query(sql) %}
    {{ log("  CRM contact ingested: " ~ subject_iri, info=True) }}
  {% endfor %}

  {{ log("Ingesting ERP contacts …", info=True) }}

  {% set erp_rows = run_query(
      "SELECT id, email, name, last_modified FROM raw.erp_contacts"
  ) %}

  {% for row in erp_rows.rows %}
    {% set payload = {
        "id":           row[0] | string,
        "email":        row[1] | string,
        "name":         row[2] | string,
        "lastModified": row[3] | string
    } %}

    {% set subject_iri = "https://erp.example.com/api/contact/" ~ row[0] %}

    {% set sql %}
      SELECT pg_ripple.ingest_json(
          payload     => $json${{ tojson(payload) }}$json$::jsonb,
          subject_iri => '{{ subject_iri }}',
          mapping     => 'erp_contact',
          graph_iri   => '<urn:source:erp>',
          mode        => 'diff'
      );
    {% endset %}
    {% do run_query(sql) %}
    {{ log("  ERP contact ingested: " ~ subject_iri, info=True) }}
  {% endfor %}

  {{ log("", info=True) }}
  {{ log("All contacts ingested.", info=True) }}

  {# ── Step 2: Run Datalog inference (BIDI-REF-01) ─────────────────────────── #}
  {#
    pg_ripple Datalog rules are not evaluated automatically — infer() must be
    called explicitly after data is loaded. It materialises the owl:sameAs
    facts derived by the same_email rule into the VP tables, which the
    merged_contacts model then queries via SPARQL.

    rule_graph_scope = 'all' (set as a database default in
    init/01_init_ripple.sql) allows the rule engine to see triples across all
    named graphs, which is required for the cross-graph email match to work.
  #}

  {% set sql_infer %}
    SELECT pg_ripple.infer('same_email');
  {% endset %}
  {% do run_query(sql_infer) %}
  {{ log("✓ Datalog inference complete — owl:sameAs facts materialised (BIDI-REF-01)", info=True) }}

{% endmacro %}
