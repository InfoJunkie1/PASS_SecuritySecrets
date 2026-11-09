"""
03b_faker_synthetic.py — Demo 3  ·  Secret #3: Synthetic data

Generate fake-but-realistic data instead of copying production, and make
generating it a step in the refresh job rather than a manual favor.

    pip install faker pandas sqlalchemy pyodbc
"""

import os
from urllib.parse import quote_plus

import pandas as pd
from faker import Faker
from sqlalchemy import create_engine

fake = Faker()
Faker.seed(2026)                      # reproducible: same dataset every run,
                                      # so CI diffs are stable

n = 10_000
customers = pd.DataFrame(
    {
        "CustomerID":  range(1, n + 1),
        "Name":        [fake.name() for _ in range(n)],
        "Email":       [fake.email() for _ in range(n)],
        "SSN":         [fake.ssn() for _ in range(n)],
        "CreditLimit": [fake.random_int(500, 50_000) for _ in range(n)],
    }
)

print(customers.head())               # visibly fake, correctly shaped

# ---------------------------------------------------------------------
# Verified output (seed 2026) — reproduced on Python 3.11 and 3.13
# ---------------------------------------------------------------------
#  CustomerID          Name                        Email         SSN  CreditLimit
#           1 Jonathan Hunt    rodriguezlisa@example.com ***-**-****        36836
#           2 Ashley Walker       briggsgina@example.net ***-**-****        33166
#           3 Kristie Logan          jason45@example.com ***-**-****         8131
#           4   Monica Tate             gkey@example.net ***-**-****        28381
#           5  Laurie Allen sharpchristopher@example.net ***-**-****        33684
#
# The SSN column is masked in this comment on purpose. Faker emits real
# ###-##-#### format, realistic enough that a data-loss scanner flags a
# file containing them. Running the script shows the full synthetic values.
# ---------------------------------------------------------------------

# ---------------------------------------------------------------------
# Load into dev as a pipeline step — the last step of the dev refresh.
# Connection string comes from env or vault; see 02_secrets.py.
#
# SERVER must name the instance where 00_setup.sql was run. Set the
# DEMO_SQL_SERVER env var to your instance (e.g. MYHOST\SQL2022);
# it defaults to localhost. Named instances need the SQL Browser
# service running.
#
# The whole ODBC string is URL-encoded into odbc_connect rather than
# built as mssql+pyodbc://server/db — SQLAlchemy does not decode the
# host portion of the URL, so a backslash encoded there reaches the
# driver as a literal %5C and the instance is never found.
# ---------------------------------------------------------------------
SERVER = os.environ.get("DEMO_SQL_SERVER", "localhost")
DATABASE = "SecuritySecrets"

odbc_str = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    f"SERVER={SERVER};DATABASE={DATABASE};"
    "Trusted_Connection=yes;"
    "Encrypt=yes;TrustServerCertificate=yes"   # local dev instance only
)
dev_engine = create_engine(
    "mssql+pyodbc:///?odbc_connect=" + quote_plus(odbc_str)
)

try:
    customers.to_sql(
        "CustomerSynthetic", dev_engine, schema="dbo",
        if_exists="replace", index=False,
    )
    print(f"Loaded {n} synthetic customers into {SERVER}.{DATABASE}.")
except Exception as exc:
    # Generating the data is the point of the demo; the insert is
    # optional. Don't let a connection problem hide the output.
    print(f"Could not write to {SERVER}.{DATABASE}: {exc}")
    print("The DataFrame above is the demo. Check the instance name and "
          "that 00_setup.sql ran there.")

# Fabric equivalent: same generation step, write the DataFrame to a Delta
# table in the dev lakehouse. Only the sink changes.
