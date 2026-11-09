/* =====================================================================
   01_LeastPrivilege.sql — Demo 1  ·  Secret #1: Least Privilege
   Scoped grants on securables, plus module signing for the one
   operation that cannot be granted granularly.

   Requires  : 00_setup.sql
   Reset     : 99_cleanup.sql
   ===================================================================== */

USE SecuritySecrets;
GO

/* ---------------------------------------------------------------------
   1. The shortcut
   --------------------------------------------------------------------- */
-- How a large share of pipelines actually run. Do not do this.
-- ALTER ROLE db_owner ADD MEMBER etl_service;

/* ---------------------------------------------------------------------
   2. Scoped grants — the pipeline's job list, as permissions
   ---------------------------------------------------------------------
   Grant directly on the securables the pipeline touches, so what the
   account can do is visible in one place. Schema-scoped, so new tables
   in staging are covered automatically — and dbo stays out of reach.
   --------------------------------------------------------------------- */
GRANT SELECT         ON SCHEMA::src     TO etl_service;   -- read the landing zone
GRANT INSERT, UPDATE ON SCHEMA::staging TO etl_service;   -- build the work tables
GRANT EXECUTE        ON SCHEMA::etl     TO etl_service;   -- run its own procs
GO

-- Never grant at the database level. db_datareader is db_owner's
-- quieter cousin: it reads everything, including dbo.Payroll.

-- Role alternative — only when the same permission set is reused across
-- several databases and nothing is added to it per-database.
--CREATE ROLE etl_pipeline;
--GRANT SELECT         ON SCHEMA::src     TO etl_pipeline;
--GRANT INSERT, UPDATE ON SCHEMA::staging TO etl_pipeline;
--GRANT EXECUTE        ON SCHEMA::etl     TO etl_pipeline;
--ALTER ROLE etl_pipeline ADD MEMBER etl_service;
--GO

/* ---------------------------------------------------------------------
   3. Verify as the account, not as yourself
   --------------------------------------------------------------------- */
EXECUTE AS USER = 'etl_service';

-- Database-level: should be almost nothing.
SELECT entity_name, subentity_name, permission_name
FROM   fn_my_permissions(NULL, 'DATABASE')
ORDER  BY permission_name;

-- Schema-level: the actual job list. dbo returns nothing.
SELECT 'src'     AS SchemaName, permission_name FROM fn_my_permissions('src',     'SCHEMA')
UNION ALL
SELECT 'staging',                permission_name FROM fn_my_permissions('staging', 'SCHEMA')
UNION ALL
SELECT 'etl',                    permission_name FROM fn_my_permissions('etl',     'SCHEMA')
UNION ALL
SELECT 'dbo',                    permission_name FROM fn_my_permissions('dbo',     'SCHEMA')
ORDER  BY SchemaName, permission_name;

REVERT;
GO

/* ---------------------------------------------------------------------
   4. What it can do vs. what it cannot
   --------------------------------------------------------------------- */
EXECUTE AS USER = 'etl_service';
SELECT TOP 3 * FROM src.Orders;        -- succeeds: reading source is its job
REVERT;
GO

EXECUTE AS USER = 'etl_service';
 SELECT TOP 3 * FROM dbo.Payroll;      -- expected to fail: SELECT permission denied
REVERT;                                -- run REVERT manually if the SELECT fails
GO

/* ---------------------------------------------------------------------
   Deriving the grant list (reference, not run)
   ---------------------------------------------------------------------
     1. Attach the scoped grants with nothing in them.
     2. Run the pipeline against dev; it fails on the first thing it
        cannot do.
     3. Add exactly that grant. Re-run. Repeat until green.

   The first green run is the least-privilege spec.
   --------------------------------------------------------------------- */

/* ---------------------------------------------------------------------
   5. The elevated-operation trap: TRUNCATE
   ---------------------------------------------------------------------
   TRUNCATE TABLE requires ALTER on the table and cannot be granted on
   its own. That single requirement is how pipelines end up in db_owner.

   Run the row counts as yourself: etl_service has INSERT/UPDATE on
   staging but no SELECT, so it cannot read its own staging table.
   --------------------------------------------------------------------- */
SELECT COUNT(*) AS RowsBefore FROM staging.CustomerLoad;   -- 5
GO

EXECUTE AS USER = 'etl_service';
 TRUNCATE TABLE staging.CustomerLoad;   -- expected to fail
REVERT;                                 -- run REVERT manually if it fails
GO

SELECT COUNT(*) AS RowsAfter FROM staging.CustomerLoad;    -- still 5
GO

/* ---------------------------------------------------------------------
   6. Module signing — the procedure carries the right, not the account
   (condensed from SignThoseSprocs!)
   --------------------------------------------------------------------- */

-- 6a. Wrap the elevated operation in a procedure
CREATE PROCEDURE etl.ResetStaging
AS
BEGIN
    TRUNCATE TABLE staging.CustomerLoad;   -- needs ALTER on the table
END;
GO

-- 6b. Create a certificate and sign the procedure
CREATE CERTIFICATE EtlSigningCert
    ENCRYPTION BY PASSWORD = 'StrongDemoPassword!1'
    WITH SUBJECT = 'ETL elevated operations';
GO
ADD SIGNATURE TO etl.ResetStaging
    BY CERTIFICATE EtlSigningCert
    WITH PASSWORD = 'StrongDemoPassword!1';
GO

-- 6c. Map the certificate to a user; grant ALTER to the CERTIFICATE
CREATE USER EtlCertUser FROM CERTIFICATE EtlSigningCert;
GRANT ALTER ON staging.CustomerLoad TO EtlCertUser;
GO

-- 6d. Same account, same operation — now it works
SELECT COUNT(*) AS RowsBefore FROM staging.CustomerLoad;   -- 5
GO

EXECUTE AS USER = 'etl_service';
EXEC etl.ResetStaging;
REVERT;
GO

SELECT COUNT(*) AS RowsAfter FROM staging.CustomerLoad;    -- 0
GO

-- Re-seed so the next section starts from a visible row count
INSERT INTO staging.CustomerLoad (CustomerID)
SELECT CustomerID FROM dbo.Customer;
SELECT COUNT(*) AS ReadyForNextSection FROM staging.CustomerLoad;  -- 5
GO

-- The signature exists
SELECT o.name, cp.crypt_type_desc, c.name AS cert_name
FROM   sys.crypt_properties cp
JOIN   sys.objects o       ON cp.major_id = o.object_id
JOIN   sys.certificates c  ON cp.thumbprint = c.thumbprint;
GO

/* ---------------------------------------------------------------------
   7. ALTER the procedure — the signature drops off
   --------------------------------------------------------------------- */
ALTER PROCEDURE etl.ResetStaging
AS
BEGIN
    TRUNCATE TABLE staging.CustomerLoad;
    -- PRINT 'something sneaky';    -- any change kills the signature
END;
GO

-- No rows: the signature is gone
SELECT o.name, cp.crypt_type_desc
FROM   sys.crypt_properties cp
JOIN   sys.objects o ON cp.major_id = o.object_id;
GO

SELECT COUNT(*) AS RowsBefore FROM staging.CustomerLoad;   -- 5
GO

EXECUTE AS USER = 'etl_service';
 EXEC etl.ResetStaging;                  -- expected to fail
REVERT;                                  -- run REVERT manually if it fails
GO

-- Nothing was truncated. Re-signing is a deploy-step concern.
SELECT COUNT(*) AS RowsAfter FROM staging.CustomerLoad;    -- still 5
GO

/* ---------------------------------------------------------------------
   8. Re-sign to restore
   --------------------------------------------------------------------- */
ADD SIGNATURE TO etl.ResetStaging
    BY CERTIFICATE EtlSigningCert
    WITH PASSWORD = 'StrongDemoPassword!1';
GO

EXECUTE AS USER = 'etl_service';
EXEC etl.ResetStaging;
REVERT;
GO

SELECT COUNT(*) AS RowsAfter FROM staging.CustomerLoad;    -- 0
GO
