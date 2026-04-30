{#
  Test scenario macros for interactive exploration of pg-ripple features.
  These are not part of the core workflow — call them manually to explore
  conflict resolution, linkback recording, etc.
#}

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
