"""
04b_audit_events.py — Demo 4  ·  Secret #4: Pipeline-side traceability

Every run emits a structured event per step — run id, identity, step,
target, rows, status — and it lands somewhere the pipeline's own
identity cannot edit.
"""

import datetime
import getpass
import json
import logging
import uuid

# In production this handler ships to a central, append-only store
# (Log Analytics, an append-only table, an events lakehouse) — not a
# local file the pipeline identity can rewrite.
audit_logger = logging.getLogger("pipeline.audit")
audit_logger.setLevel(logging.INFO)
audit_logger.addHandler(logging.StreamHandler())

RUN_ID = str(uuid.uuid4())                        # one id per run, stamped
                                                  # on every event


def audit_event(step: str, target: str, rows: int, status: str) -> None:
    event = {
        "run_id":   RUN_ID,
        "ts":       datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "identity": getpass.getuser(),            # service principal id in prod
        "step":     step,
        "target":   target,
        "rows":     rows,
        "status":   status,
    }
    audit_logger.info(json.dumps(event))


# ---- Demo: instrumented pipeline steps ----
if __name__ == "__main__":
    audit_event("extract_orders",  "src.Orders",           5, "success")
    audit_event("load_customers",  "dbo.Customer",         5, "success")
    audit_event("reset_staging",   "staging.CustomerLoad", 0, "success")

# ---------------------------------------------------------------------
# Verified output (one event, pretty-printed)
# ---------------------------------------------------------------------
# {
#   "run_id":   "964a9de2-57f4-4e82-a998-43ed18678743",
#   "ts":       "2026-07-20T14:38:29.688891+00:00",
#   "identity": "pipeline_user",
#   "step":     "load_customers",
#   "target":   "dbo.Customer",
#   "rows":     5,
#   "status":   "success"
# }
# ---------------------------------------------------------------------

# Fabric equivalent: write these to an append-only Delta table the
# pipeline identity has INSERT on but not UPDATE or DELETE.
