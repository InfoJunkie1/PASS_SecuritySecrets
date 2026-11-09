"""
02b_databricks_secrets.py — Demo 2  ·  Databricks secret scopes

Run in a Databricks notebook. Create the Key Vault-backed scope once:

    databricks secrets create-scope etl-secrets \
        --scope-backend-type AZURE_KEYVAULT \
        --resource-id /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<your-key-vault> \
        --dns-name https://<your-key-vault>.vault.azure.net/
"""

# The platform refuses to print a secret retrieved from a scope, even
# when the notebook asks it to.
pwd = dbutils.secrets.get(scope="etl-secrets", key="sales-etl-password")
print(pwd)          # [REDACTED]

jdbc_url = (
    "jdbc:sqlserver://prod-sql01:1433;database=Sales;"
    "encrypt=true;trustServerCertificate=false"
)

df = (
    spark.read.format("jdbc")
    .option("url", jdbc_url)
    .option("dbtable", "src.Orders")
    .option("user", "etl_service")
    .option("password", pwd)          # used, never displayed
    .load()
)
display(df.limit(5))
