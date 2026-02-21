# Copilot Instructions — sqlserver_mcp

## Project Context
This is a **.NET 8 MCP Server** (based on Microsoft's MssqlMcp from SQL-AI-samples) that bridges AI IDEs (VS Code Copilot, Cursor, Claude Desktop) with the shared SQL Server database (`stockdata_db`). Part of a 7-repo stock trading analytics platform.

## Key Architecture Rules
- MCP server uses **stdio** transport (not HTTP)
- Connection via `CONNECTION_STRING` environment variable (not appsettings.json)
- All tools registered via `[McpServerTool]` attribute discovery in `Tools/` partial classes
- DI with `Microsoft.Extensions.DependencyInjection` for `ISqlConnectionFactory` and `Tools`
- Connection: `localhost\MSSQLSERVER01`, `stockdata_db`, Windows Integrated Auth

## 7 MCP Tools Exposed
- **ListTables** — Lists all tables from `INFORMATION_SCHEMA.TABLES` (read-only)
- **DescribeTable** — Get schema/columns/types for a table (read-only)
- **ReadData** — Execute SQL queries against database (read-only)
- **CreateTable** — Create new tables
- **DropTable** — Drop existing tables (destructive!)
- **InsertData** — Insert rows into tables
- **UpdateData** — Update existing rows

## Tech Stack
- .NET 8, C#, Microsoft.Data.SqlClient, MCP C# SDK
- `SqlConnectionFactory.cs` reads `CONNECTION_STRING` env var
- `Tools.cs` partial class with each tool in its own file

## VS Code MCP Configuration
```json
"MSSQL MCP": {
    "type": "stdio",
    "command": "C:\\Users\\sreea\\OneDrive\\Desktop\\sqlserver_mcp\\SQL-AI-samples\\MssqlMcp\\dotnet\\MssqlMcp\\bin\\Debug\\net8.0\\MssqlMcp.exe",
    "env": {
        "CONNECTION_STRING": "Server=localhost\\MSSQLSERVER01;Database=stockdata_db;Trusted_Connection=True;TrustServerCertificate=True"
    }
}
```

## Database
Provides access to all 29+ tables and 40+ views in `stockdata_db`:
- Market data: nasdaq_100_hist_data, nse_500_hist_data, forex_hist_data
- ML predictions: ml_trading_predictions, ml_nse_trading_predictions, forex_ml_predictions
- Strategy views: vw_PowerBI_AI_Technical_Combos, vw_strategy2_trade_opportunities
- Signal tracking, portfolio, fundamentals, market context, and more

## SQL Scripts
- `trading_system_setup.sql` — Stored procs and views for trading system
- `daily_trading_workflow.sql` — Morning pre-market workflow

## Sibling Repositories (same database)
- `stockdata_agenticai` — CrewAI agents (reads DB through SQL queries, not MCP)
- `sqlserver_copilot` / `sqlserver_copilot_nse` / `sqlserver_copilot_forex` — ML pipelines
- `streamlit-trading-dashboard` — Visualization dashboard
- `stockanalysis` — Data ingestion ETL
