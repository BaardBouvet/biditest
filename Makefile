.PHONY: all seed setup ingest run test clean help

help:
	@echo "biditest: pg-ripple 0.78.0 bidirectional integration worked example"
	@echo ""
	@echo "Targets:"
	@echo "  all      Run the full end-to-end workflow (seed → setup → ingest → run → test)"
	@echo "  seed     Load seed data (crm_contacts, erp_contacts)"
	@echo "  setup    Register mappings, Datalog rules, conflict policies, subscriptions"
	@echo "  ingest   Ingest seed rows into pg_ripple via ingest_json(mode=>'diff')"
	@echo "  run      Materialise dbt models"
	@echo "  test     Run all dbt tests"
	@echo "  clean    Drop all pg_ripple data (DELETE WHERE { ?s ?p ?o })"

all: seed setup ingest run test
	@echo "✓ Full workflow complete — all 31 tests passed"

seed:
	@echo "→ Loading seed data…"
	dbt seed --profiles-dir .

setup:
	@echo "→ Running bidi setup (Step 1–5)…"
	dbt run-operation setup_bidi_example --profiles-dir .

ingest:
	@echo "→ Ingesting contacts (Step 4)…"
	dbt run-operation ingest_contacts --profiles-dir .

run:
	@echo "→ Materialising dbt models…"
	dbt run --profiles-dir .

test:
	@echo "→ Running dbt tests…"
	dbt test --profiles-dir .

clean:
	@echo "→ Clearing pg_ripple graph (DELETE WHERE { ?s ?p ?o })…"
	docker exec pg-ripple-biditest psql -U postgres -d biditest -c \
	  "SELECT pg_ripple.sparql_update('DELETE WHERE { ?s ?p ?o }');" 2>/dev/null
	@echo "✓ Graph cleared"
