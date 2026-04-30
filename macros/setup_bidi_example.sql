{#
  setup_bidi_example()
  ─────────────────────────────────────────────────────────────────────────────
  Implements Steps 1–5 of the worked example: registers mappings, Datalog rules,
  conflict policies, and subscriptions. Call after the database is initialized
  but before ingesting data:
    dbt run-operation setup_bidi_example

  The macro is idempotent — re-running it on a database that already has the
  mappings/rules/policies in place is safe (pg_ripple uses CREATE OR REPLACE
  / IF NOT EXISTS semantics internally).
#}

{% macro setup_bidi_example() %}

  {{ log("Registering JSON mappings…", info=True) }}

  {# ── Step 1: Register the two source-graph JSON mappings (BIDI-ATTR-01) ── #}

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
  {{ log("  ✓ crm_contact mapping registered", info=True) }}

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
  {{ log("  ✓ erp_contact mapping registered", info=True) }}

  {# ── Step 2: Composite-identity rule — merge on shared email (BIDI-REF-01) ── #}

  {{ log("Loading Datalog rule…", info=True) }}

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
  {{ log("  ✓ same_email Datalog rule loaded (BIDI-REF-01)", info=True) }}

  {# ── Step 3: latest_wins conflict policy on ex:name (BIDI-CONFLICT-01) ─── #}

  {{ log("Registering conflict policy…", info=True) }}

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
  {{ log("  ✓ latest_wins policy registered for ex:name (BIDI-CONFLICT-01)", info=True) }}

  {# ── Step 5: Subscriptions for both relays (BIDI-LOOP-01) ────────────────── #}

  {{ log("Creating subscriptions…", info=True) }}

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
  {{ log("  ✓ crm_relay subscription created", info=True) }}

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
  {{ log("  ✓ erp_relay subscription created", info=True) }}

  {{ log("", info=True) }}
  {{ log("pg-ripple setup complete. Run 'dbt seed' next.", info=True) }}

{% endmacro %}
