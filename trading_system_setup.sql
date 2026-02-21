-- =====================================================
-- TRADING SYSTEM - STORED PROCEDURES & VIEWS
-- Execute this script in SQL Server Management Studio
-- =====================================================

USE stockdata_db;
GO

-- =====================================================
-- 1. STORED PROCEDURE: Get Daily Trading Signals
-- =====================================================
IF OBJECT_ID('sp_get_daily_trading_signals', 'P') IS NOT NULL 
    DROP PROCEDURE sp_get_daily_trading_signals;
GO

CREATE PROCEDURE sp_get_daily_trading_signals
    @min_confidence DECIMAL(5,2) = 55,
    @min_historical_accuracy DECIMAL(5,2) = 70,
    @min_predictions INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        CASE WHEN p.predicted_change_pct > 0 THEN 'BUY' ELSE 'SELL' END AS signal_type,
        p.ticker,
        p.company_name,
        p.target_date,
        CAST(p.current_price AS DECIMAL(10,2)) AS current_price,
        CAST(p.predicted_price AS DECIMAL(10,2)) AS predicted_price,
        CAST(p.predicted_change_pct AS DECIMAL(6,2)) AS predicted_change_pct,
        CAST(p.model_confidence AS DECIMAL(5,2)) AS confidence,
        h.historical_accuracy,
        h.total_predictions,
        p.model_name,
        -- Calculate suggested stop loss (3% from entry)
        CASE 
            WHEN p.predicted_change_pct > 0 THEN CAST(p.current_price * 0.97 AS DECIMAL(10,2))
            ELSE CAST(p.current_price * 1.03 AS DECIMAL(10,2))
        END AS stop_loss,
        -- Risk/Reward ratio
        CAST(ABS(p.predicted_change_pct) / 3.0 AS DECIMAL(4,2)) AS risk_reward_ratio
    FROM ai_prediction_history p
    INNER JOIN (
        SELECT 
            ticker,
            CAST(AVG(CASE WHEN direction_correct = 1 THEN 100.0 ELSE 0 END) AS DECIMAL(5,2)) AS historical_accuracy,
            COUNT(*) AS total_predictions
        FROM ai_prediction_history 
        WHERE actual_price IS NOT NULL 
          AND market = 'NSE 500' 
          AND days_ahead = 3
        GROUP BY ticker
        HAVING COUNT(*) >= @min_predictions 
           AND AVG(CASE WHEN direction_correct = 1 THEN 100.0 ELSE 0 END) >= @min_historical_accuracy
    ) h ON p.ticker = h.ticker
    WHERE p.actual_price IS NULL 
      AND p.target_date >= CAST(GETDATE() AS DATE)
      AND p.target_date <= CAST(GETDATE() + 3 AS DATE)
      AND p.market = 'NSE 500' 
      AND p.days_ahead = 3 
      AND p.model_confidence >= @min_confidence
      AND p.model_name = 'Gradient Boosting'
    ORDER BY h.historical_accuracy DESC, p.model_confidence DESC;
END
GO

-- =====================================================
-- 2. STORED PROCEDURE: Log a Trade
-- =====================================================
IF OBJECT_ID('sp_log_trade', 'P') IS NOT NULL 
    DROP PROCEDURE sp_log_trade;
GO

CREATE PROCEDURE sp_log_trade
    @ticker VARCHAR(50),
    @signal_type VARCHAR(10),
    @entry_price DECIMAL(18,2),
    @target_price DECIMAL(18,2),
    @stop_loss_price DECIMAL(18,2),
    @predicted_change_pct DECIMAL(6,2) = NULL,
    @model_confidence DECIMAL(5,2) = NULL,
    @historical_accuracy DECIMAL(5,2) = NULL,
    @notes VARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @company_name VARCHAR(200);
    SELECT TOP 1 @company_name = company_name 
    FROM ai_prediction_history 
    WHERE ticker = @ticker;
    
    INSERT INTO trade_log (
        ticker, company_name, signal_type, entry_date, entry_price,
        target_price, stop_loss_price, predicted_change_pct,
        model_confidence, historical_accuracy, notes
    )
    VALUES (
        @ticker, @company_name, @signal_type, CAST(GETDATE() AS DATE), @entry_price,
        @target_price, @stop_loss_price, @predicted_change_pct,
        @model_confidence, @historical_accuracy, @notes
    );
    
    SELECT SCOPE_IDENTITY() AS trade_id, 'Trade logged successfully' AS message;
END
GO

-- =====================================================
-- 3. STORED PROCEDURE: Close a Trade
-- =====================================================
IF OBJECT_ID('sp_close_trade', 'P') IS NOT NULL 
    DROP PROCEDURE sp_close_trade;
GO

CREATE PROCEDURE sp_close_trade
    @trade_id INT,
    @exit_price DECIMAL(18,2),
    @trade_status VARCHAR(20) = 'CLOSED'
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE trade_log
    SET exit_date = CAST(GETDATE() AS DATE),
        exit_price = @exit_price,
        actual_change_pct = CASE 
            WHEN signal_type = 'BUY' THEN (((@exit_price - entry_price) / entry_price) * 100)
            ELSE (((entry_price - @exit_price) / entry_price) * 100)
        END,
        profit_loss = CASE 
            WHEN signal_type = 'BUY' THEN (@exit_price - entry_price)
            ELSE (entry_price - @exit_price)
        END,
        trade_status = @trade_status
    WHERE trade_id = @trade_id;
    
    SELECT * FROM trade_log WHERE trade_id = @trade_id;
END
GO

-- =====================================================
-- 4. STORED PROCEDURE: Get Trading Performance
-- =====================================================
IF OBJECT_ID('sp_get_trading_performance', 'P') IS NOT NULL 
    DROP PROCEDURE sp_get_trading_performance;
GO

CREATE PROCEDURE sp_get_trading_performance
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Overall Summary
    SELECT 
        COUNT(*) AS total_trades,
        SUM(CASE WHEN trade_status = 'CLOSED' THEN 1 ELSE 0 END) AS closed_trades,
        SUM(CASE WHEN trade_status = 'OPEN' THEN 1 ELSE 0 END) AS open_trades,
        SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) AS winning_trades,
        SUM(CASE WHEN profit_loss < 0 THEN 1 ELSE 0 END) AS losing_trades,
        CAST(AVG(CASE WHEN profit_loss > 0 THEN 100.0 ELSE 0 END) AS DECIMAL(5,2)) AS win_rate,
        CAST(SUM(profit_loss) AS DECIMAL(18,2)) AS total_profit_loss,
        CAST(AVG(profit_loss) AS DECIMAL(18,2)) AS avg_profit_loss,
        CAST(AVG(actual_change_pct) AS DECIMAL(6,2)) AS avg_return_pct
    FROM trade_log
    WHERE trade_status = 'CLOSED';
    
    -- By Signal Type
    SELECT 
        signal_type,
        COUNT(*) AS trades,
        SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) AS wins,
        CAST(AVG(CASE WHEN profit_loss > 0 THEN 100.0 ELSE 0 END) AS DECIMAL(5,2)) AS win_rate,
        CAST(SUM(profit_loss) AS DECIMAL(18,2)) AS total_pnl
    FROM trade_log
    WHERE trade_status = 'CLOSED'
    GROUP BY signal_type;
    
    -- Recent Trades
    SELECT TOP 10
        trade_id, ticker, signal_type, entry_date, entry_price,
        exit_date, exit_price, actual_change_pct, profit_loss, trade_status
    FROM trade_log
    ORDER BY created_at DESC;
END
GO

-- =====================================================
-- 5. STORED PROCEDURE: Check Alerts
-- =====================================================
IF OBJECT_ID('sp_check_trading_alerts', 'P') IS NOT NULL 
    DROP PROCEDURE sp_check_trading_alerts;
GO

CREATE PROCEDURE sp_check_trading_alerts
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Get signals matching active alerts
    SELECT 
        a.alert_type,
        a.ticker AS alert_ticker,
        CASE WHEN p.predicted_change_pct > 0 THEN 'BUY' ELSE 'SELL' END AS signal_type,
        p.ticker,
        p.company_name,
        p.target_date,
        CAST(p.current_price AS DECIMAL(10,2)) AS current_price,
        CAST(p.predicted_price AS DECIMAL(10,2)) AS predicted_price,
        CAST(p.predicted_change_pct AS DECIMAL(6,2)) AS predicted_change_pct,
        CAST(p.model_confidence AS DECIMAL(5,2)) AS confidence,
        h.historical_accuracy,
        '⚠️ ALERT TRIGGERED' AS alert_status
    FROM trading_alerts a
    CROSS APPLY (
        SELECT p2.*, h2.historical_accuracy
        FROM ai_prediction_history p2
        INNER JOIN (
            SELECT ticker,
                CAST(AVG(CASE WHEN direction_correct = 1 THEN 100.0 ELSE 0 END) AS DECIMAL(5,2)) AS historical_accuracy
            FROM ai_prediction_history 
            WHERE actual_price IS NOT NULL AND market = 'NSE 500' AND days_ahead = 3
            GROUP BY ticker HAVING COUNT(*) >= 5
        ) h2 ON p2.ticker = h2.ticker
        WHERE p2.actual_price IS NULL 
          AND p2.target_date >= CAST(GETDATE() AS DATE)
          AND p2.market = 'NSE 500' 
          AND p2.days_ahead = 3
          AND p2.model_name = 'Gradient Boosting'
          AND p2.model_confidence >= a.min_confidence
          AND h2.historical_accuracy >= a.min_historical_accuracy
          AND (
              (a.ticker = 'ALL' AND ABS(p2.predicted_change_pct) >= ABS(a.min_predicted_change))
              OR (a.ticker = p2.ticker)
          )
          AND (
              (a.alert_type = 'HIGH_CONFIDENCE_BUY' AND p2.predicted_change_pct >= a.min_predicted_change)
              OR (a.alert_type = 'HIGH_CONFIDENCE_SELL' AND p2.predicted_change_pct <= a.min_predicted_change)
              OR (a.alert_type = 'SPECIFIC_STOCK')
          )
    ) p
    INNER JOIN (
        SELECT ticker,
            CAST(AVG(CASE WHEN direction_correct = 1 THEN 100.0 ELSE 0 END) AS DECIMAL(5,2)) AS historical_accuracy
        FROM ai_prediction_history 
        WHERE actual_price IS NOT NULL AND market = 'NSE 500' AND days_ahead = 3
        GROUP BY ticker HAVING COUNT(*) >= 5
    ) h ON p.ticker = h.ticker
    WHERE a.is_active = 1
    ORDER BY h.historical_accuracy DESC, p.model_confidence DESC;
END
GO

-- =====================================================
-- 6. VIEW: Current Open Positions
-- =====================================================
IF OBJECT_ID('vw_open_positions', 'V') IS NOT NULL 
    DROP VIEW vw_open_positions;
GO

CREATE VIEW vw_open_positions AS
SELECT 
    trade_id, ticker, company_name, signal_type,
    entry_date, entry_price, target_price, stop_loss_price,
    predicted_change_pct, model_confidence, historical_accuracy,
    DATEDIFF(DAY, entry_date, GETDATE()) AS days_in_trade,
    notes
FROM trade_log
WHERE trade_status = 'OPEN';
GO

-- =====================================================
-- 7. VIEW: Today's Signals Summary
-- =====================================================
IF OBJECT_ID('vw_todays_signals', 'V') IS NOT NULL 
    DROP VIEW vw_todays_signals;
GO

CREATE VIEW vw_todays_signals AS
SELECT 
    CASE WHEN p.predicted_change_pct > 0 THEN '🟢 BUY' ELSE '🔴 SELL' END AS signal,
    p.ticker,
    p.company_name,
    p.target_date,
    CAST(p.current_price AS DECIMAL(10,2)) AS current_price,
    CAST(p.predicted_price AS DECIMAL(10,2)) AS predicted_price,
    CAST(p.predicted_change_pct AS DECIMAL(6,2)) AS predicted_change_pct,
    CAST(p.model_confidence AS DECIMAL(5,2)) AS confidence,
    h.historical_accuracy,
    p.model_name
FROM ai_prediction_history p
INNER JOIN (
    SELECT ticker,
        CAST(AVG(CASE WHEN direction_correct = 1 THEN 100.0 ELSE 0 END) AS DECIMAL(5,2)) AS historical_accuracy
    FROM ai_prediction_history 
    WHERE actual_price IS NOT NULL AND market = 'NSE 500' AND days_ahead = 3
    GROUP BY ticker HAVING COUNT(*) >= 5 AND AVG(CASE WHEN direction_correct = 1 THEN 100.0 ELSE 0 END) >= 70
) h ON p.ticker = h.ticker
WHERE p.actual_price IS NULL 
  AND p.target_date >= CAST(GETDATE() AS DATE)
  AND p.target_date <= CAST(GETDATE() + 3 AS DATE)
  AND p.market = 'NSE 500' 
  AND p.days_ahead = 3 
  AND p.model_confidence >= 55
  AND p.model_name = 'Gradient Boosting';
GO

-- =====================================================
-- USAGE EXAMPLES
-- =====================================================
/*

-- 1. Get today's trading signals (default parameters)
EXEC sp_get_daily_trading_signals;

-- 2. Get signals with custom thresholds
EXEC sp_get_daily_trading_signals 
    @min_confidence = 60, 
    @min_historical_accuracy = 80,
    @min_predictions = 8;

-- 3. Log a new trade
EXEC sp_log_trade 
    @ticker = 'HDFCBANK.NS',
    @signal_type = 'SELL',
    @entry_price = 918.70,
    @target_price = 895.83,
    @stop_loss_price = 946.26,
    @predicted_change_pct = -2.49,
    @model_confidence = 59.22,
    @historical_accuracy = 100.00,
    @notes = 'High confidence signal based on Gradient Boosting model';

-- 4. Close a trade
EXEC sp_close_trade @trade_id = 1, @exit_price = 900.50;

-- 5. Check trading performance
EXEC sp_get_trading_performance;

-- 6. Check active alerts
EXEC sp_check_trading_alerts;

-- 7. View open positions
SELECT * FROM vw_open_positions;

-- 8. View today's signals
SELECT * FROM vw_todays_signals ORDER BY historical_accuracy DESC;

-- 9. Add a new alert for a specific stock
INSERT INTO trading_alerts (ticker, alert_type, min_confidence, min_historical_accuracy, min_predicted_change)
VALUES ('TATASTEEL.NS', 'SPECIFIC_STOCK', 55, 65, 1.5);

*/

PRINT '✅ Trading System Setup Complete!';
PRINT '';
PRINT 'Tables Created: trade_log, trading_alerts, daily_signals_history';
PRINT 'Procedures Created: sp_get_daily_trading_signals, sp_log_trade, sp_close_trade, sp_get_trading_performance, sp_check_trading_alerts';
PRINT 'Views Created: vw_open_positions, vw_todays_signals';
GO
