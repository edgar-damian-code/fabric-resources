"""
generate_base_models.py

Generates dbt staging model SQL files from a source YAML file produced
by generate_source.py. Reads the source YAML directly — no dbt subprocess needed.

Each generated model follows the standard dbt staging pattern:
    - source CTE selects all columns from the source table
    - renamed CTE aliases columns explicitly
    - final SELECT from renamed

Usage:
    # Generate all tables for a source
    python scripts/generate_base_models.py qad_us

    # Generate specific tables only
    python scripts/generate_base_models.py qad_us -t ac_mstr ap_vendor

    # Strip a prefix from the output filename
    python scripts/generate_base_models.py qad_us --remove qad_us__

    # Split on a delimiter and take the second part for the filename
    python scripts/generate_base_models.py qad_us --split __

    # Append a suffix to the output filename
    python scripts/generate_base_models.py qad_us --suffix _v2

    # Overwrite existing model files (default is to skip)
    python scripts/generate_base_models.py qad_us --overwrite
"""

import os
import sys
import argparse
import textwrap
from typing import Optional

import yaml


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def find_source_yaml(source_name: str) -> Optional[str]:
    """
    Walks models/staging/ looking for _source_<source_name>.yml.

    Automatic discovery means callers don't need to know the exact path —
    the convention from generate_source.py is enough to find it:
    models/staging/<source>/_source_<source>.yml
    """
    expected_filename = f"_source_{source_name}.yml"

    for root, dirs, files in os.walk(os.path.join("models", "staging")):
        if expected_filename in files:
            return os.path.join(root, expected_filename)

    return None


# ---------------------------------------------------------------------------
# File naming
# ---------------------------------------------------------------------------

def derive_model_name(
    table_name: str,
    split_str: Optional[str],
    remove_str: Optional[str],
    suffix: str,
) -> str:
    """
    Derives the output model name from the source table name.

    Transformations are applied in order:
    1. split_str  — splits on a delimiter and takes the second part.
                    e.g. 'qad_us__ac_mstr' -> 'ac_mstr'
    2. remove_str — removes a substring from the table name.
                    e.g. 'qad_us__ac_mstr' -> 'ac_mstr'
    3. suffix     — appends a string to the end of the derived name.

    split_str and remove_str are mutually exclusive. If neither is provided
    the table name is used as-is.
    """
    name = table_name

    if split_str:
        parts = name.split(split_str)
        if len(parts) > 1:
            name = parts[1]
        else:
            print(
                f"  Warning: split delimiter '{split_str}' not found in '{table_name}', "
                "using full table name."
            )
    elif remove_str:
        name = name.replace(remove_str, "")

    if suffix:
        name += suffix

    return name


# ---------------------------------------------------------------------------
# SQL generation
# ---------------------------------------------------------------------------

def generate_staging_sql(source_name: str, table_name: str, columns: list[dict]) -> str:
    """
    Generates a dbt staging model SQL file from source metadata.

    Generates directly from the source YAML rather than calling
    dbt codegen.generate_base_model — no dbt subprocess dependency,
    consistent output regardless of codegen version.

    Column names are lowercased to match Fabric Warehouse's case-insensitive
    identifier convention and dbt best practices. Each column gets its own
    line for clean diffs in version control.
    """
    col_indent = "        "  # 8 spaces — aligns under 'select'
    column_lines = []
    for i, col in enumerate(columns):
        col_name = col["name"].lower()
        if i < len(columns) - 1:
            column_lines.append(f"{col_indent}{col_name},")
        else:
            column_lines.append(f"{col_indent}{col_name}")

    columns_str = "\n".join(column_lines)

    return (
        f"with source as (\n"
        f"\n"
        f"    select * from {{{{ source('{source_name}', '{table_name}') }}}}\n"
        f"\n"
        f"),\n"
        f"\n"
        f"renamed as (\n"
        f"\n"
        f"    select\n"
        f"{columns_str}\n"
        f"    from source\n"
        f"\n"
        f")\n"
        f"\n"
        f"select * from renamed\n"
    )


# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------

def generate_base_models(args: argparse.Namespace) -> None:
    source_name = args.source_name

    # --- Locate source YAML ---
    yaml_path = find_source_yaml(source_name)
    if not yaml_path:
        print(
            f"Error: Could not find _source_{source_name}.yml under models/staging/. "
            "Run generate_source.py first.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"Found source YAML at: {yaml_path}")

    # --- Parse source YAML ---
    with open(yaml_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    try:
        source = data["sources"][0]
        all_tables = source["tables"]
    except (KeyError, IndexError):
        print(
            f"Error: Could not parse source YAML at {yaml_path}. "
            "Expected 'sources[0].tables' structure.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Build a lookup of table name -> columns
    table_lookup: dict[str, list[dict]] = {
        table["name"]: table.get("columns", [])
        for table in all_tables
    }

    # --- Filter to specified tables if provided ---
    if args.table_names:
        missing = [t for t in args.table_names if t not in table_lookup]
        if missing:
            print(
                f"Error: The following specified tables were not found in the source YAML: "
                f"{', '.join(missing)}\n"
                f"Available tables: {', '.join(sorted(table_lookup.keys()))}",
                file=sys.stderr,
            )
            sys.exit(1)
        tables_to_generate = {t: table_lookup[t] for t in args.table_names}
    else:
        tables_to_generate = table_lookup

    total = len(tables_to_generate)
    output_dir = os.path.dirname(yaml_path)

    # --- Generate a model for each table ---
    generated = []
    skipped = []

    for i, (table_name, columns) in enumerate(tables_to_generate.items(), start=1):
        print(f"  ({i}/{total}) {table_name}")

        if not columns:
            print(
                f"  Warning: No columns found for '{table_name}' in source YAML. "
                "Skipping.",
                file=sys.stderr,
            )
            continue

        model_name = derive_model_name(
            table_name,
            split_str=args.split,
            remove_str=args.remove,
            suffix=args.suffix,
        )

        output_filename = f"stg_{source_name}__{model_name}.sql"
        output_path = os.path.join(output_dir, output_filename)

        if os.path.exists(output_path) and not args.overwrite:
            print(f"  Skipping {output_filename} (already exists, use --overwrite to replace)")
            skipped.append(output_filename)
            continue

        sql = generate_staging_sql(source_name, table_name, columns)

        with open(output_path, "w", encoding="utf-8") as f:
            f.write(sql)

        generated.append(output_filename)

    # --- Summary ---
    print(
        f"\nDone. Created: {len(generated)}, Skipped: {len(skipped)}\n"
        f"Output directory: {output_dir}/"
    )
    for filename in generated:
        print(f"  {filename}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=textwrap.dedent("""
            Generate dbt staging model SQL files from a source YAML file.

            Reads the _source_<source_name>.yml file produced by generate_source.py
            and generates one stg_<source>__<table>.sql file per table.

            The source YAML is automatically discovered under models/staging/.
            Run this script from your dbt project root.
        """),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "source_name",
        type=str,
        help="Name of the source system (e.g. 'qad_us'). Must match the source YAML filename.",
    )
    parser.add_argument(
        "-t", "--table-names",
        nargs="*",
        default=[],
        help="Specific table(s) to generate models for. Omit to generate all tables.",
    )
    parser.add_argument(
        "--remove",
        type=str,
        default=None,
        help=(
            "Remove a substring from the table name when deriving the output filename. "
            "e.g. --remove 'qad_us__' turns 'qad_us__ac_mstr' into 'stg_qad_us__ac_mstr.sql'"
        ),
    )
    parser.add_argument(
        "--split",
        type=str,
        default=None,
        const="__",
        nargs="?",
        help=(
            "Split the table name on a delimiter and use the second part for the filename. "
            "Defaults to '__' if flag is provided without a value. "
            "e.g. --split '__' turns 'qad_us__ac_mstr' into 'stg_qad_us__ac_mstr.sql'"
        ),
    )
    parser.add_argument(
        "--suffix",
        type=str,
        default="",
        help="Optional suffix to append to the model name in the output filename.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing model files. Default is to skip existing files.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    generate_base_models(args)
