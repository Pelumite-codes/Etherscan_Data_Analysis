# 🔍 Forensic On-Chain Analysis: Detecting MEV & Arbitrage Bots on Uniswap V3

An end-to-end blockchain analytics and data engineering project investigating execution cadences, Priority Gas Auctions (PGA), and liquidity routing behavior on the Uniswap V3 Router (`0xE592427A0AEce92De3Edee1F18E0157C05861564`) using Python, Etherscan V2 API, and Microsoft SQL Server (T-SQL).

---

## 📌 Executive Summary
By querying 10,000 router transactions and 6,364 ERC-20 token transfer events spanning Ethereum blocks `25,943,331` to `25,985,564`, this project isolates programmatic bot actors from manual retail traders. The analysis correlates **windowed temporal intervals**, **gas bidding dynamics**, and **relational token tracking** to profile algorithmic actors on-chain.

---

## 🔬 Core Findings & Insights

### 1. The 12-Second Slot Rhythm (Bot Cadence Identification)
* **Proof-of-Stake Heartbeat:** Ethereum transactions inherit their parent block's 12-second slot timestamp, causing inter-transaction intervals to resolve in strict multiples of 12 (0s, 12s, 24s). 
![inter-transaction intervals in SSMS](assets/12_secs_slot_timestamp_1.png)
* **High-Frequency Classification:** Screened wallets submitting transactions within $\le 24$ seconds across multi-trade sequences using window functions.
![Frequency Classification Analysis](assets/High_Frequency_Classification.png)
* **Primary Bot Isolated:** Wallet `0xf204f3acb05c405c0010f2a2ecfa9fe61783f1d1` executed **207 rapid transactions**, featuring **86 atomic same-block executions (0 seconds)** and **77 consecutive-block trades (12 seconds)**.
![Bots Analysis](assets/Primary_Bots.png)
 
### 2. Economic Forensics: Priority Gas Auctions (PGA)
* Hourly gas metrics revealed recurring **$10\times$ to $20\times$ divergences** between baseline gas prices (0.10–0.40 Gwei) and maximum bids (>21.00 Gwei).
![Hourly gas metrics in SSMS](assets/Hourly_Gas_Metrics.png)
![Hourly gas metrics in SSMS](assets/Hourly_Gas_per_Day_Metrics.png)
* An intra-day query on 2026-09-15 isolated high-priority bidding activity during **18:50 and 18:59 UTC** window:
  * Competing automated wallets (`0x38c3a2...` and `0xf3e5ba...`) matchedidentical aggressive bidsof **4.59 Gwei** just **12 Seconds (1 Block) apart** at 18:57:11 and 18:57:23 UTC.
  * Primary bot `0xf204f3...` executed rapid multi-tx burst within this cluster, including two simulteneous transactions at **18:57:35 UTC** (3.03 Gwei) and multiple trades at **18:59:11 UTC** (2.92 Gwei).
  ![0xf204f3... Bot Analysis](assets/Targeted_Intra_day_Investigation.png)

### 3. Capital Sizing & Asset Specialization
* **Liquidity Route Concentration:** WETH (Wrapped Ether) dominated router interactions with 286 unique swaps (398 transfer events), followed by stablecoins (USDT and USDC).
![Top Token Analysis](assets/Liquidity_Route_Concentration.png)
* **Whale vs. Bot Divergence:**
  * **Capital Whales** The top native ETH move (`0x3be1268...`) routed **160.9 ETH (~$396,657 USD)** across **7 transactions, submitting standard baseline gas fees (~0.12 Gwei).
  ![Top Whale Analysis](assets/Retail_Whales.png)
  * **MEV Bots** routed zero-native ETH transactions through ERC-20 pools, relying on repeated micro-margin swaps and paying elevated priority fees (2.9-4.6 Gwei) to ensure fast inclusion.
  ![MEV Bots Analysis](assets/MEV_bots_Pattern.png)

---

## 🛠️ Data Pipeline & Technical Challenges Overcome

| Challenge | Root Cause | Solution Implemented |
| :--- | :--- | :--- |
| **API Pagination Drift** | Initial token transfer extractions capped at 1,000 rows (Page 1 default), yielding only 42 cross-table matches. | Re-engineered the Python ingestion script to dynamically lock `startblock` and `endblock` boundaries matching the transaction table and looped pagination to capture all 6,364 emitted transfer events. |
| **Silent Join Failures** | Hex strings exported from CSVs had invisible trailing whitespace and casing discrepancies. | Implemented defensive string cleansing directly inside the relational join: `LOWER(LTRIM(RTRIM(t.tx_hash))) = LOWER(LTRIM(RTRIM(tt.tx_hash)))`. |
| **Cartesian Join Traps** | Joining on `block_number` produced 334 false-positive matches due to Many-to-Many block collisions. | Enforced strict `tx_hash` foreign-key linking to ensure only genuine parent router swaps were correlated with child token transfers. |
| **Multi-Decimal Scaling** | Distinct tokens use different native decimal precision (0, 6, 8, 9, 18), distorting volume sums. | Formulated dynamic exponential normalization using `POWER(10.0, CAST(token_decimal AS INT))` across all 31 unique assets. |

---

## 💻 Key SQL Logic

```sql
-- 1. Classifying Wallet Cadence via Window Functions
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
SELECT TOP 10
    from_address,
    SUM(CASE WHEN seconds_to_last_tx = 0 THEN 1 ELSE 0 END) AS same_block_trades,
    SUM(CASE WHEN seconds_to_last_tx = 12 THEN 1 ELSE 0 END) AS consecutive_block_trades,
    SUM(CASE WHEN seconds_to_last_tx <= 24 THEN 1 ELSE 0 END) AS rapid_bot_cadence_total,
    COUNT(*) AS total_tracked_trades
FROM WalletCadence
WHERE seconds_to_last_tx IS NOT NULL
GROUP BY from_address
ORDER BY same_block_trades DESC, rapid_bot_cadence_total DESC;
```

---

## 🚀 How to Run Locally

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Pelumite-codes/Etherscan_Data_Analysis.git
   cd ethereum-dex-bot-analysis
   ```
2. **Install Python dependencies:**
   ```bash
   pip install requests pandas python-dotenv
   ```
3. **Configure environment:**
   Create a `.env` file in the root directory:
   ```env
   ETHERSCAN_API_KEY="your_api_key_here"
   ```
4. **Run Extraction Pipeline:**
   ```bash
   python scripts/etherscan_data.py
   ```
5. **Execute Analysis:**
   Open `Onchain SQLQuery1.sql` inside SQL Server Management Studio (SSMS) and run the analytical suite.