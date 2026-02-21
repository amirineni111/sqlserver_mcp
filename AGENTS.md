# AGENTS.md — sqlserver_mcp

## Overview
This repo does NOT contain CrewAI agents. It is a **.NET 8 MCP Server** (based on Microsoft's MssqlMcp from SQL-AI-samples) that provides AI IDEs with SQL Server database access.

## MCP Architecture

```
AI IDE (VS Code Copilot / Cursor / Claude Desktop)
        │
        ▼ (MCP Protocol - stdio transport)
  MssqlMcp (.NET 8 Console App)
        │  Uses CONNECTION_STRING env var
        ▼ (ADO.NET / Microsoft.Data.SqlClient)
  SQL Server (192.168.87.27\MSSQLSERVER01 → stockdata_db)
```

## MCP Tools (7)

| Tool | Description | Read-Only |
|------|-------------|-----------|
| **ListTables** | Lists all tables (`INFORMATION_SCHEMA.TABLES`) | Yes |
| **DescribeTable** | Get schema/columns/types for a table | Yes |
| **ReadData** | Execute SQL queries against the database | Yes |
| **CreateTable** | Create new tables | No |
| **DropTable** | Drop existing tables | No (Destructive!) |
| **InsertData** | Insert rows into tables | No |
| **UpdateData** | Update existing rows | No |

## Configuration
```json
"MSSQL MCP": {
    "type": "stdio",
    "command": "C:\\Users\\sreea\\OneDrive\\Desktop\\sqlserver_mcp\\SQL-AI-samples\\MssqlMcp\\dotnet\\MssqlMcp\\bin\\Debug\\net8.0\\MssqlMcp.exe",
    "env": {
        "CONNECTION_STRING": "Server=192.168.87.27\\MSSQLSERVER01;Database=stockdata_db;User Id=remote_user;Password=YourStrongPassword123!;TrustServerCertificate=True"
    }
}
```

## Database Access
Provides access to all 29+ tables and 40+ views in `stockdata_db` (market data, ML predictions, signal tracking, portfolio, fundamentals, strategy views).

## SQL Scripts
- `trading_system_setup.sql` — Creates stored procs (`sp_get_daily_trading_signals`, `sp_check_trading_alerts`) and views
- `daily_trading_workflow.sql` — Morning pre-market workflow: alerts, signals, portfolio, market breadth

## Ecosystem Role
Development infrastructure layer. Lets developers explore the shared trading database during AI-assisted development sessions across all 7 repos. Does not run scheduled tasks, train models, or generate reports.
