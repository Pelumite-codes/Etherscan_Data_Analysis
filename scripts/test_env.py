import os
from dotenv import load_dotenv

load_dotenv()
api_key = os.getenv("ETHERSCAN_API_KEY")

print(f"Found Key: {api_key[:6]}..." if api_key else "None (Check .env filename or path)")
