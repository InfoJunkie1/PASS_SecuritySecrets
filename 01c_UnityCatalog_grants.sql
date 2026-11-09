-- =====================================================================
-- 01c_UnityCatalog_grants.sql — Demo 1  ·  Secret #1 in Databricks
-- Same least-privilege model, Unity Catalog syntax.
-- Run in a Databricks SQL editor or notebook; adjust names to workspace.
-- =====================================================================

-- Grants live at catalog / schema / table level
GRANT USE CATALOG  ON CATALOG  prod            TO `etl-pipeline-sp`;
GRANT USE SCHEMA   ON SCHEMA   prod.silver     TO `etl-pipeline-sp`;
GRANT SELECT       ON SCHEMA   prod.silver     TO `etl-pipeline-sp`;
GRANT MODIFY       ON TABLE    prod.gold.sales TO `etl-pipeline-sp`;

-- Verify, the equivalent of fn_my_permissions
SHOW GRANTS ON TABLE prod.gold.sales;

-- The pattern:
--   * one service principal per pipeline, not one shared account
--   * grants on schemas rather than tables where possible
--   * never ALL PRIVILEGES
