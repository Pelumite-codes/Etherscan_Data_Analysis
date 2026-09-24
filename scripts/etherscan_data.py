# curl "https://api.etherscan.io/api?module=account&action=balance&address=0x1f9840a85d5af5bf1d1762f925bdaddc4201f984&apikey=57N81UBC457DBHGKZD96PRW311HSR4CSMF"

# python -c "import requests; r = requests.get('https://api.etherscan.io/api?module=account&action=txlist&address=0xE592427A0AEce92De3Edee1F18E0157C05861564&startblock=0&endblock=99999999&sort=desc&apikey=57N81UBC457DBHGKZD96PRW311H8R4CSMF'); print(r.status_code, r.json())"
        

"""
Etherscan Data Downloader (V2 API)
Downloads transaction data and token transfers from Etherscan using V2 endpoints
Exports directly to CSV for SQL import
"""

import os
import requests
import pandas as pd
import time
from datetime import datetime, timezone, timedelta
from dotenv import load_dotenv

load_dotenv()
API_KEY = os.getenv("ETHERSCAN_API_KEY")
OUTPUT_DIR = "./etherscan_data/" 


# Etherscan API endpoints
ETHERSCAN_BASE_URL = "https://api.etherscan.io/v2/api"


# TRANSACTIONS DATASET DOWNLOAD 

def download_transactions(target_count = 10000):
    """
    Download recent transactions using Etherscan V2 API
    """
    print("📥 Downloading transactions...")

    all_transactions = []

    # Popular DEX address with lots of transaction activity
    uniswap_v3_router = "0xE592427A0AEce92De3Edee1F18E0157C05861564"
    max_pages = target_count // 1000
    
    # V2 API Parameters (cleaner than V1)
    for page in range(1, max_pages + 1):
        params = {
            'chainid': '1',
            'module': 'account',
            'action': 'txlist',  # Note: V2 still uses this, but other endpoints changed
            'address': uniswap_v3_router,
            'startblock': 0,
            'endblock': 99999999,
            'page': page,
            'offset': 1000,  # Get up to 10k records
            'sort': 'desc',
            'apikey': API_KEY
        }

        try:
            print(f"Querying V2 API for transactions from {uniswap_v3_router[:10]}...")
            response = requests.get(ETHERSCAN_BASE_URL, params = params, timeout = 15)
            
            # Check HTTP response
            if response.status_code != 200:
                print(f"❌ HTTP Error on page {page}: {response.status_code}")
                return []
            
            data = response.json()
            # V2 API Response Check
            if data.get('status') == '1':
                transactions = data.get('result', [])
                all_transactions.extend(transactions)
                print(f"✓ Downloaded {len(transactions)} records. A Total of {len(all_transactions)} transactions")

                if len(transactions) < 1000:
                    break
                
            else:
                # If you see "deprecated V1 endpoint" here, endpoint URL is wrong
                message = data.get('message', 'Unknown error')
                print(f"⚠️  API returned: {message}")
                break
                
        except Exception as e:
            print(f"❌ Error downloading transactions: {e}")
            break

        time.sleep(0.25)

    return all_transactions


# TOKEN TRANSFERS DATASET DOWNLOAD (V2 API)
 
def download_token_transfers(target_count = 10000):
    """
    Download ERC-20 token transfer events using Etherscan V2 Logs endpoint
    """
    print("📥 Downloading token transfers...")

    all_transactions = []
    uniswap_v3_router = "0xE592427A0AEce92De3Edee1F18E0157C05861564"
    max_pages = target_count // 1000

    for page in range(1, max_pages + 1):
        # V2 Logs endpoint
        params = {
            'chainid': '1',
            'module': 'account',  # V2: More organized endpoint naming
            'action': 'tokentx',  # Clear action name
            'address': uniswap_v3_router,
            'startblock': 25943331,
            'endblock': 25985564,
            'page': page,
            'offset': 1000,  # Get up to 1000 log entries
            'sort': 'desc',
            'apikey': API_KEY
        }
        try: 
            print(f"Querying V2 logs endpoint (blocks)...")
            response = requests.get(ETHERSCAN_BASE_URL, params = params, timeout = 15)
            
            if response.status_code != 200:
                print(f"❌ HTTP Error: {response.status_code}")
                return []
            
            data = response.json()
            
            # V2 Response handling
            if data.get('status') == '1':
                transfers = data.get('result', [])
                all_transactions.extend(transfers)
                print(f"✓ Downloaded {len(transfers)} token transfer events")

                if len(transfers) < 1000:
                    break
                
            else:
                message = data.get('message', 'Unknown error')
                print(f"⚠️  API returned: {message}")
                break
                
        except Exception as e:
            print(f"❌ Error downloading token transfers: {e}")
            break

        time.sleep(0.25)
        
    return all_transactions


# CLEAN & STRUCTURE DATA

def transform_transactions(raw_tx):
    """
    Convert raw Etherscan TX data to standardized schema
    Handles different data types
    """
    cleaned = []
    
    for tx in raw_tx:
        try:
            # Convert hex values to integers where needed
            gas = int(tx.get('gas', '0')) if tx.get('gas') else 0
            gas_price = int(tx.get('gasPrice', '0')) if tx.get('gasPrice') else 0
            block_number = int(tx.get('blockNumber', '0')) if tx.get('blockNumber') else 0
            timestamp = int(tx.get('timeStamp', '0')) if tx.get('timeStamp') else 0
            
            # Convert timestamp to ISO format
            block_timestamp = datetime.fromtimestamp(timestamp, tz = timezone.utc).isoformat() if timestamp else ''
            
            cleaned.append({
                'tx_hash': tx.get('hash', ''),
                'from_address': tx.get('from', ''),
                'to_address': tx.get('to', ''),
                'value': tx.get('value', '0'),  # In Wei (1 ETH = 10^18 Wei)
                'gas': gas,
                'gas_price': gas_price,
                'block_number': block_number,
                'block_timestamp': block_timestamp,
                'nonce': tx.get('nonce', ''),
                'is_contract_creation': 1 if (tx.get('input') and tx.get('input') != '0x') else 0
            })
        except Exception as e:
            print(f"⚠️  Skipping malformed transaction: {e}")
            continue
    
    return cleaned
 
def transform_token_transfers(raw_logs):
    """
    Convert raw Etherscan logs to token transfer schema
    """
    cleaned = []
    
    for tx in raw_logs:
        try:
            timestamp = int(tx.get('timeStamp', '0')) if tx.get('timeStamp') else 0 
            block_timestamp = datetime.fromtimestamp(timestamp, tz = timezone.utc).isoformat() if timestamp else ''
            
            cleaned.append({
                'tx_hash': tx.get('hash', ''),
                'block_number': int(tx.get('blockNumber', 0)),
                'block_timestamp': block_timestamp,
                'token_address': tx.get('contractAddress', ''),
                'token_name': tx.get('tokenName', ''),
                'token_symbol': tx.get('tokenSymbol', ''),
                'token_decimal': int(tx.get('tokenDecimal', 18)),
                'from_address': tx.get('from', ''),
                'to_address': tx.get('to', ''),
                'value': tx.get('value', '0'),  # Raw transfer amount
            })
        except Exception as e:
            print(f"⚠️  Skipping malformed log: {e}")
            continue
    
    return cleaned
 

# EXPORT TO CSV

def save_to_csv(data, filename):
    """Save cleaned data to CSV file"""
    if not data:
        print(f"⚠️  No data to save for {filename}")
        return
    
    df = pd.DataFrame(data)
    filepath = f"{OUTPUT_DIR}{filename}"
    df.to_csv(filepath, index = False)
    print(f"✓ Saved {len(df)} rows to {filepath}")
 

# MAIN EXECUTION
 
def main():
    print("ETHERSCAN V2 API DATA DOWNLOADER")
    print()
    
    # Create output directory
    import os
    os.makedirs(OUTPUT_DIR, exist_ok = True)
    
    # Step 1: Download and process transactions
    print("STEP 1: TRANSACTIONS")
    raw_transactions = download_transactions()
    if raw_transactions:
        clean_tx = transform_transactions(raw_transactions)
        save_to_csv(clean_tx, "transactions_1.csv")
        print(f"📊 Transaction schema: tx_hash, from_address, to_address, value (Wei), gas, gas_price, block_number, block_timestamp, nonce, is_contract_creation")
    else:
        print("⚠️  No transactions downloaded")
    
    # Rate limit: Etherscan free tier allows 5 calls/sec
    time.sleep(1)
    
    # Step 2: Download and process token transfers
    print("\nSTEP 2: TOKEN TRANSFERS")
    raw_transfers = download_token_transfers()
    if raw_transfers:
        clean_transfers = transform_token_transfers(raw_transfers)
        save_to_csv(clean_transfers, "token_transfers_2.csv")
        print(f"📊 Token transfer schema: tx_hash, token_address, from_address, to_address, value (Wei), block_timestamp")
    else:
        print("⚠️  No token transfers downloaded")
    
    print("\n✅ DOWNLOAD COMPLETE!")
    print(f"📁 Files saved to: {OUTPUT_DIR}")
    print(f"   - transactions.csv ({len(raw_transactions) if raw_transactions else 0} rows)")
    print(f"   - token_transfers_2.csv ({len(raw_transfers) if raw_transfers else 0} rows)")
 
if __name__ == "__main__":
    main()
 