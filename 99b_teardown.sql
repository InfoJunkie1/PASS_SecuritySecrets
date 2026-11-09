/* =====================================================================
   99b_teardown.sql — Remove the demo environment entirely
   Use this when you are finished with the demos, not between runs
   (for that, use 99_cleanup.sql).

   Drops the SecuritySecrets database and the three demo logins.
   Re-runnable: does nothing if they're already gone.
   ===================================================================== */

USE master;
GO

IF DB_ID('SecuritySecrets') IS NOT NULL
BEGIN
    ALTER DATABASE SecuritySecrets SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SecuritySecrets;
END
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'etl_service')
    DROP LOGIN etl_service;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'analyst_demo')
    DROP LOGIN analyst_demo;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'dev_jordan')
    DROP LOGIN dev_jordan;
GO

PRINT 'SecuritySecrets demo environment removed.';
