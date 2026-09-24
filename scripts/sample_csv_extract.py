import pandas as pd

pd.read_csv('./etherscan_data/transactions_1.csv', nrows = 100).to_csv('./etherscan_data/sample_transactions.csv', index = False)

pd.read_csv('./etherscan_data/token_transfers_2.csv', nrows = 100).to_csv('./etherscan_data/sample_token_transfers.csv', index = False)