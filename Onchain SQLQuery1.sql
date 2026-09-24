CREATE DATABASE Onchain_Analytics;
GO;

USE Onchain_Analytics;
GO

SELECT * FROM token_transfers_1;
SELECT * FROM transactions_1;

-- Non-clustered B-tree Indexes to accelerate Data retrieval
/* 
	CREATE INDEX idx_tx_from_address 
	ON transactions_1(from_address, to_address);

	CREATE INDEX idx_tx_to_address 
	ON transactions_1(to_address);

	CREATE INDEX idx_tx_timestamp 
	ON transactions_1(block_timestamp);

	CREATE INDEX idx_token_transfers_timestamp 
	ON token_transfers_1(block_timestamp);
*/

-- FINDING WHALE WALLETS
-- Querying Top Wallets By Transaction Volume
SELECT TOP 20 
	from_address, 
	COUNT(*) AS [Total Transactions],
	-- Convertint the WEI Value to readable value
	SUM(CAST(value AS FLOAT) / 1e18) AS [Total ETH Sent]
FROM transactions_1
WHERE from_address IS NOT NULL
GROUP BY from_address
ORDER BY [Total ETH Sent] DESC;


-- Ranking TOP 10 Wallets by Total ETH Moved in USD
SELECT TOP 10 
	from_address, 
	COUNT(*) AS [Total Transactions],
	ROUND(SUM(CAST(value AS FLOAT) / 1e18), 4) AS [Total ETH Moved],
	-- Converted ETH Value To USD At The Current Market Price As of The Time of Writimg This Query
	ROUND(SUM(CAST(value AS FLOAT) / 1e18) * 2465, 2) AS [ETH Estimated value (USD)],
	ROUND(SUM(CAST(gas AS FLOAT) * CAST(gas_price AS FLOAT) / 1e18), 4) AS Total_gas_fees_eth
FROM transactions_1
WHERE TRY_CONVERT(FLOAT, value) > 0
GROUP BY from_address
ORDER BY [Total ETH Moved] DESC;


-- Checking to verify the actual transactions a wallet made
SELECT 
	from_address, 
	value,
	COUNT(*)
FROM transactions_1
WHERE from_address = '0xf204f3acb05c405c0010f2a2ecfa9fe61783f1d1'
GROUP BY from_address, value
ORDER BY COUNT(*) DESC;


-- IDENTIFYING BOT WALLETS
-- Identify wallets that executes more than one transaction within the exact same block or in very short time frames 
SELECT 
	from_address,
	COUNT(DISTINCT tx_hash) AS [Total Trades],
	COUNT(DISTINCT block_number) AS [Active Blocks],
	ROUND(CAST(COUNT(DISTINCT tx_hash) AS FLOAT) / COUNT(DISTINCT block_number), 2) AS [Trade per Block],
	SUM(CAST(value AS FLOAT) / 1e18) AS [Total ETH Sent]
FROM transactions_1
GROUP BY from_address
HAVING COUNT(DISTINCT tx_hash) > 50
ORDER BY [Trade per Block] DESC;


-- Verifying the number of tx hash and blocks in the data
SELECT 
	COUNT(DISTINCT block_number),
	COUNT(DISTINCT tx_hash)
FROM transactions_1;


-- Testing for FLOAT
SELECT 1e18 AS result;


-- Validating the time gap between consecutive transactions
WITH WalletTiming AS (
	SELECT
		from_address,
		tx_hash,
		block_timestamp,

		-- Getting timestamp of the previous transaction by same wallet 
		LAG(TRY_CONVERT(datetime2, block_timestamp)) OVER (
			PARTITION BY from_address
			ORDER BY TRY_CONVERT(datetime2, block_timestamp) ASC
		) AS prev_timestamp
	FROM transactions_1
)

SELECT
	from_address,
	tx_hash,
	block_timestamp,
	prev_timestamp,

	-- Calculating interval in seconds between consecutive transactions
	DATEDIFF(SECOND, prev_timestamp, TRY_CONVERT(datetime2, block_timestamp)) AS seconds_since_last_tx
FROM WalletTiming
WHERE prev_timestamp IS NOT NULL
ORDER BY seconds_since_last_tx ASC;


-- Calculating interval in seconds between consecutive transactions within the CTE (Alternative)
WITH WalletCadence AS (
	SELECT
		from_address,
		DATEDIFF(
			SECOND,
			LAG(TRY_CONVERT(datetime2, block_timestamp)) OVER (
				PARTITION BY from_address
				ORDER BY TRY_CONVERT(datetime2, block_timestamp) ASC
			),
			TRY_CONVERT(datetime2, block_timestamp)
		) AS seconds_to_last_tx

	FROM transactions_1
)

-- Querying to calculate the frequency distribution of block intervals
SELECT
	from_address,
	seconds_to_last_tx,
	COUNT(*) AS Frequency
FROM WalletCadence
WHERE seconds_to_last_tx IS NOT NULL
GROUP BY from_address, seconds_to_last_tx
ORDER BY seconds_to_last_tx ASC;

-- Quering Actual TOP 10 Most likely Bot Wallets (With transactions executed within 24secs block creation)
/*
SELECT TOP 10
	from_address,
	SUM(CASE WHEN seconds_to_last_tx = 0 THEN 1 ELSE 0 END) AS Same_block_transaction,
	SUM(CASE WHEN seconds_to_last_tx = 12 THEN 1 ELSE 0 END) AS Consecutive_block_transaction,
	SUM(CASE WHEN seconds_to_last_tx <= 24 THEN 1 ELSE 0 END) AS Rapid_bot_cadence_total,
	COUNT(*) AS Total_tracked_transaction
FROM WalletCadence
WHERE seconds_to_last_tx IS NOT NULL
GROUP BY from_address
ORDER BY Rapid_bot_cadence_total DESC;
*/


-- GAS PRICE AND FEE TREND OVER TIME
-- Hourly Trend Query
SELECT
	-- Truncate date to YYYY-MM-DD HH:00:00
	DATEADD(HOUR, DATEDIFF(HOUR, 0, TRY_CONVERT(datetime2, block_timestamp)), 0) AS trade_hour,

	-- Gas Price in Gwei
	ROUND(AVG(CAST(gas_price AS FLOAT) / 1e9), 2) AS avg_gas_price_gwei,
	ROUND(MIN(CAST(gas_price AS FLOAT) / 1e9) ,2) AS min_gwei,
    ROUND(MAX(CAST(gas_price AS FLOAT) / 1e9) ,2) AS max_gwei,

	-- Actual Fees in ETH
	ROUND(AVG(CAST(gas AS FLOAT) * CAST(gas_price AS FLOAT) / 1e18), 5) AS avg_gas_fee_eth,
	ROUND(SUM(CAST(gas AS FLOAT) * CAST(gas_price AS FLOAT) / 1e18), 4) AS Total_fees_eth,

	COUNT(*) AS [Total Transactions],
	SUM(CAST(value AS FLOAT) / 1e18) AS [Total ETH Sent]
FROM transactions_1
WHERE block_timestamp IS NOT NULL
GROUP BY DATEADD(HOUR, DATEDIFF(HOUR, 0, TRY_CONVERT(datetime2, block_timestamp)), 0)
ORDER BY trade_hour;


-- Hourly Trend For A Single Day
SELECT
	-- Truncate date to YYYY-MM-DD HH:00:00
	DATEPART(HOUR, TRY_CONVERT(datetime2, block_timestamp)) AS trade_hour_day,

	-- Gas Price in Gwei
	ROUND(AVG(CAST(gas_price AS FLOAT) / 1e9), 2) AS avg_gas_price_gwei,
	ROUND(MIN(CAST(gas_price AS FLOAT) / 1e9) ,2) AS min_gwei,
    ROUND(MAX(CAST(gas_price AS FLOAT) / 1e9) ,2) AS max_gwei,

	-- Actual Fees in ETH
	ROUND(AVG(CAST(gas AS FLOAT) * CAST(gas_price AS FLOAT) / 1e18), 5) AS avg_gas_fee_eth,
	ROUND(SUM(CAST(gas AS FLOAT) * CAST(gas_price AS FLOAT) / 1e18), 4) AS Total_fees_eth,

	COUNT(*) AS [Total Transactions],
	SUM(CAST(value AS FLOAT) / 1e18) AS [Total ETH Sent]
FROM transactions_1
-- Filters The Exact Day
WHERE TRY_CONVERT(datetime2, block_timestamp) >= '2026-09-15 00:00:00' 
	AND TRY_CONVERT(datetime2, block_timestamp) < '2026-09-16 00:00:00'
GROUP BY DATEPART(HOUR, TRY_CONVERT(datetime2, block_timestamp))
ORDER BY trade_hour_day;


-- Checking Wallets That Cuased Spike of Gas Price For That Day
SELECT
	from_address,
	tx_hash,
	block_timestamp,
	ROUND(CAST(gas_price AS FLOAT) / 1e9, 2) AS gas_price_gwei,
	ROUND(CAST(gas AS FLOAT) * CAST(gas_price AS FLOAT) / 1e18, 5) AS Total_fees_eth
FROM transactions_1
WHERE TRY_CONVERT(datetime2, block_timestamp) >= '2026-09-15 00:00:00' 
	AND TRY_CONVERT(datetime2, block_timestamp) < '2026-09-16 00:00:00'
ORDER BY gas_price_gwei DESC;




-- Checking min and max block number for both tables
SELECT 
	'transactions_1' AS Table_name,
	MIN(CAST(block_number AS BIGINT)) AS Min_block,
	MAX(CAST(block_number AS BIGINT)) AS Max_block,
	COUNT(*) AS Row_count
FROM transactions_1
UNION ALL 
SELECT 
	'token_transfers_1' AS Table_name,
	MIN(CAST(block_number AS BIGINT)) AS Min_block,
	MAX(CAST(block_number AS BIGINT)) AS Max_block,
	COUNT(*) AS Row_count
FROM token_transfers_1;


-- Verifying The Schema of Both Tables
SELECT
	TABLE_NAME,
	COLUMN_NAME,
	DATA_TYPE,
	CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('transactions_1', 'token_transfers_1')
ORDER BY COLUMN_NAME, TABLE_NAME;


-- Checking To See Any Matching Rows In Both Tables
SELECT COUNT(*) AS matching_row
FROM transactions_1 t
INNER JOIN token_transfers_2 tt
	ON LOWER(LTRIM(RTRIM(t.tx_hash))) = LOWER(LTRIM(RTRIM(tt.tx_hash)));


-- Inspecting Transfers Generated By Top Most Likely Bot Wallets
SELECT
	t.from_address,
	t.tx_hash,
	tt.token_symbol,
	tt.to_address AS Token_recipient,
	ROUND(CAST(gas_price AS FLOAT) / 1e9, 2) AS gas_price_gwei
FROM transactions_1 t
INNER JOIN token_transfers_2 tt
	ON LOWER(LTRIM(RTRIM(t.tx_hash))) = LOWER(LTRIM(RTRIM(tt.tx_hash)))
ORDER BY gas_price_gwei DESC;

SELECT * FROM token_transfers_2;

/*
0xf204f3acb05c405c0010f2a2ecfa9fe61783f1d1
0x12d2b8ac38c59758a062a9f757f2740461779439
0xae6bbb0ce3329e7e50d028a4c14db645e666688e
0x923489cbb30f861fa60bae5c5c4e8e81bc13caf9
*/

SELECT
	t.from_address,
	tt.token_symbol,
	COUNT(*) AS Total_transfer
FROM transactions_1 t
INNER JOIN token_transfers_2 tt
	ON LOWER(LTRIM(RTRIM(t.tx_hash))) = LOWER(LTRIM(RTRIM(tt.tx_hash)))
WHERE t.from_address IN (
	'0xf204f3acb05c405c0010f2a2ecfa9fe61783f1d1',
	'0x12d2b8ac38c59758a062a9f757f2740461779439',
	'0xae6bbb0ce3329e7e50d028a4c14db645e666688e',
	'0x923489cbb30f861fa60bae5c5c4e8e81bc13caf9'
)
GROUP BY t.from_address, tt.token_symbol
ORDER BY Total_transfer DESC;


-- Top Tokens Traded
SELECT
	tt.token_symbol,
	tt.token_name,
	COUNT(DISTINCT t.tx_hash) AS Unique_swaps,
	COUNT(*) AS Total_transfer_events
FROM transactions_1 t
INNER JOIN token_transfers_2 tt
	ON LOWER(LTRIM(RTRIM(t.tx_hash))) = LOWER(LTRIM(RTRIM(tt.tx_hash)))
GROUP BY tt.token_symbol, tt.token_name
ORDER BY Total_transfer_events DESC;


-- Identifying Token Whales, Measuring token transfer size
SELECT TOP 10
	tt.from_address AS Sender,
	tt.to_address AS Recipient,
	tt.token_symbol,
	COUNT(*) AS Transfer_count,

	-- Hardcoded The Divisions
	ROUND(SUM(
		CASE
			WHEN tt.token_symbol IN ('USDC', 'USDT') THEN CAST(tt.value AS FLOAT) / 1e6
			ELSE CAST(tt.value AS FLOAT) / 1e18
		END
	), 2) AS Total_token_amount,

	-- Dynamically Normalizing All Tokens Across All Decimal Tiers
	ROUND(SUM(CAST(tt.value AS FLOAT) / POWER(10.0, CAST(tt.token_decimal AS INT))), 2) AS Total_token_units,

	-- Estimated USD Value
	ROUND(SUM(
		CASE
			WHEN tt.token_symbol IN ('USDC', 'USDT') THEN CAST(tt.value AS FLOAT) / 1e6
			WHEN tt.token_symbol = 'WETH' THEN (CAST(tt.value AS FLOAT) / 1e18) * 2465
			ELSE 0
		END
	), 2) AS Estimated_USD_volume
FROM token_transfers_2 tt
GROUP BY tt.from_address, tt.to_address, tt.token_symbol
ORDER BY Estimated_USD_volume DESC;