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
  {% do adapter.execute(sql_crm_mapping, auto_begin=False, fetch=False) %}
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
  {% do adapter.execute(sql_erp_mapping, auto_begin=False, fetch=False) %}
  {{ log("  ✓ erp_contact mapping registered", info=True) }}

  {# ── Step 2: Composite-identity rule — merge on shared email (BIDI-REF-01) ── #}

  {{ log("Loading Datalog rule…", info=True) }}

  {% set sql_drop_rules %}
    DO $$
    BEGIN
      PERFORM pg_ripple.drop_rules('same_email');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END $$;
  {% endset %}
  {% do adapter.execute(sql_drop_rules, auto_begin=False, fetch=False) %}

  {% set sql_load_rules %}
    SELECT pg_ripple.load_rules(
        rules    => '?x <http://www.w3.org/2002/07/owl#sameAs> ?y :-
                       ?x <http://example.org/email> ?e,
                       ?y <http://example.org/email> ?e,
                       ?x != ?y .',
        rule_set => 'same_email'
    );
  {% endset %}
  {% do adapter.execute(sql_load_rules, auto_begin=False, fetch=False) %}
  {{ log("  ✓ same_email Datalog rule loaded (BIDI-REF-01)", info=True) }}

  {# ── Step 3: latest_wins conflict policy on ex:name (BIDI-CONFLICT-01) ─── #}

  {{ log("Registering conflict policy…", info=True) }}

  {% set sql_conflict %}
    SELECT pg_ripple.register_conflict_policy(
        predicate => 'http://example.org/name',
        strategy  => 'latest_wins'
    );
  {% endset %}
  {% do adapter.execute(sql_conflict, auto_begin=False, fetch=False) %}
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
  {% do adapter.execute(sql_crm_sub, auto_begin=False, fetch=False) %}
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
  {% do adapter.execute(sql_erp_sub, auto_begin=False, fetch=False) %}
  {{ log("  ✓ erp_relay subscription created", info=True) }}

  {# ── Step 6: Datalog view for automatic inference (BIDI-REF-01) ──────────── #}

  {{ log("Creating datalog view for automatic inference…", info=True) }}

  {# create_datalog_view_from_rule_set() is not idempotent, so drop the stream
     table if it exists from a previous run. #}
  {% set sql_drop_view %}
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'same_email_inferred'
      ) THEN
        PERFORM pg_ripple.drop_datalog_view('same_email_inferred');
      END IF;
    END $$;
  {% endset %}
  {% do adapter.execute(sql_drop_view, auto_begin=False, fetch=False) %}

  {# create_datalog_view_from_rule_set() registers a pg_trickle-managed stream
     table that re-runs same_email inference on a 1s schedule whenever the base
     VP tables change. decode=false is required: decode=true generates a column
     alias 's' internally that confuses pg_trickle's query parser.
     
     Note: On initial setup, this may fail because the VP tables don't exist yet.
     The view is optional for the tests — load_rules alone provides query-time
     inference. #}
  {% set sql_datalog_view %}
    DO $$
    BEGIN
      PERFORM pg_ripple.create_datalog_view_from_rule_set(
          name     => 'same_email_inferred',
          rule_set => 'same_email',
          goal     => 'SELECT ?x ?y WHERE { ?x <http://www.w3.org/2002/07/owl#sameAs> ?y }',
          schedule => '1s',
          decode   => false
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END $$;
  {% endset %}
  {% do adapter.execute(sql_datalog_view, auto_begin=False, fetch=False) %}

  {{ log("  ✓ same_email_inferred datalog view creation attempted (optional)", info=True) }}

  {% do adapter.execute("COMMIT", auto_begin=False, fetch=False) %}

  {{ log("", info=True) }}
  {{ log("pg-ripple setup complete. Run 'dbt seed' next.", info=True) }}

{% endmacro %}
