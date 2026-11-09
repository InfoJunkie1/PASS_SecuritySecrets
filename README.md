# Demo Scripts — PASS 2026

**Mom/Daughter Duo: DBA Teaches Data Engineer Security Secrets Worth Stealing**
Sharon Reid · Allison Harris

Scripts are numbered by security secret; a letter marks an additional demo within the same secret.

| Script | Demo | What it shows |
|---|---|---|
| `00_setup.sql` | — | Builds the SecuritySecrets database: schemas, logins, tables (including the `dbo.Payroll` table nothing should be able to read), seed data, and a pre-seeded "yesterday" permissions snapshot. Run once before anything else. |
| `01_LeastPrivilege.sql` | Demo&nbsp;1 | Direct grants on securables vs. db_owner; `fn_my_permissions` self-check; `src.Orders` works / `dbo.Payroll` **denied**; module signing — TRUNCATE denied → signed procedure works → ALTER removes the signature → re-sign |
| `01b_TempPerms.sql` | Demo&nbsp;1 | Temporary permissions with automatic expiration (a loan with a due date): the principal's permissions shown before the grant, after it, and after the nightly job revokes it; simplified from [TempPerms](https://github.com/InfoJunkie1/TempPerms) |
| `01c_UnityCatalog_grants.sql` | Demo&nbsp;1 | The same least-privilege approach in Databricks Unity Catalog |
| `02_secrets.py` | Demo&nbsp;2 | The credential escalation ladder: hardcoded → environment variable → Key Vault → managed identity |
| `02b_databricks_secrets.py` | Demo&nbsp;2 | Databricks secret scopes, including how `print(pwd)` shows `[REDACTED]` |
| `03_masking.sql` | Demo&nbsp;3 | Dynamic data masking (including the inference caveat) and static masking on a dev refresh |
| `03b_faker_synthetic.py` | Demo&nbsp;3 | Synthetic customers with Faker, with a reproducible seed for CI |
| `04_audit_delta.sql` | Demo&nbsp;4 | Permissions snapshot and a morning delta report that catches a new, unexpected GRANT |
| `04b_audit_events.py` | Demo&nbsp;4 | Structured pipeline audit events (run id, identity, step, target, rows, status) |
| `99_cleanup.sql` | — | Resets the demos so they can be run again: drops the masks, restores the seeded rows, removes the Demo 1 objects and grants, clears today's snapshot and re-creates "yesterday". Re-runnable. |
| `99b_teardown.sql` | — | Removes everything: drops the SecuritySecrets database and the three demo logins. Re-runnable. |

## Requirements

- SQL Server (any supported edition, including Developer) for the `.sql` scripts.
- Python with: `pip install pyodbc faker pandas sqlalchemy azure-identity azure-keyvault-secrets`
- A Databricks workspace for `01c` and `02b`.

## Connecting

The `.sql` scripts run against whatever instance your query window is connected to.
`03b_faker_synthetic.py` reads the server name from the `DEMO_SQL_SERVER` environment
variable and defaults to `localhost`; set it to your instance if different (for example `MYHOST\SQL2022`).
A named instance needs the SQL Server Browser service running.

## Run order

1. `00_setup.sql` (once)
2. `01_LeastPrivilege.sql` → `01b_TempPerms.sql` → `01c_UnityCatalog_grants.sql` (Databricks)
3. `02_secrets.py` → `02b_databricks_secrets.py` (Databricks)
4. `03_masking.sql` → `03b_faker_synthetic.py`
5. `04_audit_delta.sql` (the GRANT at the top gives the delta something to catch) → `04b_audit_events.py`
6. `99_cleanup.sql` to reset before running the demos again

`00_setup.sql` and `99_cleanup.sql` are both re-runnable — every object is created or dropped
only if it needs to be, and seed data is only re-inserted when it's missing. When you're done,
`99b_teardown.sql` removes the database and logins entirely.

## Notes

- **Grants are made directly on securables, not through roles** — it's easier to
  see what a given principal actually has. The role version is kept commented in
  `01_LeastPrivilege.sql` for the case it's meant for: the same permission set
  reused across multiple databases.
- Statements that are expected to fail (permission denied) are marked in the scripts.
  `EXECUTE AS` blocks are split into separate batches so a failing statement doesn't
  skip the `REVERT`; if a statement fails, run the `REVERT` manually before continuing.
- `dbo.Payroll` deliberately has **no grants to anyone**. Leave it that way — the
  denial is the point of Demo 1.
- Demo passwords are placeholders — never reuse them in real environments.
- Faker output is seeded (`Faker.seed(2026)`) and verified reproducible on Python
  3.11 and 3.13 — the sample output in `03b` is real, not mocked. SSNs are masked
  in the sample output only, so the repository doesn't trip data-loss scanners;
  running the script shows the full synthetic values.
