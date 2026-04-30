# biditest

A devcontainer project that walks through the **pg-ripple v0.78.0 bidirectional
integration worked example**: merging CRM and ERP contacts on email with
last-modified-wins names.

Source spec: [v0.77.0-full.md — Worked example](https://github.com/grove/pg-ripple/blob/main/roadmap/v0.77.0-full.md#worked-example-merging-crm-and-erp-contacts-on-email-with-last-modified-wins-names)

> **Note:** the worked example was introduced in v0.77.0 and ships unchanged in v0.78.0.

## What this project demonstrates

| pg-ripple feature | Step |
|---|---|
| **BIDI-ATTR-01** — named-graph source attribution | Step 1 (register mappings) |
| **BIDI-REF-01** — composite-identity Datalog rule (`sameAs` on email) | Step 2 |
| **BIDI-CONFLICT-01** — `latest_wins` policy on `ex:name` | Step 3 |
| **BIDI-DIFF-01** — diff-mode ingest, per-triple `prov:generatedAtTime` annotations | Step 4 |
| **BIDI-LOOP-01** — `exclude_graphs` prevents echo storms | Step 5 |
| **BIDI-CAS-01** — outbound UPDATE event with `base` CAS diff | Step 6 |
| **BIDI-LINKBACK-01** — `record_linkback(target_id => '4011')` | Step 7 |

## Stack

| Component | Version |
|---|---|
| [pg-ripple](https://github.com/grove/pg-ripple) | 0.78.0 |
| PostgreSQL | 18 (bundled in the pg-ripple image) |
| [dbt-core](https://docs.getdbt.com/) | ≥ 1.8 |
| [dbt-postgres](https://docs.getdbt.com/docs/core/connect-data-platform/postgres-setup) | ≥ 1.8 |
| [dbt-pg-ripple](https://github.com/grove/pg-ripple/tree/main/clients/dbt-pg-ripple) | from source |

## Getting started

Choose one of two ways to run the database — plain Docker or the devcontainer.

### Option A — Local (plain Docker + local venv)

**1. Start the pg-ripple container**

```bash
docker run -d \
  --name pg-ripple-biditest \
  -e POSTGRES_DB=biditest \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  ghcr.io/grove/pg-ripple:0.78.0

# Initialise the extension
docker exec -i pg-ripple-biditest psql -U postgres -d biditest \
  < init/01_init_ripple.sql
```

**2. Create the virtual environment and install dependencies**

```bash
# uv is used here because python3-venv may not be installed system-wide
curl -Ls https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env   # or restart your shell

uv venv .venv
uv pip install setuptools
uv pip install -r requirements.txt
source .venv/bin/activate
```

**3. Verify the connection**

```bash
# DBT_HOST defaults to localhost — no override needed
dbt debug --profiles-dir .
```

### Option B — Devcontainer

In VS Code: **Reopen in Container** (requires the
[Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)).

Docker Compose will:
- Pull `ghcr.io/grove/pg-ripple:0.78.0`
- Run `init/01_init_ripple.sql` to `CREATE EXTENSION pg_ripple`
- Start the Python devcontainer and install the Python dependencies
- Set `DBT_HOST=db` automatically so dbt resolves the Compose service name

Then verify:

```bash
dbt debug
```

Environment variables

The `profiles.yml` reads connection details from environment variables so you
never need to edit the file directly:

| Variable | Default | Notes |
|---|---|---|
| `DBT_HOST` | `localhost` | Set to `db` inside the devcontainer |
| `DBT_PORT` | `5432` | |
| `DBT_USER` | `postgres` | |
| `DBT_PASSWORD` | `postgres` | |
| `DBT_DBNAME` | `biditest` | |

---

## Workflow

### 1. Set up pg-ripple infrastructure

```bash
dbt run-operation setup_bidi_example
```

Registers the two JSON mappings (`crm_contact`, `erp_contact`), loads the
composite-identity Datalog rule, registers the `latest_wins` conflict policy
on `ex:name`, and creates the `crm_relay` / `erp_relay` subscriptions.

### 2. Load the seed data

```bash
dbt seed
```

This loads `seeds/crm_contacts.csv` and `seeds/erp_contacts.csv` into the
`raw` schema as plain PostgreSQL tables.

### 3. Ingest contacts into pg-ripple (Step 4)

```bash
dbt run-operation ingest_contacts
```

Reads from the seed tables and calls `pg_ripple.ingest_json(..., mode => 'diff')`
for each contact.  After this step:

- The CRM contact `c-42` and ERP contact `7` share `ada@example.com` → the
  Datalog rule fires and links them via `owl:sameAs`.
- The `latest_wins` policy resolves `ex:name` to `"Ada Lovelace"` (ERP at
  11:30 beats CRM at 10:00).

### 4. Materialise dbt models

```bash
dbt run
```

| Model | What it shows |
|---|---|
| `staging.stg_crm_contacts` | Normalised CRM seed view |
| `staging.stg_erp_contacts` | Normalised ERP seed view |
| `marts.merged_contacts` | Resolved projection from SPARQL (one row per unique email) |
| `marts.graph_stats` | Per-graph triple counts and conflict metrics |

### 5. Run the dbt tests

```bash
dbt test
```

| Test | Type | What it checks |
|---|---|---|
| `assert_latest_wins_name` | singular | `ada@example.com` resolves to `"Ada Lovelace"` (ERP at 11:30 beats CRM at 10:00 under `latest_wins`) |
| `assert_email_merge_deduplicates` | singular | Each email appears exactly once in `merged_contacts` (the `sameAs` Datalog rule deduplicated correctly) |
| `assert_both_graphs_present` | singular | Both `<urn:source:crm>` and `<urn:source:erp>` exist in `graph_stats` with at least one triple |
| `not_null` / `unique` on `stg_crm_contacts` | generic | `contact_id`, `email`, `name`, `last_modified_at`, `subject_iri`, `graph_iri` |
| `not_null` / `unique` on `stg_erp_contacts` | generic | same columns as CRM |
| `not_null` / `unique` on `merged_contacts` | generic | `subject_iri`, `email`, `name` |
| `not_null` / `unique` on `graph_stats` | generic | `graph_iri`, `triple_count`, `conflicts_total` |

You can also target tests for a specific model:

```bash
dbt test --select merged_contacts
```

---

## Simulating further steps

### Simulate Step 8 — ERP name update after initial sync

```bash
dbt run-operation simulate_erp_name_update
dbt run --select merged_contacts
```

The updated ERP name has a later `lastModified` → `latest_wins` promotes it →
`merged_contacts` now shows `"Ada Lovelace (updated)"`.

### Simulate Step 7 — linkback after fresh ERP create

When the ERP relay creates `grace@example.com` in ERP and gets back ID `4011`:

```bash
# First get the event_id from the outbox
psql -h db -U postgres -d biditest \
  -c "SELECT event_id FROM pg_ripple.erp_relay_outbox \
      WHERE (payload->>'subject_resolved')::boolean = false LIMIT 1;"

# Then record the linkback
dbt run-operation simulate_linkback \
  --args '{"event_id": "<paste UUID here>", "target_id": "4011"}'
```

---

## Project layout

```
.devcontainer/
  devcontainer.json          # Dev Containers config (Python 3.12 + pg-ripple db)
  docker-compose.yml         # db (pg-ripple:0.78.0) + app services

init/
  01_init_ripple.sql         # CREATE EXTENSION, ALTER DATABASE defaults, GRANT permissions

seeds/
  crm_contacts.csv           # CRM contacts (id, email, name, last_modified)
  erp_contacts.csv           # ERP contacts

macros/
  setup_bidi_example.sql     # Steps 1–5: register mappings, rules, policies, subscriptions
  ingest_contacts.sql        # Step 4: ingest_json(mode=>'diff') for each seed row
  test_scenarios.sql         # Interactive macros: simulate_erp_name_update, simulate_linkback
  generate_schema_name.sql   # Custom schema naming for dbt

models/
  staging/
    stg_crm_contacts.sql     # Staging view over crm_contacts seed
    stg_erp_contacts.sql     # Staging view over erp_contacts seed
    schema.yml
  marts/
    merged_contacts.sql      # Resolved projection via pg_ripple.sparql()
    graph_stats.sql          # pg_ripple.graph_stats() as a table
    schema.yml               # Generic not_null/unique/accepted_values tests

tests/
  assert_latest_wins_name.sql           # latest_wins picks ERP name for ada@example.com
  assert_email_merge_deduplicates.sql   # sameAs rule produces one row per email
  assert_both_graphs_present.sql        # both named graphs have triples after ingest

profiles.yml                 # dbt profile (connects to the db service)
dbt_project.yml
requirements.txt
```

## Reference

- [pg-ripple v0.77.0 full spec](https://github.com/grove/pg-ripple/blob/main/roadmap/v0.77.0-full.md) (worked example origin)
- [pg-ripple v0.78.0 changelog](https://github.com/grove/pg-ripple/blob/main/CHANGELOG.md)
- [pg-ripple Docker image](https://github.com/grove/pg-ripple/pkgs/container/pg-ripple)
- [dbt-pg-ripple adapter](https://github.com/grove/pg-ripple/tree/main/clients/dbt-pg-ripple)
