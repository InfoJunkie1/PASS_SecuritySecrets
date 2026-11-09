/* =====================================================================
   00_setup.sql — Demo environment for PASS 2026
   "Mom/Daughter Duo: DBA Teaches Data Engineer Security Secrets Worth Stealing"

   Database: SecuritySecrets
   Re-runnable: every object is created only if it isn't already there,
   and seed data is only inserted when the table is empty. Safe to run
   again at any time.
   ===================================================================== */

/* ---- Database ---- */
IF DB_ID('SecuritySecrets') IS NULL
    EXEC ('CREATE DATABASE SecuritySecrets;');
GO

USE SecuritySecrets;
GO

/* ---- Schemas ---- */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'src')
    EXEC ('CREATE SCHEMA src;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
    EXEC ('CREATE SCHEMA staging;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'etl')
    EXEC ('CREATE SCHEMA etl;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'audit')
    EXEC ('CREATE SCHEMA audit;');
GO

/* ---- Logins/users used in demos (demo passwords — never for prod) ---- */
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'etl_service')
    CREATE LOGIN etl_service  WITH PASSWORD = 'DemoOnly!NotForProd1';
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'analyst_demo')
    CREATE LOGIN analyst_demo WITH PASSWORD = 'DemoOnly!NotForProd2';
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'dev_jordan')
    CREATE LOGIN dev_jordan   WITH PASSWORD = 'DemoOnly!NotForProd3';
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'etl_service')
    CREATE USER etl_service  FOR LOGIN etl_service;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'analyst_demo')
    CREATE USER analyst_demo FOR LOGIN analyst_demo;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'dev_jordan')
    CREATE USER dev_jordan   FOR LOGIN dev_jordan;
GO

/* ---- Demo tables ---- */
IF OBJECT_ID('dbo.Customer', 'U') IS NULL
CREATE TABLE dbo.Customer (
    CustomerID  int IDENTITY PRIMARY KEY,
    LastName    nvarchar(50),
    Email       nvarchar(100),
    Phone       varchar(20),
    SSN         char(9),
    CreditLimit money
);
GO

IF OBJECT_ID('staging.CustomerLoad', 'U') IS NULL
CREATE TABLE staging.CustomerLoad (
    CustomerID  int,
    LoadedOn    datetime2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('src.Orders', 'U') IS NULL
CREATE TABLE src.Orders (
    OrderID     int IDENTITY PRIMARY KEY,
    CustomerID  int,
    OrderTotal  money
);
GO

/* ---- The table that proves scoping works (Demo 1) ----
   dbo.Payroll is the table the pipeline has NO business reading.
   It lives in dbo on purpose: the pipeline's grants are on src,
   staging and etl, so nothing it has touches this table.
   The "SELECT permission denied" on this table is the proof. */
IF OBJECT_ID('dbo.Payroll', 'U') IS NULL
CREATE TABLE dbo.Payroll (
    EmployeeID  int IDENTITY PRIMARY KEY,
    LastName    nvarchar(50),
    Title       nvarchar(60),
    AnnualSalary money,
    BonusPct    decimal(5,2)
);
GO

/* ---- Grants (GRANT is idempotent; re-running just re-asserts it) ---- */
GRANT SELECT ON dbo.Customer TO analyst_demo;   -- for the masking demo (03)
GO
-- Deliberately NO grants on dbo.Payroll to anyone. Leave it that way.

/* ---- Seed visibly fake customers (only if the table is empty) ---- */
IF NOT EXISTS (SELECT 1 FROM dbo.Customer)
INSERT INTO dbo.Customer (LastName, Email, Phone, SSN, CreditLimit)
VALUES ('Smith',  'smith@contoso.com',  '314-555-0101', '123456789', 5000),
       ('Jones',  'jones@contoso.com',  '314-555-0102', '234567891', 7500),
       ('Nguyen', 'nguyen@contoso.com', '314-555-0103', '345678912', 12000),
       ('Garcia', 'garcia@contoso.com', '314-555-0104', '456789123', 3000),
       ('Okafor', 'okafor@contoso.com', '314-555-0105', '567891234', 20000);
GO

IF NOT EXISTS (SELECT 1 FROM staging.CustomerLoad)
INSERT INTO staging.CustomerLoad (CustomerID)
SELECT CustomerID FROM dbo.Customer;
GO

/* ---- Seed src.Orders so the "its job works" half of the proof
        actually returns rows ---- */
IF NOT EXISTS (SELECT 1 FROM src.Orders)
INSERT INTO src.Orders (CustomerID, OrderTotal)
VALUES (1, 249.99), (2, 1875.00), (3,  42.50),
       (4, 610.25), (5, 3200.00);
GO

/* ---- Seed dbo.Payroll (visibly fake salaries — it only has to LOOK
        like the table nobody wants leaked) ---- */
IF NOT EXISTS (SELECT 1 FROM dbo.Payroll)
INSERT INTO dbo.Payroll (LastName, Title, AnnualSalary, BonusPct)
VALUES ('Smith',  'VP, Operations',      245000, 22.50),
       ('Jones',  'Senior Engineer',     168000, 12.00),
       ('Nguyen', 'Director, Finance',   210000, 18.00),
       ('Garcia', 'Data Engineer',       142000, 10.00),
       ('Okafor', 'Chief Data Officer',  325000, 30.00);
GO

/* ---- Audit objects ---- */
IF OBJECT_ID('audit.PermissionSnapshot', 'U') IS NULL
CREATE TABLE audit.PermissionSnapshot (
    SnapshotDate   date          NOT NULL,
    PrincipalName  sysname       NOT NULL,
    PermissionName nvarchar(128) NOT NULL,
    ObjectName     nvarchar(300) NOT NULL
);
GO

/* ---- Pre-seed "yesterday" so the delta demo (04) works immediately.
        Only seeds if yesterday's snapshot isn't already there, so a
        re-run never overwrites a snapshot the demo relies on. ---- */
IF NOT EXISTS (SELECT 1 FROM audit.PermissionSnapshot
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

PRINT 'SecuritySecrets environment ready.';
