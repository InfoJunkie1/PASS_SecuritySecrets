/* =====================================================================
   01b_TempPerms.sql — Demo 1  ·  Secret #1: Temporary permissions
   Grants that expire on their own, removed by a nightly job.
   Simplified from github.com/InfoJunkie1/TempPerms

   Requires  : 00_setup.sql
   Reset     : 99_cleanup.sql
   ===================================================================== */
USE SecuritySecrets;
GO

/* ---------------------------------------------------------------------
   1. The register: what was granted, how to undo it, when it expires
   --------------------------------------------------------------------- */
CREATE TABLE audit.TempPermission (
    TempPermissionID int IDENTITY PRIMARY KEY,
    PrincipalName    sysname        NOT NULL,
    PermissionSql    nvarchar(400)  NOT NULL,   -- the GRANT that was run
    RevokeSql        nvarchar(400)  NOT NULL,   -- how to undo it
    Reason           nvarchar(200)  NOT NULL,
    ExpirationDate   date           NOT NULL,
    GrantedBy        sysname        NOT NULL DEFAULT SUSER_SNAME(),
    GrantedOn        datetime2      NOT NULL DEFAULT SYSDATETIME()
);
GO

/* ---------------------------------------------------------------------
   2. Grant with an expiration date
   --------------------------------------------------------------------- */
CREATE or ALTER PROCEDURE audit.GrantTempPermission
    @PrincipalName sysname,
    @PermissionSql nvarchar(400),
    @RevokeSql     nvarchar(400),
    @Reason        nvarchar(200),
    @Days          int = 7
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sp_executesql @PermissionSql;
    INSERT INTO audit.TempPermission
            (PrincipalName, PermissionSql, RevokeSql, Reason, ExpirationDate)
    VALUES  (@PrincipalName, @PermissionSql, @RevokeSql, @Reason,
             DATEADD(day, @Days, CAST(GETDATE() AS date)));
END;
GO

/* ---------------------------------------------------------------------
   3. The nightly job: revoke anything past its date
   --------------------------------------------------------------------- */
CREATE PROCEDURE audit.RevokeExpiredPermissions
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql nvarchar(400);
    DECLARE revoke_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT RevokeSql FROM audit.TempPermission
        WHERE ExpirationDate < CAST(GETDATE() AS date);
    OPEN revoke_cur;
    FETCH NEXT FROM revoke_cur INTO @sql;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sp_executesql @sql;
        FETCH NEXT FROM revoke_cur INTO @sql;
    END
    CLOSE revoke_cur;
    DEALLOCATE revoke_cur;
    DELETE FROM audit.TempPermission
    WHERE ExpirationDate < CAST(GETDATE() AS date);
END;
GO

-- Schedule audit.RevokeExpiredPermissions as a nightly SQL Agent job.
-- Production version (server level, error handling, orphaned users):
-- github.com/InfoJunkie1/TempPerms

/* ---------------------------------------------------------------------
   4. Demo: a grant with a due date
   --------------------------------------------------------------------- */

-- 4a. Before: dev_jordan can connect, and that's all
SELECT pr.name            AS Principal,
       pe.state_desc,
       pe.permission_name,
       CASE pe.class
            WHEN 0 THEN 'DATABASE'
            WHEN 1 THEN OBJECT_SCHEMA_NAME(pe.major_id) + '.' +
                        OBJECT_NAME(pe.major_id)
            WHEN 3 THEN 'SCHEMA::' + SCHEMA_NAME(pe.major_id)
            ELSE pe.class_desc
       END                AS Securable
FROM   sys.database_permissions pe
JOIN   sys.database_principals  pr
       ON pe.grantee_principal_id = pr.principal_id
WHERE  pr.name = 'dev_jordan'
ORDER  BY pe.permission_name;   -- CONNECT only
GO

EXECUTE AS USER = 'dev_jordan';
 SELECT TOP 3 * FROM staging.CustomerLoad;   -- fails: SELECT permission denied
REVERT;                                      -- run REVERT manually if the SELECT fails
GO

-- 4b. The loan
EXEC audit.GrantTempPermission
     @PrincipalName = 'dev_jordan',
     @PermissionSql = N'GRANT SELECT ON SCHEMA::staging TO dev_jordan;',
     @RevokeSql     = N'REVOKE SELECT ON SCHEMA::staging FROM dev_jordan;',
     @Reason        = N'Troubleshooting ticket #4821',
     @Days          = 3;
GO

SELECT PrincipalName, Reason, ExpirationDate, GrantedBy
FROM   audit.TempPermission;
GO

-- 4c. After: the grant is real — SELECT on SCHEMA::staging now shows up
SELECT pr.name            AS Principal,
       pe.state_desc,
       pe.permission_name,
       CASE pe.class
            WHEN 0 THEN 'DATABASE'
            WHEN 1 THEN OBJECT_SCHEMA_NAME(pe.major_id) + '.' +
                        OBJECT_NAME(pe.major_id)
            WHEN 3 THEN 'SCHEMA::' + SCHEMA_NAME(pe.major_id)
            ELSE pe.class_desc
       END                AS Securable
FROM   sys.database_permissions pe
JOIN   sys.database_principals  pr
       ON pe.grantee_principal_id = pr.principal_id
WHERE  pr.name = 'dev_jordan'
ORDER  BY pe.permission_name;   -- CONNECT + SELECT on SCHEMA::staging
GO

-- Verify as the account, not as yourself
EXECUTE AS USER = 'dev_jordan';
SELECT 'staging' AS SchemaName, permission_name
FROM   fn_my_permissions('staging', 'SCHEMA');      -- SELECT
SELECT TOP 3 * FROM staging.CustomerLoad;           -- succeeds now
REVERT;
GO

/* ---------------------------------------------------------------------
   5. Fast-forward: backdate the row, run the job
   --------------------------------------------------------------------- */
UPDATE audit.TempPermission
SET    ExpirationDate = DATEADD(day, -1, CAST(GETDATE() AS date))
WHERE  PrincipalName = 'dev_jordan';
GO

EXEC audit.RevokeExpiredPermissions;
GO

SELECT COUNT(*) AS RemainingLoans FROM audit.TempPermission;  -- 0
GO

-- 5a. After the job: the grant itself is gone, not just the register row
SELECT pr.name            AS Principal,
       pe.state_desc,
       pe.permission_name,
       CASE pe.class
            WHEN 0 THEN 'DATABASE'
            WHEN 1 THEN OBJECT_SCHEMA_NAME(pe.major_id) + '.' +
                        OBJECT_NAME(pe.major_id)
            WHEN 3 THEN 'SCHEMA::' + SCHEMA_NAME(pe.major_id)
            ELSE pe.class_desc
       END                AS Securable
FROM   sys.database_permissions pe
JOIN   sys.database_principals  pr
       ON pe.grantee_principal_id = pr.principal_id
WHERE  pr.name = 'dev_jordan'
ORDER  BY pe.permission_name;   -- back to CONNECT only
GO

EXECUTE AS USER = 'dev_jordan';
 SELECT TOP 3 * FROM staging.CustomerLoad;   -- fails again: SELECT permission denied
REVERT;                                      -- run REVERT manually if the SELECT fails
GO
