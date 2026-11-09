/* =====================================================================
   04_audit_delta.sql — Demo 4  ·  Secret #4: The permissions delta
   Snapshot permissions nightly; report only what changed.

   Requires  : 00_setup.sql (pre-seeds yesterday's snapshot)
   Reset     : 99_cleanup.sql
   ===================================================================== */
USE SecuritySecrets;
GO

-- Run this first so the delta has something to catch.
GRANT CONTROL ON SCHEMA::staging TO dev_jordan;

/* ---------------------------------------------------------------------
   1. Nightly job: snapshot today's permissions
   --------------------------------------------------------------------- */
DELETE FROM audit.PermissionSnapshot        -- keeps re-runs idempotent
WHERE SnapshotDate = CAST(GETDATE() AS date);

INSERT INTO audit.PermissionSnapshot
        (SnapshotDate, PrincipalName, PermissionName, ObjectName)
SELECT  CAST(GETDATE() AS date),
        pr.name, pe.permission_name,
        CASE pe.class
             WHEN 0 THEN 'DATABASE'
             WHEN 1 THEN OBJECT_SCHEMA_NAME(pe.major_id) + '.' +
                         OBJECT_NAME(pe.major_id)
             WHEN 3 THEN 'SCHEMA::' + SCHEMA_NAME(pe.major_id)
             ELSE pe.class_desc
        END
FROM    sys.database_permissions pe
JOIN    sys.database_principals pr
        ON pe.grantee_principal_id = pr.principal_id
WHERE   pr.name <> 'public';
GO

/* ---------------------------------------------------------------------
   2. Morning report: what changed since yesterday
   --------------------------------------------------------------------- */
WITH today AS (
    SELECT * FROM audit.PermissionSnapshot
    WHERE SnapshotDate = CAST(GETDATE() AS date)
), yesterday AS (
    SELECT * FROM audit.PermissionSnapshot
    WHERE SnapshotDate = CAST(DATEADD(day, -1, GETDATE()) AS date)
)
SELECT COALESCE(t.PrincipalName,  y.PrincipalName)  AS PrincipalName,
       COALESCE(t.PermissionName, y.PermissionName) AS PermissionName,
       COALESCE(t.ObjectName,     y.ObjectName)     AS ObjectName,
       CASE WHEN y.PrincipalName IS NULL THEN 'GRANTED'
            WHEN t.PrincipalName IS NULL THEN 'REVOKED' END AS ChangeType
FROM      today     t
FULL JOIN yesterday y
       ON  t.PrincipalName  = y.PrincipalName
       AND t.PermissionName = y.PermissionName
       AND t.ObjectName     = y.ObjectName
WHERE t.PrincipalName IS NULL OR y.PrincipalName IS NULL;
GO
