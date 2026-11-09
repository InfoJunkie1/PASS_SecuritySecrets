/* =====================================================================
   03_masking.sql — Demo 3  ·  Secret #3: Protecting data in non-prod
   Dynamic data masking, then static masking on refresh.

   Requires  : 00_setup.sql
   Reset     : 99_cleanup.sql
   ===================================================================== */
USE SecuritySecrets;
GO

/* ---------------------------------------------------------------------
   1. Dynamic data masking
   --------------------------------------------------------------------- */
ALTER TABLE dbo.Customer ALTER COLUMN Email
    ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE dbo.Customer ALTER COLUMN SSN
    ADD MASKED WITH (FUNCTION = 'partial(0,"XXX-XX-",4)');
ALTER TABLE dbo.Customer ALTER COLUMN CreditLimit
    ADD MASKED WITH (FUNCTION = 'random(1, 9999)');
GO

-- As ourselves (dbo): unmasked
SELECT TOP 5 Email, SSN, CreditLimit FROM dbo.Customer;

-- As an analyst without UNMASK: masked
EXECUTE AS USER = 'analyst_demo';
SELECT TOP 5 Email, SSN, CreditLimit FROM dbo.Customer;
-- aXXX@XXXX.com | XXX-XX-6789 | 4382
REVERT;
GO

/* ---------------------------------------------------------------------
   2. The limit of DDM: presentation layer only
   ---------------------------------------------------------------------
   The stored value is untouched, so aggregates and predicates still
   answer truthfully. DDM does not stop inference.
   --------------------------------------------------------------------- */
EXECUTE AS USER = 'analyst_demo';
SELECT COUNT(*) FROM dbo.Customer WHERE CreditLimit > 10000;  -- still answers
REVERT;
GO

/* ---------------------------------------------------------------------
   3. Static masking on refresh — the workhorse
   Run as the last step of every dev-refresh job.
   --------------------------------------------------------------------- */
UPDATE dbo.Customer SET
    Email    = CONCAT('user', CustomerID, '@example.com'),
    Phone    = '555-01' + RIGHT('00' + CAST(CustomerID % 100 AS varchar(2)), 2),
    SSN      = RIGHT('000000000' + CAST(ABS(CHECKSUM(NEWID())) AS varchar(10)), 9),
    LastName = CONCAT('Customer', CustomerID);
GO

-- CustomerID drives the fake values, so joins, volumes and skew
-- still behave like prod.
SELECT TOP 5 CustomerID, LastName, Email, Phone, SSN FROM dbo.Customer;
GO

/* ---------------------------------------------------------------------
   4. Optional: Unity Catalog column masks (Databricks)
   One policy applies to every consumer of the table.

CREATE FUNCTION prod.silver.ssn_mask(ssn STRING) RETURNS STRING
    RETURN CASE WHEN is_account_group_member('pii_readers')
                THEN ssn ELSE 'XXX-XX-' || right(ssn, 4) END;

ALTER TABLE prod.silver.customers
    ALTER COLUMN ssn SET MASK prod.silver.ssn_mask;
   --------------------------------------------------------------------- */
