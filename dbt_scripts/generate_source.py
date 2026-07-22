"""
generate_source.py

Generates a dbt source YAML file by querying a Microsoft Fabric Warehouse's
information_schema directly via pyodbc.

Reads connection details (server, service principal auth) from ~/.dbt/profiles.yml.
The --database parameter controls WHICH database in the Fabric workspace is queried —
this is independent of the profile's write target (Gold_EDW).

Usage:
    # Generate source from landing_data_engineering
    python scripts/generate_source.py -d landing -s dbo -n qad_us

    # Generate source with a table prefix filter
    python scripts/generate_source.py -d landing -s dbo -n qad_us -p qad_us__

    # Use a specific dbt profile and target
    python scripts/generate_source.py -d gold -s dbo -n my_source --profile my_profile --target prod

Authentication:
    Reads from ~/.dbt/profiles.yml using the dbt-fabric adapter format:
        type: fabric
        driver: "ODBC Driver 18 for SQL Server"
        server: <workspace>.datawarehouse.fabric.microsoft.com
        authentication: ServicePrincipal
        tenant_id: <tenant-id>
        client_id: <client-id>
        client_secret: <client-secret>
"""

import os
import sys
import argparse
import textwrap
from typing import Optional

import pyodbc
import yaml


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Default dbt profile to use from ~/.dbt/profiles.yml.
# Set this to your Fabric profile name so you don't need to pass --profile
# on every invocation. Can still be overridden via --profile on the CLI.
DEFAULT_PROFILE = "wia_fabric_dev"  # <-- update this to your profile name

# Map shorthand aliases to canonical Fabric database names.
# These are the databases (warehouses/lakehouses) available in your workspace.
# The key is what you type on the CLI; the value is the exact database name in Fabric.
DATABASE_ALIASES: dict[str, str] = {
    "gold":                        "gold_edw",
    "gold_edw":                    "gold_edw",
    "landing":                     "landing_lh__data_engineering",
    "landing_de":                  "landing_lh__data_engineering",
    "landing_lh__data_engineering": "landing_lh__data_engineering",
    "staging":                     "staging_lh__data_engineering",
    "staging_lh":                  "staging_lh__data_engineering",
    "staging_lh__data_engineering": "staging_lh__data_engineering",
}


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def validate_database(value: str) -> str:
    """
    Resolves a CLI shorthand alias to the canonical Fabric database name.

    Keeping alias resolution here means argparse surfaces a clean error
    message immediately if an invalid value is passed, before any connection
    is attempted.
    """
    resolved = DATABASE_ALIASES.get(value.lower())
    if resolved is None:
        valid = ", ".join(sorted(DATABASE_ALIASES.keys()))
        raise argparse.ArgumentTypeError(
            f"Invalid database '{value}'. Valid options: {valid}"
        )
    return resolved


# ---------------------------------------------------------------------------
# Profile reading
# ---------------------------------------------------------------------------

def read_fabric_profile(
    profile_name: Optional[str] = None,
    target: Optional[str] = None,
) -> dict:
    """
    Reads a dbt-fabric profile output from ~/.dbt/profiles.yml.

    Returns the raw output dict so the caller can extract the fields it needs.

    Why read the profile directly instead of relying on dbt:
    - This script runs outside of dbt — no dbt process dependency
    - We only need 4-5 fields from the profile; no need for full dbt parsing
    - Direct reading is faster and more explicit about what's being used

    Expected profile structure (dbt-fabric adapter):
        my_profile:
          target: dev
          outputs:
            dev:
              type: fabric
              driver: "ODBC Driver 18 for SQL Server"
              server: <workspace-id>.datawarehouse.fabric.microsoft.com
              port: 1433
              database: Gold_EDW
              schema: dbo
              authentication: ServicePrincipal
              tenant_id: <tenant-id>
              client_id: <client-id>
              client_secret: <client-secret>
              threads: 4
    """
    profiles_path = os.path.join(os.path.expanduser("~"), ".dbt", "profiles.yml")

    if not os.path.exists(profiles_path):
        raise FileNotFoundError(
            f"profiles.yml not found at {profiles_path}. "
            "Ensure dbt is configured before running this script."
        )

    with open(profiles_path, "r") as f:
        profiles = yaml.safe_load(f)

    # Fall back to DEFAULT_PROFILE if none specified on the CLI
    if profile_name is None:
        profile_name = DEFAULT_PROFILE
        print(f"No profile specified, using default '{profile_name}'")

    profile = profiles.get(profile_name)
    if not profile:
        available = ", ".join(profiles.keys())
        raise ValueError(
            f"Profile '{profile_name}' not found in profiles.yml. "
            f"Available profiles: {available}"
        )

    # Use the profile's default target if none specified
    resolved_target = target or profile.get("target")
    print(f"Using target '{resolved_target}'")

    output = profile.get("outputs", {}).get(resolved_target)
    if not output:
        available = ", ".join(profile.get("outputs", {}).keys())
        raise ValueError(
            f"Target '{resolved_target}' not found in profile '{profile_name}'. "
            f"Available targets: {available}"
        )

    if output.get("type") != "fabric":
        raise ValueError(
            f"Profile '{profile_name}' target '{resolved_target}' is not a Fabric connection "
            f"(found type: '{output.get('type')}'). This script requires the dbt-fabric adapter."
        )

    return output


# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------

def build_connection_string(profile_output: dict, database: str) -> str:
    """
    Builds a pyodbc connection string for Fabric Warehouse using service principal auth.

    The database in the connection string is set to the TARGET database we want to
    query (passed via --database), NOT the profile's write target. This allows
    querying information_schema in any warehouse in the workspace while leaving
    the profile itself unchanged.

    Service principal auth format for ODBC Driver 18:
        UID  = <client_id>@<tenant_id>
        PWD  = <client_secret>
        Authentication = ActiveDirectoryServicePrincipal

    Encrypt and TrustServerCertificate are required for Fabric endpoints.
    """
    server   = profile_output.get("server") or profile_output["host"]
    driver   = profile_output.get("driver", "ODBC Driver 18 for SQL Server")
    tenant   = profile_output["tenant_id"]
    client   = profile_output["client_id"]
    secret   = profile_output["client_secret"]
    port     = profile_output.get("port", 1433)

    return (
        f"Driver={{{driver}}};"
        f"Server={server},{port};"
        f"Database={database};"
        f"Authentication=ActiveDirectoryServicePrincipal;"
        f"UID={client}@{tenant};"
        f"PWD={secret};"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )


def get_connection(profile_output: dict, database: str) -> pyodbc.Connection:
    """
    Opens a pyodbc connection to the specified Fabric Warehouse database.

    Separating connection building from connection opening makes it easy to
    test the connection string logic without needing a live Fabric endpoint.
    """
    conn_str = build_connection_string(profile_output, database)
    try:
        return pyodbc.connect(conn_str)
    except pyodbc.Error as e:
        raise ConnectionError(
            f"Failed to connect to Fabric Warehouse '{database}': {e}\n"
            "Check that your service principal credentials in profiles.yml are correct "
            "and that the service principal has access to this warehouse."
        ) from e


# ---------------------------------------------------------------------------
# Schema discovery
# ---------------------------------------------------------------------------

def fetch_tables(
    conn: pyodbc.Connection,
    database: str,
    schema: str,
    prefix: Optional[str] = None,
) -> dict[str, list[dict]]:
    """
    Queries information_schema.columns in the target Fabric database to discover
    tables and their columns.

    Returns a dict keyed by table name, where each value is an ordered list of
    column dicts: [{"name": "column_name"}, ...]

    Why information_schema directly:
    - No dbt subprocess or codegen macro dependency
    - Full control over filtering — the prefix filter uses LIKE with proper
      T-SQL escaping (underscore is a wildcard in LIKE, so we escape it)
    - Parameterised query prevents injection
    - Consistent results regardless of dbt or codegen version

    T-SQL note: INFORMATION_SCHEMA.COLUMNS is available in Fabric Warehouse
    and behaves identically to SQL Server. Column names and table names are
    returned in their stored case — we lowercase them for dbt conventions.
    """
    # Escape underscores in the prefix so they're treated as literals in LIKE,
    # not single-character wildcards. This matters for prefixes like 'qad_us__'.
    if prefix:
        escaped_prefix = prefix.replace("_", "[_]")
        pattern = f"{escaped_prefix}%"
    else:
        pattern = "%"

    query = """
        SELECT
            TABLE_NAME,
            COLUMN_NAME,
            ORDINAL_POSITION
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_CATALOG = ?
          AND TABLE_SCHEMA  = ?
          AND TABLE_NAME    LIKE ?
        ORDER BY
            TABLE_NAME,
            ORDINAL_POSITION
    """

    cursor = conn.cursor()
    cursor.execute(query, (database, schema, pattern))
    rows = cursor.fetchall()
    cursor.close()

    if not rows:
        raise ValueError(
            f"No tables found in [{database}].[{schema}] matching pattern '{pattern}'. "
            "Check your --database, --schema, and --prefix values."
        )

    # Group columns by table, preserving ordinal order (already sorted by query)
    tables: dict[str, list[dict]] = {}
    for row in rows:
        table = row.TABLE_NAME.lower()
        if table not in tables:
            tables[table] = []
        tables[table].append({"name": row.COLUMN_NAME.lower()})

    return tables


# ---------------------------------------------------------------------------
# YAML generation
# ---------------------------------------------------------------------------

def build_source_yaml(
    source_name: str,
    database: str,
    schema: str,
    tables: dict[str, list[dict]],
) -> dict:
    """
    Constructs the dbt source YAML structure as a Python dict.

    Building as a dict (rather than string templating) means PyYAML handles
    all escaping and formatting consistently. It also makes the output easy
    to unit test — just assert on the dict structure.

    The output matches the dbt source YAML spec:
    https://docs.getdbt.com/reference/source-properties

    Note on database casing: we store the canonical name (e.g. 'Gold_EDW')
    as resolved by validate_database(), matching what Fabric expects.
    """
    return {
        "version": 2,
        "sources": [
            {
                "name": source_name,
                "database": database,
                "schema": schema,
                "tables": [
                    {
                        "name": table_name,
                        "columns": [{"name": col["name"]} for col in columns],
                    }
                    for table_name, columns in sorted(tables.items())
                ],
            }
        ],
    }


def write_yaml(data: dict, output_path: str) -> None:
    """
    Writes the source YAML dict to a file.

    PyYAML settings:
    - default_flow_style=False  → block style (readable, diffs well in git)
    - allow_unicode=True        → preserve any unicode in identifiers
    - sort_keys=False           → respect our key ordering (version first, name before columns)
    """
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        yaml.dump(
            data,
            f,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
        )


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

def generate_source(args: argparse.Namespace) -> None:
    prefix_text = f" with prefix '{args.prefix}%'" if args.prefix else ""
    print(f"Discovering tables in [{args.database}].[{args.schema}]{prefix_text}...")

    # --- Read profile ---
    try:
        profile_output = read_fabric_profile(
            profile_name=args.profile,
            target=args.target,
        )
    except (FileNotFoundError, ValueError) as e:
        print(f"Profile error: {e}", file=sys.stderr)
        sys.exit(1)

    # --- Connect and discover ---
    try:
        conn = get_connection(profile_output, args.database)
    except ConnectionError as e:
        print(f"Connection error: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        tables = fetch_tables(conn, args.database, args.schema, args.prefix)
    except ValueError as e:
        print(f"Discovery error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        conn.close()

    print(f"Found {len(tables)} table(s): {', '.join(sorted(tables.keys()))}")

    # --- Build and write YAML ---
    source_yaml = build_source_yaml(
        source_name=args.source,
        database=args.database,
        schema=args.schema,
        tables=tables,
    )

    output_path = os.path.join(
        "models", "staging", args.source, f"_source_{args.source}.yml"
    )
    write_yaml(source_yaml, output_path)

    print(f"Successfully wrote source YAML to {output_path}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=textwrap.dedent("""
            Generate a dbt source YAML file by discovering tables in a Fabric Warehouse.

            Reads connection details from ~/.dbt/profiles.yml (dbt-fabric adapter).
            The --database parameter controls which warehouse/database in the Fabric
            workspace is queried — independent of the profile's write target.

            Run this script from your dbt project root.
        """),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-d", "--database",
        type=validate_database,
        required=True,
        help=(
            "Fabric database (warehouse) to query. "
            f"Valid aliases: {', '.join(sorted(DATABASE_ALIASES.keys()))}. "
            "This controls which database information_schema is queried against, "
            "not the dbt write target."
        ),
    )
    parser.add_argument(
        "-s", "--schema",
        type=str,
        required=True,
        help="Schema within the Fabric database containing the source tables (e.g. 'dbo').",
    )
    parser.add_argument(
        "-n", "--source",
        type=str,
        required=True,
        help=(
            "Short name for the source system (e.g. 'qad_us'). "
            "Used as the dbt source name and determines the output folder: "
            "models/staging/<source>/_source_<source>.yml"
        ),
    )
    parser.add_argument(
        "-p", "--prefix",
        type=str,
        default="",
        help=(
            "Optional table name prefix filter. "
            "e.g. --prefix 'qad_us__' matches only tables starting with 'qad_us__'. "
            "Underscores in the prefix are treated as literals, not LIKE wildcards."
        ),
    )
    parser.add_argument(
        "--profile",
        type=str,
        default=None,
        help=(
            "dbt profile name from profiles.yml. "
            "Defaults to DEFAULT_PROFILE."
        ),
    )
    parser.add_argument(
        "--target",
        type=str,
        default=None,
        help=(
            "dbt target within the profile (e.g. 'dev', 'prod'). "
            "Defaults to the profile's configured default target."
        ),
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    generate_source(args)