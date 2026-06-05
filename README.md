# KalshiPowerShell — PowerShell 7+ Module for the Kalshi API

A complete PowerShell 7+ client for the [Kalshi](https://kalshi.com) prediction market trading API. Supports all exchange, market, order, and portfolio GET endpoints, plus V2 order creation, amendment, and cancellation with RSA-PSS/SHA256 authentication.

## Requirements

- PowerShell 7.0+ (.NET 6+)
- A Kalshi account with API key (generate at kalshi.com → Account → API Keys)
- Your RSA private key file (`.key` PEM file)

## Installation

```powershell
# Clone or copy the KalshiPowerShell folder to your modules path
# Or import directly from the source directory:
Import-Module /path/to/KalshiPowerShell -Force
```

## Quick Start

```powershell
# 1. Import the module
Import-Module ./KalshiPowerShell

# 2. Set your credentials (production or demo)
Set-KalshiCredentials -ApiKeyId 'your-api-key-id' -PrivateKeyPath './kalshi-key.key' -Environment prod

# 3. Check exchange status (public, no auth needed)
Get-KalshiExchangeStatus

# 4. Check your balance
Get-KalshiBalance

# 5. Browse open markets
Get-KalshiMarkets -Status open -Limit 10

# 6. Place a limit order (buy YES on a market)
$order = New-KalshiOrder -Ticker 'HIGHINFLATION-24JAN01-T60' -Side bid -Count 10 -Price 0.55
$order.order_id

# 7. View your open orders
Get-KalshiOrders -Status resting

# 8. Cancel an order
Remove-KalshiOrder -OrderId $order.order_id
```

## Demo Environment

```powershell
Set-KalshiCredentials -ApiKeyId 'your-demo-key' -PrivateKeyPath './kalshi-demo.key' -Environment demo
```

## All Functions

### Credentials
| Function | Description |
|----------|-------------|
| `Set-KalshiCredentials` | Configure API key ID, private key, and environment |
| `Test-KalshiCredentials` | Check if credentials are configured |

### Exchange (some public, no auth needed)
| Function | Description | Auth Required |
|----------|-------------|:---:|
| `Get-KalshiExchangeStatus` | Exchange and trading status | No |
| `Get-KalshiExchangeAnnouncements` | Exchange announcements | No |
| `Get-KalshiExchangeSchedule` | Trading hours/schedule | No |
| `Get-KalshiSeriesFeeChanges` | Fee structure overrides | No |
| `Get-KalshiUserDataTimestamp` | Last data refresh timestamp | Yes |

### Markets
| Function | Description | Auth |
|----------|-------------|:---:|
| `Get-KalshiMarkets` | List markets with filters (status, ticker, event, series) | No |
| `Get-KalshiMarket` | Get a single market by ticker | No |
| `Get-KalshiMarketCandlesticks` | Price candlesticks (1m/1h/1d) | No |
| `Get-KalshiTrades` | All trades across markets | No |
| `Get-KalshiSeries` | Get a series definition | No |
| `Get-KalshiSeriesList` | List available series | No |
| `Get-KalshiOrderbook` | Get orderbook for a market (depth optional) | Yes |
| `Get-KalshiMultipleOrderbooks` | Batch orderbook for multiple markets | Yes |

### Orders (V2)
| Function | Description |
|----------|-------------|
| `New-KalshiOrder` | Create an order (bid/ask, fixed-point price) |
| `Get-KalshiOrders` | List orders with status/ticker/time filters |
| `Get-KalshiOrder` | Get a single order by ID |
| `Remove-KalshiOrder` | Cancel an order |
| `Edit-KalshiOrder` | Amend order price and/or count |

### Portfolio
| Function | Description |
|----------|-------------|
| `Get-KalshiBalance` | Balance and portfolio value |
| `Get-KalshiAllSubaccountBalances` | Balances for all subaccounts |
| `Get-KalshiPositions` | Current positions with filters |
| `Get-KalshiFills` | Completed trade fills |
| `Get-KalshiSettlements` | Settlement history |

## Authentication

Kalshi uses **RSA-PSS with SHA256** signing:
1. Concatenate `timestamp + HTTP_METHOD + path` (path without query string)
2. Sign with your RSA private key using RSA-PSS/SHA256
3. Base64-encode the signature
4. Send in headers: `KALSHI-ACCESS-KEY`, `KALSHI-ACCESS-TIMESTAMP`, `KALSHI-ACCESS-SIGNATURE`

The module handles all signing automatically.

## Creating Orders (V2)

The V2 endpoint (`/portfolio/events/orders`) uses single-book bid/ask:
- `bid` = buy YES contracts
- `ask` = sell YES contracts (equivalent to buying NO at 1 - price)

### Order Parameters

```powershell
New-KalshiOrder -Ticker 'HIGHINFLATION-24JAN01-T60' `
    -Side bid `
    -Count 10 `
    -Price 0.55 `
    -TimeInForce good_till_canceled `
    -PostOnly `
    -ClientOrderId 'my-ref-001'
```

Optional: `ExpirationTime`, `CancelOrderOnPause`, `ReduceOnly`, `OrderGroupId`, `SelfTradePreventionType`

## Running Tests

```powershell
Import-Module ./KalshiPowerShell -Force
Invoke-Pester -Path ./KalshiPowerShell.Tests.ps1 -Output Detailed
```

## API Reference

Full Kalshi API documentation: https://docs.kalshi.com/api-reference

## File Structure

```
KalshiPowerShell/
  KalshiPowerShell.psd1   — Module manifest
  KalshiPowerShell.psm1   — Module implementation
KalshiPowerShell.Tests.ps1 — Pester unit tests (42 tests)
```

## License

MIT
