/* =====================================================================
   99_cleanup.sql — Reset the demo environment between runs
   PASS 2026: "Mom/Daughter Duo: DBA Teaches Data Engineer Security
   Secrets Worth Stealing"

   Database: SecuritySecrets
   Undoes everything demos 01, 01b, 03 and 04 change, and leaves the
   database exactly as 00_setup.sql leaves it. Re-runnable: every step
   checks first, so running it twice (or on a clean database) is a no-op.

   Run order for a full reset:  99_cleanup.sql  ->  00_setup.sql (optional)
   To remove the database entirely: 99b_teardown.sql
   ===================================================================== */

USE SecuritySecrets;
GO

/* ---------------------------------------------------------------------
   Demo 03 — drop the dynamic data masks
   ---------------------------------------------------------------------
   Built from what sys.masked_columns actually reports rather than from a
   hardcoded column list behind an IF: the ALTER statement only comes into
   existence for a column the catalog says is masked, so this can't raise
   "column does not have a data masking function". It also picks up any
   extra column you mask on the fly while trying things out.
   --------------------------------------------------------------------- */
DECLARE @sql nvarchar(max) = N'';

SELECT  @sql = @sql
      + N'ALTER TABLE dbo.Customer ALTER COLUMN '
      + QUOTENAME(name) + N' DROP MASKED;' + CHAR(13) + CHAR(10)
FROM    sys.masked_columns
WHERE   object_id = OBJECT_ID('dbo.Customer')
  AND   is_masked = 1
  AND   ISNULL(masking_function, N'') <> N'';

IF @sql <> N''
BEGIN
    BEGIN TRY
        EXEC sp_executesql @sql;
        PRINT 'Dropped dynamic data masks on dbo.Customer.';
    END TRY
    BEGIN CATCH
        -- A reset script should never halt partway. Say what happened
        -- and carry on; the static-mask restore below fixes the data anyway.
        PRINT 'Could not drop one or more masks: ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
    PRINT 'No dynamic data masks on dbo.Customer — nothing to drop.';
GO

/* ---------------------------------------------------------------------
   Demo 03 — restore the seeded customers
   The static-masking step overwrites LastName/Email/Phone/SSN in place,
   so put the original visibly-fake values back. Matched by row order,
   so it works whatever the IDENTITY values happen to be.
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Customer', 'U') IS NOT NULL
BEGIN
    ;WITH ordered AS (
    SELECT CustomerID,
           ROW_NUMBER() OVER (ORDER BY CustomerID) AS rn
    FROM   dbo.Customer
), seed AS (
    SELECT * FROM (VALUES
        (1, N'Smith',  N'smith@contoso.com',  '314-555-0101', '123456789',  5000),
        (2, N'Jones',  N'jones@contoso.com',  '314-555-0102', '234567891',  7500),
        (3, N'Nguyen', N'nguyen@contoso.com', '314-555-0103', '345678912', 12000),
        (4, N'Garcia', N'garcia@contoso.com', '314-555-0104', '456789123',  3000),
        (5, N'Okafor', N'okafor@contoso.com', '314-555-0105', '567891234', 20000)
    ) v (rn, LastName, Email, Phone, SSN, CreditLimit)
)
UPDATE  c
SET     c.LastName    = s.LastName,
        c.Email       = s.Email,
        c.Phone       = s.Phone,
        c.SSN         = s.SSN,
        c.CreditLimit = s.CreditLimit
FROM    dbo.Customer c
JOIN    ordered o ON o.CustomerID = c.CustomerID
JOIN    seed    s ON s.rn         = o.rn;
END
GO

/* ---------------------------------------------------------------------
   Demo 01 — module-signing objects
   Drop the procedure first: that removes the signature, so the
   certificate and its user can then go.
   --------------------------------------------------------------------- */
IF OBJECT_ID('etl.ResetStaging', 'P') IS NOT NULL
    DROP PROCEDURE etl.ResetStaging;
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'EtlCertUser')
    DROP USER EtlCertUser;
GO

IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'EtlSigningCert')
    DROP CERTIFICATE EtlSigningCert;
GO

/* ---------------------------------------------------------------------
   Demo 01 — take the scoped grants back off the pipeline account
   REVOKE on a permission that was never granted is a no-op.
   --------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'etl_service')
BEGIN
    REVOKE SELECT         ON SCHEMA::src     FROM etl_service;
    REVOKE INSERT, UPDATE ON SCHEMA::staging FROM etl_service;
    REVOKE EXECUTE        ON SCHEMA::etl     FROM etl_service;
END
GO

/* ---- If the role alternative was run instead of direct grants ---- */
IF EXISTS (SELECT 1 FROM sys.database_principals
           WHERE name = 'etl_pipeline' AND type = 'R')
BEGIN
    IF EXISTS (SELECT 1
               FROM   sys.database_role_members rm
               JOIN   sys.database_principals r ON r.principal_id = rm.role_principal_id
               JOIN   sys.database_principals m ON m.principal_id = rm.member_principal_id
               WHERE  r.name = 'etl_pipeline' AND m.name = 'etl_service')
        ALTER ROLE etl_pipeline DROP MEMBER etl_service;

    DROP ROLE etl_pipeline;
END
GO

/* ---------------------------------------------------------------------
   Demo 01 — re-seed staging.CustomerLoad
   The signed-procedure step truncates it.
   --------------------------------------------------------------------- */
IF OBJECT_ID('staging.CustomerLoad', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM staging.CustomerLoad)
    INSERT INTO staging.CustomerLoad (CustomerID)
    SELECT CustomerID FROM dbo.Customer;
GO

/* ---------------------------------------------------------------------
   Demo 01b — temporary-permission objects
   --------------------------------------------------------------------- */
IF OBJECT_ID('audit.GrantTempPermission', 'P') IS NOT NULL
    DROP PROCEDURE audit.GrantTempPermission;
GO
IF OBJECT_ID('audit.RevokeExpiredPermissions', 'P') IS NOT NULL
    DROP PROCEDURE audit.RevokeExpiredPermissions;
GO
IF OBJECT_ID('audit.TempPermission', 'U') IS NOT NULL
    DROP TABLE audit.TempPermission;
GO

/* ---------------------------------------------------------------------
   Demos 01b and 04 — anything left on the borrowed developer account
   (the temporary SELECT, and the unexpected GRANT the delta catches)
   --------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'dev_jordan')
BEGIN
    REVOKE SELECT  ON SCHEMA::staging FROM dev_jordan;
    REVOKE CONTROL ON SCHEMA::staging FROM dev_jordan;
END
GO

/* ---------------------------------------------------------------------
   Demo 04 — clear today's snapshot and re-arm "yesterday"
   so the delta report has something to compare against next run.
   --------------------------------------------------------------------- */
IF OBJECT_ID('audit.PermissionSnapshot', 'U') IS NOT NULL
    DELETE FROM audit.PermissionSnapshot
    WHERE  SnapshotDate = CAST(GETDATE() AS date);
GO

IF OBJECT_ID('audit.PermissionSnapshot', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM audit.PermissionSnapshot
                   WHERE SnapshotDate = CAST(DATEADD(day, -1, GETDATE()) AS date))
INSERT INTO audit.PermissionSnapshot
        (SnapshotDate, PrincipalName, PermissionName, ObjectName)
SELECT  CAST(DATEADD(day, -1, GETDATE()) AS date),
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

PRINT 'SecuritySecrets reset — ready to run the demos again.';
