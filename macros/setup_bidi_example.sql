{#
  setup_bidi_example()
  ─────────────────────────────────────────────────────────────────────────────
  Implements Steps 1–5 of the worked example from:
  https://github.com/grove/pg-ripple/blob/main/roadmap/v0.77.0-full.md
  (the worked example ships unchanged in v0.78.0)

  Call once before running the ingestion macros:
    dbt run-operation setup_bidi_example

  The macro is idempotent — re-running it on a database that already has the
  mappings/rules/policies in place is safe (pg_ripple uses CREATE OR REPLACE
  / IF NOT EXISTS semantics internally).
#}

{% macro setup_bidi_example() %}

  {# ── Step 1: Register the two source-graph JSON mappings ──────────────── #}

  {% set sql_crm_mapping %}
    SELECT pg_ripple.register_json_mapping(
        name              => 'crm_contact',
        default_graph_iri => '<urn:source:crm>',
        iri_template      => 'https://crm.example.com/contacts/{id}',
        iri_match_pattern => '^https://crm.example.com/contacts/',
        timestamp_path    => '$.lastModified',
        context           => '{
          "@vocab":       "http://example.org/",
          "email":        {"@id": "http://example.org/email"},
          "name":         {"@id": "http://example.org/name"},
          "lastModified": {"@id": "http://example.org/lastModified"}
        }'::jsonb
    );
  {% endset %}
  {% do run_query(sql_crm_mapping) %}
  {{ log("✓ crm_contact mapping registered", info=True) }}

  {% set sql_erp_mapping %}
    SELECT pg_ripple.register_json_mapping(
        name              => 'erp_contact',
        default_graph_iri => '<urn:source:erp>',
        iri_template      => 'https://erp.example.com/api/contact/{id}',
        iri_match_pattern => '^https://erp.example.com/api/contact/',
        timestamp_path    => '$.lastModified',
        context           => '{
          "@vocab":       "http://example.org/",
          "email":        {"@id": "http://example.org/email"},
          "name":         {"@id": "http://example.org/name"},
          "lastModified": {"@id": "http://example.org/lastModified"}
        }'::jsonb
    );
  {% endset %}
  {% do run_query(sql_erp_mapping) %}
  {{ log("✓ erp_contact mapping registered", info=True) }}

  {# ── Step 2: Composite-identity rule — merge on shared email ─────────── #}

  {% set sql_drop_rules %}
    SELECT pg_ripple.drop_rules('same_email');
  {% endset %}
  {% do run_query(sql_drop_rules) %}

  {% set sql_load_rules %}
    SELECT pg_ripple.load_rules(
        rules    => '?x <http://www.w3.org/2002/07/owl#sameAs> ?y :-
                       ?x <http://example.org/email> ?e,
                       ?y <http://example.org/email> ?e,
                       ?x != ?y .',
        rule_set => 'same_email'
    );
  {% endset %}
  {% do run_query(sql_load_rules) %}
  {{ log("✓ same_email Datalog rule loaded (BIDI-REF-01)", info=True) }}

  {# ── Step 3: latest_wins conflict policy on ex:name ───────────────────── #}

  {% set sql_conflict %}
    SELECT pg_ripple.register_conflict_policy(
        predicate => 'http://example.org/name',
        strategy  => 'latest_wins',
        config    => '{
          "timestamp_predicate":
            "http://www.w3.org/ns/prov#generatedAtTime"
        }'::jsonb
    );
  {% endset %}
  {% do run_query(sql_conflict) %}
  {{ log("✓ latest_wins conflict policy registered for ex:name", info=True) }}

  {# ── Step 5: Subscriptions for both relays ────────────────────────────── #}
  {#
    With only target_graph set, pg_ripple automatically defaults:
      rewrite_target_graph  => target_graph
      exclude_graphs        => ARRAY[target_graph]
    so CRM-originated writes don't echo back to CRM, and vice-versa.
  #}

  {#
    create_subscription in pg-ripple 0.78 takes:
      (name text, filter_sparql text DEFAULT NULL, filter_shape text DEFAULT NULL)
    Outbox tables are provisioned separately via pg-trickle (not required here).
  #}

  {% set sql_crm_sub %}
    SELECT pg_ripple.create_subscription(
        name         => 'crm_relay',
        filter_sparql => '
            FILTER EXISTS { ?s <http://example.org/email> ?e }
            FILTER(?g NOT IN (<urn:source:crm>))
        '
    );
  {% endset %}
  {% do run_query(sql_crm_sub) %}
  {{ log("✓ crm_relay subscription created", info=True) }}

  {% set sql_erp_sub %}
    SELECT pg_ripple.create_subscription(
        name         => 'erp_relay',
        filter_sparql => '
            FILTER EXISTS { ?s <http://example.org/email> ?e }
            FILTER(?g NOT IN (<urn:source:erp>))
        '
    );
  {% endset %}
  {% do run_query(sql_erp_sub) %}
  {{ log("✓ erp_relay subscription created", info=True) }}

  {{ log("", info=True) }}
  {{ log("pg_ripple bidi setup complete. Run 'dbt run-operation ingest_contacts' next.", info=True) }}

{% endmacro %}
