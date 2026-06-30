const Map<String, dynamic> paymentDetailsJson =
{
  "id": "pl_beeddb41cd4b6d9e",
  "externalId": "TestfürAlle",
  "mode": "Multiple",
  "tag": "payRequest",
  "callback": "https://api.dfx.swiss/v1/lnurlp/cb/pl_beeddb41cd4b6d9e",
  "minSendable": 1985000,
  "maxSendable": 1985000,
  "metadata": "[[\"text/plain\", \"Test Shop - CHF 1\"]]",
  "displayName": "Test Shop",
  "standard": "OpenCryptoPay",
  "possibleStandards": [
    "OpenCryptoPay"
  ],
  "displayQr": true,
  "recipient": {
    "name": "hier könnte Viktor stehen",
    "address": {
      "street": "Bahnhofstrasse",
      "houseNumber": "7",
      "city": "Zug",
      "zip": "6300",
      "country": "CH"
    },
    "phone": "+41792684224",
    "mail": "mail@ammer.group",
    "website": "https://ammer.group/",
    "registrationNumber": "CHE-429.856.521",
    "storeType": "Physical",
    "merchantCategory": "RetailTradeOthers",
    "goodsType": "Tangible",
    "goodsCategory": "FoodGroceryHealthProducts"
  },
  "route": "VM 01",
  "quote": {
    "id": "plq_62b1865ed28358be",
    "expiration": "2026-06-24T08:37:49.704Z",
    "payment": "plp_f1ba466e2f1c0a4e"
  },
  "requestedAmount": {
    "asset": "CHF",
    "amount": 1
  },
  "transferAmounts": [
    {
      "method": "Lightning",
      "minFee": 0,
      "assets": [
        {
          "asset": "BTC",
          "amount": "0.00001985"
        }
      ],
      "available": true
    },
    {
      "method": "Polygon",
      "minFee": 338028026700,
      "assets": [
        {
          "asset": "dEURO",
          "amount": "1.0968538"
        },
        {
          "asset": "ZCHF",
          "amount": "1."
        },
        {
          "asset": "USDT",
          "amount": "1.244696"
        },
        {
          "asset": "USDC",
          "amount": "1.244671"
        },
        {
          "asset": "POL",
          "amount": "16.21572727"
        },
        {
          "asset": "WBTC",
          "amount": "0.00001985"
        }
      ],
      "available": true
    },
    {
      "method": "Arbitrum",
      "minFee": 24480000,
      "assets": [
        {
          "asset": "dEURO",
          "amount": "1.0968538"
        },
        {
          "asset": "USDT",
          "amount": "1.244696"
        },
        {
          "asset": "USDC",
          "amount": "1.244671"
        },
        {
          "asset": "ETH",
          "amount": "0.00074522"
        },
        {
          "asset": "WBTC",
          "amount": "0.00001985"
        }
      ],
      "available": true
    },
    {
      "method": "Optimism",
      "minFee": 1200399,
      "assets": [
        {
          "asset": "dEURO",
          "amount": "1.0968538"
        },
        {
          "asset": "USDT",
          "amount": "1.244696"
        },
        {
          "asset": "USDC",
          "amount": "1.244671"
        },
        {
          "asset": "WBTC",
          "amount": "0.00001985"
        },
        {
          "asset": "ETH",
          "amount": "0.00074522"
        }
      ],
      "available": true
    },
    {
      "method": "Base",
      "minFee": 7200000,
      "assets": [
        {
          "asset": "dEURO",
          "amount": "1.0968538"
        },
        {
          "asset": "USDC",
          "amount": "1.244671"
        },
        {
          "asset": "ETH",
          "amount": "0.00074522"
        }
      ],
      "available": true
    },
    {
      "method": "Ethereum",
      "minFee": 98965874,
      "assets": [
        {
          "asset": "dEURO",
          "amount": "1.0968538"
        },
        {
          "asset": "ZCHF",
          "amount": "1."
        },
        {
          "asset": "USDT",
          "amount": "1.244696"
        },
        {
          "asset": "USDC",
          "amount": "1.244671"
        },
        {
          "asset": "ETH",
          "amount": "0.00074522"
        },
        {
          "asset": "WBTC",
          "amount": "0.00001985"
        }
      ],
      "available": true
    },
    {
      "method": "BinanceSmartChain",
      "minFee": 7000000000,
      "assets": [
        {
          "asset": "USDT",
          "amount": "1.24469577"
        },
        {
          "asset": "USDC",
          "amount": "1.24467084"
        },
        {
          "asset": "BNB",
          "amount": "0.00215709"
        }
      ],
      "available": true
    },
    {
      "method": "Bitcoin",
      "minFee": 2.146,
      "assets": [
        {
          "asset": "BTC",
          "amount": "0.00001985"
        }
      ],
      "available": true
    },
    {
      "method": "Firo",
      "minFee": 2.008,
      "assets": [
        {
          "asset": "FIRO",
          "amount": "1.81435207"
        }
      ],
      "available": true
    },
    {
      "method": "Monero",
      "minFee": 0,
      "assets": [
        {
          "asset": "XMR",
          "amount": "0.00381648"
        }
      ],
      "available": true
    },
    {
      "method": "Zano",
      "minFee": 0,
      "assets": [
        {
          "asset": "ZANO",
          "amount": "0.12962098"
        }
      ],
      "available": true
    },
    {
      "method": "Solana",
      "minFee": 0,
      "assets": [
        {
          "asset": "USDT",
          "amount": "1.244696"
        },
        {
          "asset": "USDC",
          "amount": "1.244671"
        },
        {
          "asset": "SOL",
          "amount": "0.01793745"
        }
      ],
      "available": true
    },
    {
      "method": "Tron",
      "minFee": 0,
      "assets": [
        {
          "asset": "USDT",
          "amount": "1.244696"
        },
        {
          "asset": "TRX",
          "amount": "3.780267"
        }
      ],
      "available": true
    },
    {
      "method": "Cardano",
      "minFee": 0,
      "assets": [
        {
          "asset": "ADA",
          "amount": "8.257978"
        }
      ],
      "available": true
    },
    {
      "method": "InternetComputer",
      "minFee": 0,
      "assets": [
        {
          "asset": "VEUR",
          "amount": "1.0968538"
        },
        {
          "asset": "ckBTC",
          "amount": "0.00001985"
        },
        {
          "asset": "VCHF",
          "amount": "1."
        },
        {
          "asset": "ICP",
          "amount": "0.5702134"
        }
      ],
      "available": true
    },
    {
      "method": "BinancePay",
      "minFee": 0,
      "assets": [
        {
          "asset": "USDT",
          "amount": "1.24469577"
        }
      ],
      "available": true
    },
    {
      "method": "TaprootAsset",
      "minFee": 0,
      "assets": [],
      "available": false
    },
    {
      "method": "Spark",
      "minFee": 0,
      "assets": [],
      "available": false
    },
    {
      "method": "Arkade",
      "minFee": 0,
      "assets": [],
      "available": false
    }
  ]
};



