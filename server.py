"""
SQL Server MCP Server
A Model Context Protocol server for connecting Claude to a local SQL Server instance.
"""

import os
import json
import logging
import pymssql
from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sqlserver-mcp")

# Initialize MCP server
mcp = FastMCP("SQL Server MCP")

# ──────────────────────────────────────────────
# Database Connection Helper
# ──────────────────────────────────────────────

def get_connection():
    """Create and return a database connection."""
    return pymssql.connect(
        server=os.getenv("DB_SERVER", "localhost"),
        port=os.getenv("DB_PORT", "1433"),
        user=os.getenv("DB_USER", "sa"),
        password=os.getenv("DB_PASSWORD", ""),
        database=os.getenv("DB_NAME", "master"),
        charset="UTF-8"
    )


def run_query(query: str, params: tuple = None, fetch: bool = True):
    """Execute a query and return results."""
    conn = get_connection()
    try:
        cursor = conn.cursor(as_dict=True)
        cursor.execute(query, params)
        if fetch:
            results = cursor.fetchall()
            return results
        else:
            conn.commit()
            return {"affected_rows": cursor.rowcount}
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()


# ──────────────────────────────────────────────
# MCP Tools
# ──────────────────────────────────────────────

@mcp.tool()
def test_connection() -> str:
    """Test the SQL Server database connection."""
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT @@VERSION AS version")
        row = cursor.fetchone()
        conn.close()
        return json.dumps({
            "status": "connected",
            "version": row[0]
        }, indent=2)
    except Exception as e:
        return json.dumps({
            "status": "error",
            "message": str(e)
        }, indent=2)


@mcp.tool()
def list_databases() -> str:
    """List all databases on the SQL Server instance."""
    try:
        results = run_query(
            "SELECT name, state_desc, create_date FROM sys.databases ORDER BY name"
        )
        for r in results:
            if r.get("create_date"):
                r["create_date"] = str(r["create_date"])
        return json.dumps(results, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def list_tables(schema: str = "dbo") -> str:
    """List all tables in the current database, optionally filtered by schema."""
    try:
        results = run_query(
            """
            SELECT 
                TABLE_SCHEMA, 
                TABLE_NAME, 
                TABLE_TYPE
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = %s
            ORDER BY TABLE_SCHEMA, TABLE_NAME
            """,
            (schema,)
        )
        return json.dumps(results, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def describe_table(table_name: str, schema: str = "dbo") -> str:
    """Get column details for a specific table."""
    try:
        results = run_query(
            """
            SELECT 
                COLUMN_NAME,
                DATA_TYPE,
                CHARACTER_MAXIMUM_LENGTH,
                IS_NULLABLE,
                COLUMN_DEFAULT
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = %s AND TABLE_SCHEMA = %s
            ORDER BY ORDINAL_POSITION
            """,
            (table_name, schema)
        )
        return json.dumps(results, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def run_select_query(query: str) -> str:
    """
    Run a SELECT query against the database. 
    Only SELECT statements are allowed for safety.
    """
    # Safety check: only allow SELECT
    stripped = query.strip().upper()
    if not stripped.startswith("SELECT"):
        return json.dumps({
            "error": "Only SELECT queries are allowed. Use run_modify_query for INSERT/UPDATE/DELETE."
        })
    try:
        results = run_query(query)
        # Convert non-serializable types
        for row in results:
            for key, val in row.items():
                if not isinstance(val, (str, int, float, bool, type(None))):
                    row[key] = str(val)
        return json.dumps({
            "row_count": len(results),
            "data": results
        }, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def run_modify_query(query: str) -> str:
    """
    Run an INSERT, UPDATE, or DELETE query.
    Returns the number of affected rows.
    """
    stripped = query.strip().upper()
    if stripped.startswith("SELECT"):
        return json.dumps({
            "error": "Use run_select_query for SELECT statements."
        })
    # Block dangerous operations
    if stripped.startswith("DROP") or stripped.startswith("TRUNCATE"):
        return json.dumps({
            "error": "DROP and TRUNCATE operations are blocked for safety."
        })
    try:
        result = run_query(query, fetch=False)
        return json.dumps(result, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_table_indexes(table_name: str, schema: str = "dbo") -> str:
    """Get all indexes for a specific table."""
    try:
        results = run_query(
            """
            SELECT 
                i.name AS index_name,
                i.type_desc AS index_type,
                i.is_unique,
                i.is_primary_key,
                STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS columns
            FROM sys.indexes i
            INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE i.object_id = OBJECT_ID(%s)
            GROUP BY i.name, i.type_desc, i.is_unique, i.is_primary_key
            ORDER BY i.name
            """,
            (f"{schema}.{table_name}",)
        )
        return json.dumps(results, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_row_count(table_name: str, schema: str = "dbo") -> str:
    """Get the row count for a specific table."""
    try:
        results = run_query(
            f"SELECT COUNT(*) AS row_count FROM [{schema}].[{table_name}]"
        )
        return json.dumps(results[0], indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_stored_procedures(schema: str = "dbo") -> str:
    """List all stored procedures in the current database."""
    try:
        results = run_query(
            """
            SELECT 
                ROUTINE_NAME,
                ROUTINE_TYPE,
                CREATED,
                LAST_ALTERED
            FROM INFORMATION_SCHEMA.ROUTINES
            WHERE ROUTINE_SCHEMA = %s AND ROUTINE_TYPE = 'PROCEDURE'
            ORDER BY ROUTINE_NAME
            """,
            (schema,)
        )
        for r in results:
            for key in ["CREATED", "LAST_ALTERED"]:
                if r.get(key):
                    r[key] = str(r[key])
        return json.dumps(results, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def get_table_relationships(table_name: str, schema: str = "dbo") -> str:
    """Get foreign key relationships for a specific table."""
    try:
        results = run_query(
            """
            SELECT 
                fk.name AS fk_name,
                tp.name AS parent_table,
                cp.name AS parent_column,
                tr.name AS referenced_table,
                cr.name AS referenced_column
            FROM sys.foreign_keys fk
            INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
            INNER JOIN sys.tables tp ON fkc.parent_object_id = tp.object_id
            INNER JOIN sys.columns cp ON fkc.parent_object_id = cp.object_id AND fkc.parent_column_id = cp.column_id
            INNER JOIN sys.tables tr ON fkc.referenced_object_id = tr.object_id
            INNER JOIN sys.columns cr ON fkc.referenced_object_id = cr.object_id AND fkc.referenced_column_id = cr.column_id
            WHERE tp.name = %s OR tr.name = %s
            ORDER BY fk.name
            """,
            (table_name, table_name)
        )
        return json.dumps(results, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


# ──────────────────────────────────────────────
# MCP Resources (read-only context for Claude)
# ──────────────────────────────────────────────

@mcp.resource("sqlserver://info")
def get_server_info() -> str:
    """Provide SQL Server instance information as context."""
    try:
        results = run_query(
            """
            SELECT 
                SERVERPROPERTY('MachineName') AS machine,
                SERVERPROPERTY('ServerName') AS server_name,
                SERVERPROPERTY('Edition') AS edition,
                SERVERPROPERTY('ProductVersion') AS version,
                DB_NAME() AS current_database
            """
        )
        for row in results:
            for key, val in row.items():
                if not isinstance(val, (str, int, float, bool, type(None))):
                    row[key] = str(val)
        return json.dumps(results[0], indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


# ──────────────────────────────────────────────
# Run Server
# ──────────────────────────────────────────────

if __name__ == "__main__":
    logger.info("Starting SQL Server MCP Server...")
    mcp.run(transport="stdio")
