"""
02_secrets.py — Demo 2  ·  Secret #2: The credential escalation ladder

    hardcoded  ->  environment variable  ->  secret vault  ->  managed identity

Each rung removes a whole class of leak. The top rung removes the
secret itself.
"""

import os

import pyodbc

# ---------------------------------------------------------------------
# Stage 0 — hardcoded
# Committed once, it is in git history permanently; deleting the file
# does not remove the commit.
# ---------------------------------------------------------------------
# conn = pyodbc.connect(
#     "DRIVER={ODBC Driver 18 for SQL Server};SERVER=prod-sql01;"
#     "DATABASE=Sales;UID=etl_service;PWD=Summer2026!"
# )

# ---------------------------------------------------------------------
# Stage 1 — environment variable
# Set by the runtime, not by the file. Gets the secret out of source
# control; it is still readable by anything in the process environment.
# ---------------------------------------------------------------------
conn_str = os.environ["SALES_DB_CONN"]
conn = pyodbc.connect(conn_str)

# ---------------------------------------------------------------------
# Stage 2 — secret vault
# Rotate in one place and every pipeline picks it up on its next run.
# The vault also logs who read the secret.
# ---------------------------------------------------------------------
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

kv = SecretClient(
    vault_url="https://<your-key-vault>.vault.azure.net",
    credential=DefaultAzureCredential(),
)
pwd = kv.get_secret("sales-etl-password").value
conn = pyodbc.connect(
    "DRIVER={ODBC Driver 18 for SQL Server};SERVER=prod-sql01;"
    f"DATABASE=Sales;UID=etl_service;PWD={pwd};"
    "Encrypt=yes;TrustServerCertificate=no"
)

# ---------------------------------------------------------------------
# Stage 3 — managed identity
# No password in the connection string at all; the platform proves who
# the pipeline is.
# ---------------------------------------------------------------------
conn = pyodbc.connect(
    "DRIVER={ODBC Driver 18 for SQL Server};SERVER=prod-sql01;"
    "DATABASE=Sales;Authentication=ActiveDirectoryMsi;"
    "Encrypt=yes;TrustServerCertificate=no"
)

# Fabric equivalent: notebookutils.credentials.getSecret(vaultUrl, name)
# against Key Vault; pipeline activities authenticate with a
# workspace-assigned managed identity.
