-- =====================================================
-- DAILY TRADING WORKFLOW
-- Run this script every morning before market opens
-- =====================================================

USE stockdata_db;
GO

PRINT '========================================';
PRINT '  DAILY TRADING SIGNALS - ' + CONVERT(VARCHAR, GETDATE(), 106);
PRINT '========================================';
PRINT '';

-- =====================================================
-- STEP 1: Check Active Alerts
-- =====================================================
PRINT '📢 ACTIVE ALERTS:';
PRINT '----------------';
EXEC sp_check_trading_alerts;

-- =====================================================
-- STEP 2: Get Today's High-Confidence Signals
-- =====================================================
PRINT '';
PRINT '🎯 HIGH CONFIDENCE SIGNALS (100% Historical Accuracy):';
PRINT '------------------------------------------------------';

SELECT 
    CASE WHEN predicted_change_pct > 0 THEN '🟢 BUY' ELSE '🔴 SELL' END AS signal,
    ticker,
    company_name,
    target_date,
    current_price,
    predicted_price,
    predicted_change_pct AS pred_chg_pct,
    confidence,
    historical_accuracy AS hist_acc,
    -- Suggested Stop Loss (3%)
    CASE 
        WHEN predicted_change_pct > 0 THEN CAST(current_price * 0.97 AS DECIMAL(10,2))
        ELSE CAST(current_price * 1.03 AS DECIMAL(10,2))
    END AS stop_loss
FROM vw_todays_signals
WHERE historical_accuracy >= 100
ORDER BY ABS(predicted_change_pct) DESC;

-- =====================================================
-- STEP 3: Get Additional Good Signals (75%+ Accuracy)
-- =====================================================
PRINT '';
PRINT '📊 ADDITIONAL SIGNALS (75%+ Historical Accuracy):';
PRINT '------------------------------------------------';

SELECT TOP 15
    CASE WHEN predicted_change_pct > 0 THEN '🟢 BUY' ELSE '🔴 SELL' END AS signal,
    ticker,
    company_name,
    target_date,
    current_price,
    predicted_price,
    predicted_change_pct AS pred_chg_pct,
    confidence,
    historical_accuracy AS hist_acc
FROM vw_todays_signals
WHERE historical_accuracy >= 75 AND historical_accuracy < 100
ORDER BY historical_accuracy DESC, ABS(predicted_change_pct) DESC;

-- =====================================================
-- STEP 4: Review Open Positions
-- =====================================================
PRINT '';
PRINT '📂 OPEN POSITIONS:';
PRINT '-----------------';

SELECT 
    trade_id,
    ticker,
    signal_type,
    entry_date,
    entry_price,
    target_price,
    stop_loss_price,
    days_in_trade,
    predicted_change_pct
FROM vw_open_positions
ORDER BY entry_date;

-- =====================================================
-- STEP 5: Check if any open positions hit target/stop
-- =====================================================
PRINT '';
PRINT '⚠️ POSITIONS TO REVIEW (check current market prices):';
PRINT '----------------------------------------------------';

SELECT 
    t.trade_id,
    t.ticker,
    t.signal_type,
    t.entry_price,
    t.target_price,
    t.stop_loss_price,
    p.current_price AS latest_price,
    CASE 
        WHEN t.signal_type = 'BUY' AND p.current_price >= t.target_price THEN '✅ TARGET HIT - CLOSE'
        WHEN t.signal_type = 'BUY' AND p.current_price <= t.stop_loss_price THEN '🛑 STOP LOSS - CLOSE'
        WHEN t.signal_type = 'SELL' AND p.current_price <= t.target_price THEN '✅ TARGET HIT - CLOSE'
        WHEN t.signal_type = 'SELL' AND p.current_price >= t.stop_loss_price THEN '🛑 STOP LOSS - CLOSE'
        ELSE '⏳ HOLD'
    END AS action_needed
FROM vw_open_positions t
LEFT JOIN (
    SELECT ticker, MAX(current_price) AS current_price
    FROM ai_prediction_history
    WHERE prediction_date = (SELECT MAX(prediction_date) FROM ai_prediction_history)
    GROUP BY ticker
) p ON t.ticker = p.ticker;

-- =====================================================
-- STEP 6: Performance Summary
-- =====================================================
PRINT '';
PRINT '📈 TRADING PERFORMANCE SUMMARY:';
PRINT '------------------------------';
EXEC sp_get_trading_performance;

-- =====================================================
-- QUICK ACTIONS REMINDER
-- =====================================================
PRINT '';
PRINT '========================================';
PRINT '  QUICK ACTIONS';
PRINT '========================================';
PRINT '';
PRINT '-- To log a new trade:';
PRINT 'EXEC sp_log_trade @ticker=''TICKER.NS'', @signal_type=''BUY'', @entry_price=100, @target_price=105, @stop_loss_price=97;';
PRINT '';
PRINT '-- To close a trade:';
PRINT 'EXEC sp_close_trade @trade_id=1, @exit_price=104.50;';
PRINT '';
PRINT '-- To add an alert:';
PRINT 'INSERT INTO trading_alerts (ticker, alert_type, min_confidence, min_historical_accuracy) VALUES (''STOCK.NS'', ''SPECIFIC_STOCK'', 55, 70);';
PRINT '';
GO
