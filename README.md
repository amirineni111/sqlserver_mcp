# SQL Server MCP Server

A Python-based Model Context Protocol (MCP) server that connects Claude to your local SQL Server instance.

## Available Tools

| Tool | Description |
|---|---|
| `test_connection` | Verify database connectivity |
| `list_databases` | List all databases on the instance |
| `list_tables` | List tables in a schema |
| `describe_table` | Get column details for a table |
| `run_select_query` | Run SELECT queries (read-only) |
| `run_modify_query` | Run INSERT/UPDATE/DELETE queries |
| `get_table_indexes` | View indexes on a table |
| `get_row_count` | Get row count for a table |
| `get_stored_procedures` | List stored procedures |
| `get_table_relationships` | View foreign key relationships |

---

## Step-by-Step Setup Guide

### Step 1: Prerequisites

- **Python 3.10+** installed → [python.org](https://www.python.org/downloads/)
- **SQL Server** running locally (Express, Developer, or full edition)
- **TCP/IP enabled** on SQL Server (see Troubleshooting below)

### Step 2: Clone / Copy Project

Place the project folder on your Desktop (or wherever you prefer):

```
C:\Users\sreea\OneDrive\Desktop\sqlserver_mcp\
├── server.py
├── requirements.txt
├── .env.example
└── README.md
```

### Step 3: Create Virtual Environment & Install Dependencies

Open **Command Prompt** or **PowerShell**:

```bash
cd C:\Users\sreea\OneDrive\Desktop\sqlserver_mcp

python -m venv venv
venv\Scripts\activate

pip install -r requirements.txt
```

### Step 4: Configure Environment Variables

```bash
copy .env.example .env
```

Edit `.env` with your SQL Server credentials:

```env
DB_SERVER=localhost
DB_PORT=1433
DB_NAME=YourDatabaseName
DB_USER=sa
DB_PASSWORD=YourActualPassword
```

> **Windows Auth:** If using Windows Authentication, you may need to switch from `pymssql` to `pyodbc`. See Troubleshooting.

### Step 5: Test the Server Standalone

```bash
python server.py
```

If it starts without errors, the server is ready. Press `Ctrl+C` to stop.

### Step 6: Register with Claude Desktop App

Edit your Claude Desktop config file:

**Windows location:**
```
%APPDATA%\Claude\claude_desktop_config.json
```

Add this to the `mcpServers` section:

```json
{
  "mcpServers": {
    "sqlserver": {
      "command": "C:\\Users\\sreea\\OneDrive\\Desktop\\sqlserver_mcp\\venv\\Scripts\\python.exe",
      "args": ["C:\\Users\\sreea\\OneDrive\\Desktop\\sqlserver_mcp\\server.py"],
      "env": {
        "DB_SERVER": "localhost",
        "DB_PORT": "1433",
        "DB_NAME": "YourDatabaseName",
        "DB_USER": "sa",
        "DB_PASSWORD": "YourActualPassword"
      }
    }
  }
}
```

### Step 7: Restart Claude Desktop

Close and reopen the Claude Desktop app. You should see "sqlserver" listed under the MCP tools icon (hammer icon).

---

## Registering with Claude.ai (Web)

If using Claude.ai in the browser instead of the Desktop app:

1. Go to **claude.ai → Settings → Integrations**
2. Click **Add Integration**
3. Select **MCP Server**
4. You'll need to expose the server via a URL (e.g., using `ngrok` or running in SSE mode)

To run in **SSE mode** (HTTP-based instead of stdio):

```python
# Change the last line of server.py to:
mcp.run(transport="sse", host="0.0.0.0", port=8000)
```

Then register `http://localhost:8000/sse` as the MCP server URL.

---

## Troubleshooting

### SQL Server TCP/IP Not Enabled

1. Open **SQL Server Configuration Manager**
2. Go to **SQL Server Network Configuration → Protocols for [INSTANCE]**
3. Right-click **TCP/IP** → **Enable**
4. Restart SQL Server service

### Connection Refused on Port 1433

```bash
# Verify SQL Server is listening
netstat -an | findstr 1433
```

If nothing shows, check SQL Server Configuration Manager for the correct port.

### Windows Authentication

Replace `pymssql` with `pyodbc` in `requirements.txt`:

```
pyodbc>=5.1.0
```

Update the connection in `server.py`:

```python
import pyodbc

def get_connection():
    conn_str = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={os.getenv('DB_SERVER', 'localhost')};"
        f"DATABASE={os.getenv('DB_NAME', 'master')};"
        f"Trusted_Connection=yes;"
    )
    return pyodbc.connect(conn_str)
```

### MCP Not Showing in Claude Desktop

- Ensure the path to `python.exe` in `claude_desktop_config.json` points to your **venv** Python
- Check Claude Desktop logs: **Help → Show Logs**
- Restart Claude Desktop after any config change
