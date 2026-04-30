{#
  ingest_contacts()
  ─────────────────────────────────────────────────────────────────────────────
  Implements Step 4 of the worked example: load seed rows into pg_ripple using
  ingest_json(..., mode => 'diff') so each field gets a per-triple
  prov:generatedAtTime annotation derived from the row's lastModified column.

  Call after setup_bidi_example and after the seeds have been loaded:
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
  {{ log("All contacts ingested. Run 'dbt run' to materialise the dbt models.", info=True) }}

  {# ── Step 2 (runtime): assert sameAs for contacts sharing ex:email ───── #}
  {#
    pg-ripple 0.78.0 Datalog bug: the infer() engine computes the result (returns 1),
    but the generated SQL has a self-join bug (ON t1.s = t1.s), so derived facts
    don't get written to SPARQL-queryable VP tables. Workaround: use sparql_update()
    which DOES write to VP tables and IS visible to SPARQL queries.
  #}

  {% set sql_sameas %}
    SELECT pg_ripple.sparql_update($sparql$
      PREFIX ex:  <http://example.org/>
      PREFIX owl: <http://www.w3.org/2002/07/owl#>
      INSERT { ?a owl:sameAs ?b . }
      WHERE  {
          ?a ex:email ?e .
          ?b ex:email ?e .
          FILTER (str(?a) < str(?b))
      }
    $sparql$);
  {% endset %}
  {% do run_query(sql_sameas) %}
  {{ log("✓ owl:sameAs inserted for shared-email contacts via SPARQL UPDATE (BIDI-REF-01 workaround)", info=True) }}

  {# ── Recompute conflict winners for ex:name across merged entities ────── #}
  {#
    After sameAs triples are in place, recompute_conflict_winners re-evaluates
    the latest_wins policy.  This ensures the resolved projection reflects the
    correct winner when the merged_contacts model is materialised.
  #}

  {% set sql_recompute %}
    SELECT pg_ripple.recompute_conflict_winners('http://example.org/name');
  {% endset %}
  {% do run_query(sql_recompute) %}
  {{ log("✓ ex:name conflict winners recomputed (latest_wins across merged entities)", info=True) }}

{% endmacro %}


{#
  simulate_erp_name_update()
  ─────────────────────────────────────────────────────────────────────────────
  Simulates Step 8: a user edits ada@example.com in ERP at a later timestamp.
  Because the new lastModified is later than the CRM value, latest_wins promotes
  the ERP name in the resolved projection and the crm_relay outbox receives an
  UPDATE event with base: {"ex:name": "Ada Lovelace"}.

  Call interactively to see the conflict policy in action:
    dbt run-operation simulate_erp_name_update
#}

{% macro simulate_erp_name_update() %}

  {% set payload = {
      "id":           "7",
      "email":        "ada@example.com",
      "name":         "Ada Lovelace (updated)",
      "lastModified": "2026-04-30T08:00:00Z"
  } %}

  {% set sql %}
    SELECT pg_ripple.ingest_json(
        payload     => {{ tojson(payload) }}::jsonb,
        subject_iri => 'https://erp.example.com/api/contact/7',
        mapping     => 'erp_contact',
        graph_iri   => '<urn:source:erp>',
        mode        => 'diff'
    );
  {% endset %}
  {% do run_query(sql) %}

  {{ log("ERP name updated → latest_wins will promote the new value.", info=True) }}
  {{ log("Refresh the merged_contacts model with: dbt run --select merged_contacts", info=True) }}

{% endmacro %}


{#
  simulate_linkback(event_id, target_id)
  ─────────────────────────────────────────────────────────────────────────────
  Simulates Step 7: after the ERP relay POSTs a new contact and gets back the
  target-assigned ID from ERP, it calls record_linkback to close the loop.

  Usage (substitute the real event_id UUID from the erp_relay outbox table):
    dbt run-operation simulate_linkback \
        --args '{"event_id": "a3f1…", "target_id": "4011"}'
#}

{% macro simulate_linkback(event_id, target_id) %}

  {% set sql %}
    SELECT pg_ripple.record_linkback(
        event_id  => '{{ event_id }}'::uuid,
        target_id => '{{ target_id }}'
    );
  {% endset %}
  {% do run_query(sql) %}

  {{ log("Linkback recorded: hub entity linked to ERP ID " ~ target_id, info=True) }}

{% endmacro %}
