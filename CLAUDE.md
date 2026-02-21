# CLAUDE.md — sqlserver_mcp (.NET 8 MCP Server for SQL Server)

> **Master project context file for AI assistants (Claude, Copilot, Cursor).**
> Last updated: February 20, 2026

---

## 1. SYSTEM OVERVIEW

This is the **MCP (Model Context Protocol) bridge** — one of **7 interconnected repositories** that form an AI-powered stock trading analytics platform. It provides AI IDEs (VS Code Copilot, Cursor, Claude Desktop) with direct access to the shared SQL Server database.

### Repository Map

| Layer | Repo | Location | Purpose |
|-------|------|----------|---------|
| **Data Ingestion** | `stockanalysis` | `C:\Users\sreea\OneDrive\Documents\stockanalysis` | ETL: yfinance/Alpha Vantage → SQL Server |
| **SQL Infrastructure** ⭐ | **`sqlserver_mcp`** | `Desktop\sqlserver_mcp` | **THIS REPO** — .NET 8 MCP Server for AI IDE ↔ SQL Server |
| **SQL Views + Dashboard** | `streamlit-trading-dashboard` | `Desktop\streamlit-trading-dashboard` | 40+ views, signal tracking, 15-page Streamlit UI |
| **ML: NASDAQ** | `sqlserver_copilot` | `Desktop\sqlserver_copilot` | Gradient Boosting → `ml_trading_predictions` |
| **ML: NSE** | `sqlserver_copilot_nse` | `Desktop\sqlserver_copilot_nse` | 5-model ensemble → `ml_nse_trading_predictions` |
| **ML: Forex** | `sqlserver_copilot_forex` | `Desktop\sqlserver_copilot_forex` | XGBoost/LightGBM → `forex_ml_predictions` |
| **Agentic AI** | `stockdata_agenticai` | `Desktop\stockdata_agenticai` | 7 CrewAI agents, daily briefing email |

---

## 2. THIS REPO: sqlserver_mcp

### Purpose
Hosts a **.NET 8 MCP Server** (based on Microsoft's [MssqlMcp](https://github.com/Azure-Samples/SQL-AI-samples) sample) that exposes SQL Server database operations via the Model Context Protocol. This allows AI-powered IDEs to query, explore schema, and manage data in the trading platform database directly through natural language requests.

### Architecture
```
AI IDE (VS Code Copilot / Cursor / Claude Desktop)
        │
        ▼ (MCP Protocol - stdio transport)
  MssqlMcp (.NET 8 Console App)
        │  Uses CONNECTION_STRING env var
        ▼ (ADO.NET / Microsoft.Data.SqlClient)
  SQL Server (192.168.87.27\MSSQLSERVER01 → stockdata_db)
```

### Key Files

```
sqlserver_mcp/
├── CLAUDE.md                             # This file
├── AGENTS.md                             # Agent architecture reference
├── .cursorrules                          # Cursor IDE context
├── .github/copilot-instructions.md       # VS Code Copilot context
├── daily_trading_workflow.sql             # Morning trading workflow script
├── trading_system_setup.sql              # Stored procs & views setup (sp_get_daily_trading_signals, etc.)
└── SQL-AI-samples/                       # Microsoft SQL-AI-samples (contains MCP server)
    └── MssqlMcp/
        └── dotnet/
            ├── MssqlMcp.sln              # Solution file
            ├── MssqlMcp/
            │   ├── Program.cs            # Entry point — Host builder + MCP server registration
            │   ├── MssqlMcp.csproj       # .NET 8 project file
            │   ├── SqlConnectionFactory.cs   # CONNECTION_STRING env var → SqlConnection
            │   ├── ISqlConnectionFactory.cs  # Interface for DI
            │   ├── DbOperationResult.cs      # Standard result model
            │   └── Tools/
            │       ├── Tools.cs          # Partial class base (DataTable helper)
            │       ├── ListTables.cs     # List all tables in database
            │       ├── DescribeTable.cs  # Get schema for a table
            │       ├── CreateTable.cs    # Create new tables
            │       ├── DropTable.cs      # Drop existing tables
            │       ├── InsertData.cs     # Insert data into tables
            │       ├── ReadData.cs       # Execute SQL queries (SELECT)
            │       └── UpdateData.cs     # Update data in tables
            └── MssqlMcp.Tests/           # xUnit test project
```

---

## 3. MCP TOOLS EXPOSED (7 Tools)

| Tool | Description | Read-Only | MCP Attributes |
|------|-------------|-----------|----------------|
| **ListTables** | Lists all tables (`INFORMATION_SCHEMA.TABLES`) | Yes | `ReadOnly=true, Idempotent=true` |
| **DescribeTable** | Get schema/columns/types for a table | Yes | `ReadOnly=true, Idempotent=true` |
| **ReadData** | Execute arbitrary SQL queries | Yes | `ReadOnly=true, Idempotent=true` |
| **CreateTable** | Create new tables in the database | No | `Destructive=false` |
| **DropTable** | Drop existing tables | No | `Destructive=true` |
| **InsertData** | Insert rows into tables | No | `Destructive=false` |
| **UpdateData** | Update existing rows | No | `Destructive=false` |

### Important: ReadData Tool
The `ReadData` tool executes **arbitrary SQL** passed as the `sql` parameter. Unlike some MCP servers, it does **NOT** restrict to SELECT-only — it relies on the AI IDE to send appropriate queries. For safety during development:
- Always use SELECT queries for data exploration
- The `ListTables` and `DescribeTable` tools are the safest entry points
- Be cautious with write tools (CreateTable, InsertData, UpdateData, DropTable) in production databases

---

## 4. DATABASE CONTEXT

### Connection
- **Server**: `192.168.87.27\MSSQLSERVER01` (Machine A LAN IP)
- **Database**: `stockdata_db`
- **Auth**: SQL Auth (`User Id=remote_user;Password=YourStrongPassword123!;TrustServerCertificate=True`)
- **Env Var**: `CONNECTION_STRING` (read by `SqlConnectionFactory.cs`)

### What This Server Provides Access To

#### Tables (29+)
Market data, ML predictions, signal tracking, portfolio — the full shared ecosystem:
- `nasdaq_100_hist_data`, `nse_500_hist_data`, `forex_hist_data` (market data)
- `ml_trading_predictions`, `ml_nse_trading_predictions`, `forex_ml_predictions` (ML outputs)
- `ai_prediction_history`, `signal_tracking_history` (tracking)
- `nasdaq_top100`, `nse_500`, `forex_master` (ticker masters)
- `portfolio_tracker`, `trade_log`, `trading_alerts`, `family_assets` (portfolio)
- `market_context_daily` (VIX, DXY, sector ETFs, yields)

#### Views (40+)
- **Technical indicators**: `{market}_RSI_calculation`, `{market}_macd`, `{market}_bollingerband`, `{market}_stochastic`, `{market}_fibonacci`, `{market}_support_resistance`, `{market}_patterns` per market
- **Strategy views**: `vw_PowerBI_AI_Technical_Combos` (TIER 1/2), `vw_strategy2_trade_opportunities` (Grades A-D)
- **Signal views**: `{market}_rsi_signals`, `{market}_macd_signals`, `{market}_bb_signals`, crossover aggregates
- **Fundamental screening**: `vw_value_stocks_screen`, `vw_quality_stocks_screen`, `vw_growth_stocks_screen`, `vw_dividend_stocks_screen`
- **Performance views**: `vw_signal_performance_summary`, `vw_model_performance_summary`, `vw_recent_prediction_accuracy`

#### Stored Procedures
- `sp_get_daily_trading_signals` — High-confidence trading signals
- `sp_check_trading_alerts` — Active alert check
- Any other stored procedures in `stockdata_db`

---

## 5. CONFIGURATION

### VS Code — Settings JSON
Add to VS Code settings (`Ctrl+Shift+P` → `Preferences: Open Settings (JSON)`):
```json
"mcp": {
    "servers": {
        "MSSQL MCP": {
            "type": "stdio",
            "command": "C:\\Users\\sreea\\OneDrive\\Desktop\\sqlserver_mcp\\SQL-AI-samples\\MssqlMcp\\dotnet\\MssqlMcp\\bin\\Debug\\net8.0\\MssqlMcp.exe",
            "env": {
                "CONNECTION_STRING": "Server=192.168.87.27\\MSSQLSERVER01;Database=stockdata_db;User Id=remote_user;Password=YourStrongPassword123!;TrustServerCertificate=True"
            }
        }
    }
}
```

### Claude Desktop — Config File
`File → Settings → Developer → Edit Config` (edits `claude_desktop_config.json`):
```json
{
    "mcpServers": {
        "MSSQL MCP": {
            "command": "C:\\Users\\sreea\\OneDrive\\Desktop\\sqlserver_mcp\\SQL-AI-samples\\MssqlMcp\\dotnet\\MssqlMcp\\bin\\Debug\\net8.0\\MssqlMcp.exe",
            "env": {
                "CONNECTION_STRING": "Server=192.168.87.27\\MSSQLSERVER01;Database=stockdata_db;User Id=remote_user;Password=YourStrongPassword123!;TrustServerCertificate=True"
            }
        }
    }
}
```

### Cursor IDE
Add MCP server via Cursor settings with the same command and env var.

### Building the MCP Server
```bash
cd SQL-AI-samples\MssqlMcp\dotnet
dotnet build
# Binary output: MssqlMcp\bin\Debug\net8.0\MssqlMcp.exe
```

---

## 6. SQL SCRIPTS IN THIS REPO

### `trading_system_setup.sql`
Creates stored procedures and views for the trading system:
- `sp_get_daily_trading_signals` — Parametric signal query (min confidence, min accuracy, min predictions)
- `sp_check_trading_alerts` — Alert threshold checks
- `vw_todays_signals` — Today's actionable signals view

### `daily_trading_workflow.sql`
A morning pre-market workflow script that:
1. Checks active alerts via `sp_check_trading_alerts`
2. Gets high-confidence signals (100% historical accuracy)
3. Gets additional signals (75%+ accuracy)
4. Shows portfolio positions
5. Summarizes market breadth

---

## 7. CODING CONVENTIONS

### .NET 8 Patterns
- **DI Container**: `Microsoft.Extensions.DependencyInjection` for `ISqlConnectionFactory` and `Tools`
- **Transport**: stdio (standard I/O, not HTTP) — `WithStdioServerTransport()`
- **Tool Discovery**: Assembly-based — `WithToolsFromAssembly()` finds all `[McpServerTool]` attributes
- **Partial Classes**: `Tools` is a partial class — each tool in its own file under `Tools/`
- **Connection Pooling**: Handled by ADO.NET — `SqlConnectionFactory` creates per-request connections
- **Logging**: Console logging via `Microsoft.Extensions.Logging` (Trace level to stderr)

### Building & Running
```bash
cd SQL-AI-samples\MssqlMcp\dotnet
dotnet build
dotnet run --project MssqlMcp
```

---

## 8. ECOSYSTEM ROLE

This repo is a **development utility/infrastructure** layer. It does NOT:
- Run scheduled tasks or pipelines
- Train ML models
- Generate reports or emails

It EXISTS to let AI IDEs directly explore and interact with the trading platform database during development sessions (schema discovery, data exploration, query testing, ad-hoc analysis).

### Who Uses This
- Developers using **VS Code + GitHub Copilot** (Agent mode with MCP tools)
- Developers using **Cursor IDE**
- **Claude Desktop** users
- Any **MCP-compatible AI tool** that supports stdio transport

### Cross-Repo Development Use Cases
When developing in any of the 7 repos, the MCP server enables:
- **stockanalysis**: Verify data loaded correctly, check row counts, inspect schema
- **sqlserver_copilot / _nse / _forex**: Query prediction tables, check model outputs, explore feature data
- **streamlit-trading-dashboard**: Test views, verify signal calculations, debug dashboard queries
- **stockdata_agenticai**: Test SQL queries from `config/sql_queries.py`, explore agent data sources
