# KalshiPowerShell.psm1 - Kalshi Trading API Client for PowerShell 7+
#
# A complete PowerShell module for the Kalshi prediction market API.
# Supports exchange, market, order, and portfolio operations.
#
# Requirements: PowerShell 7+, .NET 8+
# Authentication: RSA-PSS/SHA256 (Kalshi API key pair required for private endpoints)

using namespace System.Security.Cryptography
using namespace System.Text

# ─── Module Globals ───────────────────────────────────────────────────────────

$Script:DefaultBaseUrl  = 'https://external-api.kalshi.com/trade-api/v2'
$Script:DefaultApiKeyId = $null
$Script:DefaultRsaKey   = $null   # RSACng object
$Script:DefaultSubaccount = 0

# ─── Helper Functions (internal) ─────────────────────────────────────────────

<#
.SYNOPSIS
    Load an RSA private key from a PEM file path or a raw PEM string.
#>
function Import-KalshiPrivateKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$KeyString,

        [switch]$IsFilePath
    )

    $pem = if ($IsFilePath) {
        if (-not (Test-Path $KeyString)) { throw "Key file not found: $KeyString" }
        Get-Content -Path $KeyString -Raw
    } else {
        $KeyString
    }

    # Parse PEM and import the RSA private key
    # Supports PKCS#1 (BEGIN RSA PRIVATE KEY) and PKCS#8 (BEGIN PRIVATE KEY) formats
    $rsa = [System.Security.Cryptography.RSA]::Create()

    try {
        $rsa.ImportFromPem($pem.ToCharArray())
    } catch {
        # Fallback for environments/storage layers where PEM gets modified
        $b64 = $pem -replace '[^A-Za-z0-9+/=]', ''
        $raw = [Convert]::FromBase64String($b64)
        try {
            $rsa.ImportRSAPrivateKey($raw, [ref]0)
        } catch {
            $rsa.ImportPkcs8PrivateKey($raw, [ref]0)
        }
    }

    return $rsa
}

<#
.SYNOPSIS
    Create the RSA-PSS/SHA256 signature required for Kalshi authentication.
#>
function New-KalshiSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [long]$TimestampMs,
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Path,        # full path from root (e.g. /trade-api/v2/portfolio/balance)
        [Parameter(Mandatory)] [System.Security.Cryptography.RSA]$RsaKey
    )

    # Strip query string — Kalshi signs the path without query parameters
    $pathOnly = $Path -replace '\?.*', ''
    $message = "${TimestampMs}${Method}${pathOnly}"
    $data = [Encoding]::UTF8.GetBytes($message)

    $sig = $RsaKey.SignData(
        $data,
        [HashAlgorithmName]::SHA256,
        [RSASignaturePadding]::Pss
    )
    return [Convert]::ToBase64String($sig)
}

<#
.SYNOPSIS
    Create authentication headers for a Kalshi API request.
#>
function New-KalshiAuthHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Path,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey
    )

    $apiKeyId = Choose-Value $ApiKeyId $Script:DefaultApiKeyId
    $rsaKey   = Choose-Value $RsaKey   $Script:DefaultRsaKey

    if (-not $apiKeyId) { throw "No API key ID configured. Use Set-KalshiCredentials or pass -ApiKeyId." }
    if (-not $rsaKey)   { throw "No RSA key configured. Use Set-KalshiCredentials or pass -RsaKey." }

    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $sig = New-KalshiSignature -TimestampMs $ts -Method $Method -Path $Path -RsaKey $rsaKey

    return @{
        'KALSHI-ACCESS-KEY'       = $apiKeyId
        'KALSHI-ACCESS-TIMESTAMP' = "$ts"
        'KALSHI-ACCESS-SIGNATURE' = $sig
    }
}

<#
.SYNOPSIS
    Helper to pick the first non-null value (parameter override vs global default).
#>
function Choose-Value {
    param($UserVal, $DefaultVal)
    if ($null -ne $UserVal -and ($UserVal -is [string] -and $UserVal -ne '') -or ($UserVal -isnot [string] -and $null -ne $UserVal)) {
        return $UserVal
    }
    return $DefaultVal
}

<#
.SYNOPSIS
    Internal GET request builder.
#>
function Invoke-KalshiGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1,
        [int]$TimeoutSec = 30
    )

    $baseUrl = Choose-Value $BaseUrl $Script:DefaultBaseUrl
    $headers = @{}
    $query   = @()

    if ($Subaccount -ge 0) { $query += "subaccount=$Subaccount" }

    # Only add auth headers if we have credentials (some endpoints are public)
    $ak = Choose-Value $ApiKeyId $Script:DefaultApiKeyId
    $rk = Choose-Value $RsaKey   $Script:DefaultRsaKey
    if ($ak -and $rk) {
        $headers = New-KalshiAuthHeaders -Method 'GET' -Path $Path -ApiKeyId $ak -RsaKey $rk
    }

    $fullUrl = $baseUrl + $Path
    if ($query.Count -gt 0) { $fullUrl += '?' + ($query -join '&') }

    Write-Verbose "GET $fullUrl"
    return Invoke-RestMethod -Uri $fullUrl -Method Get -Headers $headers -TimeoutSec $TimeoutSec
}

<#
.SYNOPSIS
    Internal POST request builder.
#>
function Invoke-KalshiPost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [object]$Body,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1,
        [int]$TimeoutSec = 30
    )

    $baseUrl = Choose-Value $BaseUrl $Script:DefaultBaseUrl
    $headers = New-KalshiAuthHeaders -Method 'POST' -Path $Path -ApiKeyId $ApiKeyId -RsaKey $RsaKey
    $headers['Content-Type'] = 'application/json'

    $fullUrl = $baseUrl + $Path
    if ($Subaccount -ge 0) { $fullUrl += "?subaccount=$Subaccount" }

    $jsonBody = $Body | ConvertTo-Json -Compress -Depth 10

    Write-Verbose "POST $fullUrl"
    return Invoke-RestMethod -Uri $fullUrl -Method Post -Headers $headers -Body $jsonBody -TimeoutSec $TimeoutSec
}

<#
.SYNOPSIS
    Internal DELETE request builder.
#>
function Invoke-KalshiDelete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1,
        [int]$TimeoutSec = 30
    )

    $baseUrl = Choose-Value $BaseUrl $Script:DefaultBaseUrl
    $headers = New-KalshiAuthHeaders -Method 'DELETE' -Path $Path -ApiKeyId $ApiKeyId -RsaKey $RsaKey

    $fullUrl = $baseUrl + $Path
    $query = @()
    if ($Subaccount -ge 0) { $query += "subaccount=$Subaccount" }
    if ($query.Count -gt 0) { $fullUrl += '?' + ($query -join '&') }

    Write-Verbose "DELETE $fullUrl"
    return Invoke-RestMethod -Uri $fullUrl -Method Delete -Headers $headers -TimeoutSec $TimeoutSec
}

# ─── Public Module Functions ─────────────────────────────────────────────────

<#
.SYNOPSIS
    Configure Kalshi API credentials and environment.

.DESCRIPTION
    Set your Kalshi API key ID and private RSA key for authenticated requests.
    Accepts a PEM string or path to a .key file. Optionally switch between
    production (default) and demo environments.

.EXAMPLE
    Set-KalshiCredentials -ApiKeyId 'a952bcbe-...' -PrivateKeyPath '/home/user/kalshi.key'

.EXAMPLE
    Set-KalshiCredentials -ApiKeyId 'abc123' -PrivateKey (Get-Content key.pem -Raw) -Environment demo
#>
function Set-KalshiCredentials {
    [CmdletBinding(DefaultParameterSetName = 'FilePath')]
    param(
        [Parameter(Mandatory)] [string]$ApiKeyId,
        [Parameter(ParameterSetName = 'FilePath', Mandatory)] [string]$PrivateKeyPath,
        [Parameter(ParameterSetName = 'KeyString', Mandatory)] [string]$PrivateKey,
        [ValidateSet('prod', 'demo')] [string]$Environment = 'prod',
        [int]$DefaultSubaccount = 0
    )

    $Script:DefaultApiKeyId = $ApiKeyId

    if ($PSCmdlet.ParameterSetName -eq 'FilePath') {
        $Script:DefaultRsaKey = Import-KalshiPrivateKey -KeyString $PrivateKeyPath -IsFilePath
    } else {
        $Script:DefaultRsaKey = Import-KalshiPrivateKey -KeyString $PrivateKey
    }

    $Script:DefaultSubaccount = $DefaultSubaccount

    if ($Environment -eq 'demo') {
        $Script:DefaultBaseUrl = 'https://external-api.demo.kalshi.co/trade-api/v2'
    } else {
        $Script:DefaultBaseUrl = 'https://external-api.kalshi.com/trade-api/v2'
    }

    Write-Output "Kalshi credentials configured. Environment: $Environment"
}

<#
.SYNOPSIS
    Test if Kalshi credentials are configured.
#>
function Test-KalshiCredentials {
    [CmdletBinding()]
    param()

    $configured = ($null -ne $Script:DefaultApiKeyId -and $Script:DefaultApiKeyId -ne '' -and $null -ne $Script:DefaultRsaKey)
    if (-not $configured) {
        Write-Warning "Kalshi credentials not configured. Use Set-KalshiCredentials."
        return $false
    }
    return $true
}

# ═══════════════════════════════════════════════════════════════════════════════
# EXCHANGE ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Get Kalshi exchange status.

.DESCRIPTION
    Returns whether the exchange is active and whether trading is active.
    Public endpoint — no authentication required.

.EXAMPLE
    Get-KalshiExchangeStatus
#>
function Get-KalshiExchangeStatus {
    [CmdletBinding()]
    param(
        [string]$BaseUrl
    )
    return Invoke-KalshiGet -Path '/exchange/status' -BaseUrl $BaseUrl
}

<#
.SYNOPSIS
    Get Kalshi exchange announcements.

.EXAMPLE
    Get-KalshiExchangeAnnouncements
#>
function Get-KalshiExchangeAnnouncements {
    [CmdletBinding()]
    param(
        [string]$BaseUrl
    )
    return Invoke-KalshiGet -Path '/exchange/announcements' -BaseUrl $BaseUrl
}

<#
.SYNOPSIS
    Get Kalshi exchange schedule (trading hours).

.EXAMPLE
    Get-KalshiExchangeSchedule
#>
function Get-KalshiExchangeSchedule {
    [CmdletBinding()]
    param(
        [string]$BaseUrl
    )
    return Invoke-KalshiGet -Path '/exchange/schedule' -BaseUrl $BaseUrl
}

<#
.SYNOPSIS
    Get Kalshi series fee changes.

.EXAMPLE
    Get-KalshiSeriesFeeChanges
#>
function Get-KalshiSeriesFeeChanges {
    [CmdletBinding()]
    param(
        [string]$BaseUrl
    )
    return Invoke-KalshiGet -Path '/exchange/series/fee_changes' -BaseUrl $BaseUrl
}

<#
.SYNOPSIS
    Get the user data timestamp (approximate delay indicator).

.EXAMPLE
    Get-KalshiUserDataTimestamp
#>
function Get-KalshiUserDataTimestamp {
    [CmdletBinding()]
    param(
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl
    )
    return Invoke-KalshiGet -Path '/exchange/user_data_timestamp' -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl
}

# ═══════════════════════════════════════════════════════════════════════════════
# MARKET ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Get a list of markets with optional filters.

.EXAMPLE
    Get-KalshiMarkets -Status open -Limit 50

.EXAMPLE
    Get-KalshiMarkets -EventTicker 'HIGHINFLATION-24JAN01'

.EXAMPLE
    Get-KalshiMarkets -Tickers 'HIGHINFLATION-24JAN01-T60','HIGHINFLATION-24JAN01-T70'
#>
function Get-KalshiMarkets {
    [CmdletBinding()]
    param(
        [ValidateSet('unopened', 'open', 'paused', 'closed', 'settled')] [string]$Status,
        [string]$EventTicker,
        [string]$SeriesTicker,
        [string[]]$Tickers,
        [int]$Limit = 100,
        [string]$Cursor,
        [ValidateSet('only', 'exclude')] [string]$MveFilter,
        [string]$BaseUrl
    )

    $query = @()
    if ($Status)        { $query += "status=$Status" }
    if ($EventTicker)   { $query += "event_ticker=$( [uri]::EscapeDataString($EventTicker) )" }
    if ($SeriesTicker)  { $query += "series_ticker=$( [uri]::EscapeDataString($SeriesTicker) )" }
    if ($Tickers)       { $query += "tickers=$( $Tickers -join ',' )" }
    if ($Limit -ne 100) { $query += "limit=$Limit" }
    if ($Cursor)        { $query += "cursor=$( [uri]::EscapeDataString($Cursor) )" }
    if ($MveFilter)     { $query += "mve_filter=$MveFilter" }

    $path = '/markets'
    if ($query.Count -gt 0) { $path += '?' + ($query -join '&') }

    return Invoke-KalshiGet -Path $path -BaseUrl $BaseUrl
}

<#
.SYNOPSIS
    Get details for a specific market by ticker.

.EXAMPLE
    Get-KalshiMarket -Ticker 'HIGHINFLATION-24JAN01-T60'
#>
function Get-KalshiMarket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Ticker,
        [string]$BaseUrl
    )
    $path = "/markets/$( [uri]::EscapeDataString($Ticker) )"
    return Invoke-KalshiGet -Path $path -BaseUrl $BaseUrl
}

<#
.SYNOPSIS
    Get the orderbook for a specific market.

.DESCRIPTION
    Returns yes bids and no bids (no asks — in binary markets, a no bid at X is
    equivalent to an ask at 1-X). Requires authentication. Use -Depth to limit
    levels (0 or negative = all levels, 1-100 for specific depth).

.EXAMPLE
    Get-KalshiOrderbook -Ticker 'HIGHINFLATION-24JAN01-T60' -Depth 5
#>
function Get-KalshiOrderbook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Ticker,
        [ValidateRange(0, 100)] [int]$Depth = 0,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1
    )

    $path = "/markets/$( [uri]::EscapeDataString($Ticker) )/orderbook"
    $query = @()
    if ($Depth -ne 0) { $query += "depth=$Depth" }
    if ($query.Count -gt 0) { $path += '?' + ($query -join '&') }

    return Invoke-KalshiGet -Path $path -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

<#
.SYNOPSIS
    Get orderbooks for multiple markets in one request.

.EXAMPLE
    Get-KalshiMultipleOrderbooks -Tickers 'HIGHINFLATION-24JAN01-T60','HIGHINFLATION-24JAN01-T70'
#>
function Get-KalshiMultipleOrderbooks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]]$Tickers,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1
    )

    $path = '/markets/multiple/orderbooks'
    return Invoke-KalshiPost -Path $path -Body @{ tickers = $Tickers } -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

<#
.SYNOPSIS
    Get candlesticks for a market.

.PARAMETER Period
    1 = 1 minute, 60 = 1 hour, 1440 = 1 day

.EXAMPLE
    Get-KalshiMarketCandlesticks -Ticker 'HIGHINFLATION-24JAN01-T60' -Period 60 -Limit 24
#>
function Get-KalshiMarketCandlesticks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Ticker,
        [ValidateSet(1, 60, 1440)] [int]$Period = 60,
        [int]$Limit = 100,
        [string]$Cursor,
        [int]$MinTs,
        [int]$MaxTs,
        [string]$BaseUrl
    )

    $query = @("period=$Period")
    if ($Limit -ne 100) { $query += "limit=$Limit" }
    if ($Cursor)        { $query += "cursor=$( [uri]::EscapeDataString($Cursor) )" }
    if ($MinTs)         { $query += "min_ts=$MinTs" }
    if ($MaxTs)         { $query += "max_ts=$MaxTs" }

    $path = "/markets/$( [uri]::EscapeDataString($Ticker) )/candlesticks?" + ($query -join '&')
    return Invoke-KalshiGet -Path $path -BaseUrl $BaseUrl
}

<#
.SYNOPSIS
    Get all trades across markets (public).

.EXAMPLE
    Get-KalshiTrades -Ticker 'HIGHINFLATION-24JAN01-T60' -Limit 200
#>
function Get-KalshiTrades {
    [CmdletBinding()]
    param(
        [string]$Ticker,
        [int]$Limit = 100,
        [string]$Cursor,
        [int]$MinTs,
        [int]$MaxTs,
        [Nullable[bool]]$IsBlockTrade,
        [string]$BaseUrl
    )

    $query = @()
    if ($Ticker)       { $query += "ticker=$( [uri]::EscapeDataString($Ticker) )" }
    if ($Limit -ne 100){ $query += "limit=$Limit" }
    if ($Cursor)       { $query += "cursor=$( [uri]::EscapeDataString($Cursor) )" }
    if ($MinTs)        { $query += "min_ts=$MinTs" }
    if ($MaxTs)        { $query += "max_ts=$MaxTs" }
    if ($null -ne $IsBlockTrade) { $query += "is_block_trade=$( $IsBlockTrade.ToString().ToLower() )" }

    $path = '/markets/trades'
    if ($query.Count -gt 0) { $path += '?' + ($query -join '&') }
    return Invoke-KalshiGet -Path $path -BaseUrl $BaseUrl
}

<#
.SYNOPSIS
    Get a series definition by ticker.

.EXAMPLE
    Get-KalshiSeries -Ticker 'HIGHINFLATION'
#>
function Get-KalshiSeries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Ticker,
        [switch]$IncludeVolume,
        [string]$BaseUrl
    )
    $path = "/series/$( [uri]::EscapeDataString($Ticker) )"
    if ($IncludeVolume) { $path += '?include_volume=true' }
    return Invoke-KalshiGet -Path $path -BaseUrl $BaseUrl
}

<#
.SYNOPSIS
    List available series with optional filters.

.EXAMPLE
    Get-KalshiSeriesList -Category 'Economic'
#>
function Get-KalshiSeriesList {
    [CmdletBinding()]
    param(
        [string]$Category,
        [string]$Tags,
        [switch]$IncludeVolume,
        [switch]$IncludeProductMetadata,
        [string]$BaseUrl
    )
    $query = @()
    if ($Category)              { $query += "category=$( [uri]::EscapeDataString($Category) )" }
    if ($Tags)                  { $query += "tags=$( [uri]::EscapeDataString($Tags) )" }
    if ($IncludeVolume)         { $query += "include_volume=true" }
    if ($IncludeProductMetadata){ $query += "include_product_metadata=true" }

    $path = '/series'
    if ($query.Count -gt 0) { $path += '?' + ($query -join '&') }
    return Invoke-KalshiGet -Path $path -BaseUrl $BaseUrl
}

# ═══════════════════════════════════════════════════════════════════════════════
# ORDER ENDPOINTS (V2)
# ═══════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Create a new order on Kalshi (V2).

.DESCRIPTION
    Submits an event-market order using the V2 endpoint. Uses single-book bid/ask
    side with fixed-point dollar prices.
    - side: 'bid' = buy YES, 'ask' = sell YES
    - To buy NO, use 'bid' with price = 1 - <desired_no_price>

.EXAMPLE
    $order = New-KalshiOrder -Ticker 'HIGHINFLATION-24JAN01-T60' -Side bid -Count 10 -Price 0.55
#>
function New-KalshiOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Ticker,
        [Parameter(Mandatory)] [ValidateSet('bid', 'ask')] [string]$Side,
        [Parameter(Mandatory)] [string]$Count,
        [Parameter(Mandatory)] [string]$Price,
        [string]$ClientOrderId,
        [ValidateSet('good_till_canceled', 'fill_or_kill', 'immediate_or_cancel')] [string]$TimeInForce,
        [int]$ExpirationTime,
        [string]$SelfTradePreventionType,
        [switch]$PostOnly,
        [switch]$CancelOrderOnPause,
        [switch]$ReduceOnly,
        [string]$OrderGroupId,
        [int]$ExchangeIndex = 0,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1
    )

    $body = @{
        ticker = $Ticker
        side   = $Side
        count  = "$Count"
        price  = "$Price"
    }

    if ($ClientOrderId)           { $body.client_order_id           = $ClientOrderId }
    if ($TimeInForce)             { $body.time_in_force             = $TimeInForce }
    if ($ExpirationTime -gt 0)    { $body.expiration_time           = $ExpirationTime }
    if ($SelfTradePreventionType) { $body.self_trade_prevention_type = $SelfTradePreventionType }
    if ($PostOnly)                { $body.post_only                 = $true }
    if ($CancelOrderOnPause)      { $body.cancel_order_on_pause     = $true }
    if ($ReduceOnly)              { $body.reduce_only               = $true }
    if ($OrderGroupId)            { $body.order_group_id            = $OrderGroupId }
    if ($ExchangeIndex -ne 0)     { $body.exchange_index            = $ExchangeIndex }

    return Invoke-KalshiPost -Path '/portfolio/events/orders' -Body $body -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

<#
.SYNOPSIS
    Get orders with optional filters.

.DESCRIPTION
    Retrieves orders filtered by status (resting, canceled, executed).
    Canceled/executed orders older than the historical cutoff are only
    available via the historical endpoint.

.EXAMPLE
    Get-KalshiOrders -Status resting -Limit 50

.EXAMPLE
    Get-KalshiOrders -Ticker 'HIGHINFLATION-24JAN01-T60'
#>
function Get-KalshiOrders {
    [CmdletBinding()]
    param(
        [ValidateSet('resting', 'canceled', 'executed')] [string]$Status,
        [string]$Ticker,
        [string[]]$EventTicker,
        [int]$MinTs,
        [int]$MaxTs,
        [int]$Limit = 100,
        [string]$Cursor,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1
    )

    $query = @()
    if ($Status)         { $query += "status=$Status" }
    if ($Ticker)         { $query += "ticker=$( [uri]::EscapeDataString($Ticker) )" }
    if ($EventTicker)    { $query += "event_ticker=$( $EventTicker -join ',' )" }
    if ($MinTs)          { $query += "min_ts=$MinTs" }
    if ($MaxTs)          { $query += "max_ts=$MaxTs" }
    if ($Limit -ne 100)  { $query += "limit=$Limit" }
    if ($Cursor)         { $query += "cursor=$( [uri]::EscapeDataString($Cursor) )" }

    $path = '/portfolio/orders'
    if ($query.Count -gt 0) { $path += '?' + ($query -join '&') }

    return Invoke-KalshiGet -Path $path -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

<#
.SYNOPSIS
    Get a single order by its order ID.

.EXAMPLE
    Get-KalshiOrder -OrderId '3b23c1c7-f4ef-4f0d-8b9a-9e53c61f1a0d'
#>
function Get-KalshiOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$OrderId,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1
    )

    $path = "/portfolio/orders/$( [uri]::EscapeDataString($OrderId) )"
    return Invoke-KalshiGet -Path $path -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

<#
.SYNOPSIS
    Cancel an existing order (V2).

.EXAMPLE
    Remove-KalshiOrder -OrderId '3b23c1c7-f4ef-4f0d-8b9a-9e53c61f1a0d'
#>
function Remove-KalshiOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$OrderId,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1,
        [int]$ExchangeIndex = 0
    )

    $path = "/portfolio/events/orders/$( [uri]::EscapeDataString($OrderId) )"
    $query = @()
    if ($ExchangeIndex -ne 0) { $query += "exchange_index=$ExchangeIndex" }
    if ($query.Count -gt 0)   { $path += '?' + ($query -join '&') }

    return Invoke-KalshiDelete -Path $path -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

<#
.SYNOPSIS
    Amend an existing order's price and/or count (V2).

.DESCRIPTION
    Updates the price and/or max fillable count of a resting order. The 'Count'
    parameter is the updated total/max fillable count (filled + desired remaining).

.EXAMPLE
    Edit-KalshiOrder -OrderId '3b23c1c7-...' -Ticker 'HIGHINFLATION-24JAN01-T60' -Side bid -Price 0.57 -Count 8
#>
function Edit-KalshiOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$OrderId,
        [Parameter(Mandatory)] [string]$Ticker,
        [Parameter(Mandatory)] [ValidateSet('bid', 'ask')] [string]$Side,
        [Parameter(Mandatory)] [string]$Count,
        [Parameter(Mandatory)] [string]$Price,
        [string]$ClientOrderId,
        [string]$UpdatedClientOrderId,
        [int]$ExchangeIndex = 0,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1
    )

    $body = @{
        ticker = $Ticker
        side   = $Side
        count  = "$Count"
        price  = "$Price"
    }
    if ($ClientOrderId)         { $body.client_order_id           = $ClientOrderId }
    if ($UpdatedClientOrderId)  { $body.updated_client_order_id   = $UpdatedClientOrderId }
    if ($ExchangeIndex -ne 0)   { $body.exchange_index            = $ExchangeIndex }

    $path = "/portfolio/events/orders/$( [uri]::EscapeDataString($OrderId) )/amend"
    return Invoke-KalshiPost -Path $path -Body $body -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

# ═══════════════════════════════════════════════════════════════════════════════
# PORTFOLIO ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Get the member's balance and portfolio value.

.DESCRIPTION
    Returns available balance in cents, portfolio value, and a balance breakdown
    per exchange index.

.EXAMPLE
    Get-KalshiBalance

.EXAMPLE
    Get-KalshiBalance -Subaccount 1
#>
function Get-KalshiBalance {
    [CmdletBinding()]
    param(
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1
    )
    return Invoke-KalshiGet -Path '/portfolio/balance' -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

<#
.SYNOPSIS
    Get balances for all subaccounts.

.EXAMPLE
    Get-KalshiAllSubaccountBalances
#>
function Get-KalshiAllSubaccountBalances {
    [CmdletBinding()]
    param(
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl
    )
    return Invoke-KalshiGet -Path '/portfolio/subaccounts/balances' -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl
}

<#
.SYNOPSIS
    Get current positions with optional filters.

.PARAMETER CountFilter
    Comma-separated list of fields that must be non-zero: 'position', 'total_traded'.

.EXAMPLE
    Get-KalshiPositions -Limit 500

.EXAMPLE
    Get-KalshiPositions -Ticker 'HIGHINFLATION-24JAN01-T60'
#>
function Get-KalshiPositions {
    [CmdletBinding()]
    param(
        [int]$Limit = 100,
        [string]$Cursor,
        [string]$CountFilter,
        [string]$Ticker,
        [string]$EventTicker,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1
    )

    $query = @()
    if ($Limit -ne 100) { $query += "limit=$Limit" }
    if ($Cursor)        { $query += "cursor=$( [uri]::EscapeDataString($Cursor) )" }
    if ($CountFilter)   { $query += "count_filter=$( [uri]::EscapeDataString($CountFilter) )" }
    if ($Ticker)        { $query += "ticker=$( [uri]::EscapeDataString($Ticker) )" }
    if ($EventTicker)   { $query += "event_ticker=$( [uri]::EscapeDataString($EventTicker) )" }

    $path = '/portfolio/positions'
    if ($query.Count -gt 0) { $path += '?' + ($query -join '&') }

    return Invoke-KalshiGet -Path $path -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

<#
.SYNOPSIS
    Get fills (completed trades) for the member.

.EXAMPLE
    Get-KalshiFills -Limit 200

.EXAMPLE
    Get-KalshiFills -Ticker 'HIGHINFLATION-24JAN01-T60' -MinTs 1703123456
#>
function Get-KalshiFills {
    [CmdletBinding()]
    param(
        [string]$Ticker,
        [string]$OrderId,
        [int]$MinTs,
        [int]$MaxTs,
        [int]$Limit = 100,
        [string]$Cursor,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1
    )

    $query = @()
    if ($Ticker)        { $query += "ticker=$( [uri]::EscapeDataString($Ticker) )" }
    if ($OrderId)       { $query += "order_id=$( [uri]::EscapeDataString($OrderId) )" }
    if ($MinTs)         { $query += "min_ts=$MinTs" }
    if ($MaxTs)         { $query += "max_ts=$MaxTs" }
    if ($Limit -ne 100) { $query += "limit=$Limit" }
    if ($Cursor)        { $query += "cursor=$( [uri]::EscapeDataString($Cursor) )" }

    $path = '/portfolio/fills'
    if ($query.Count -gt 0) { $path += '?' + ($query -join '&') }

    return Invoke-KalshiGet -Path $path -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

<#
.SYNOPSIS
    Get settlement history.

.DESCRIPTION
    Returns historical settlements for the member's positions, filtered by
    market or event ticker and time range.

.EXAMPLE
    Get-KalshiSettlements -Limit 500

.EXAMPLE
    Get-KalshiSettlements -EventTicker 'HIGHINFLATION-24JAN01'
#>
function Get-KalshiSettlements {
    [CmdletBinding()]
    param(
        [int]$Limit = 100,
        [string]$Cursor,
        [string]$Ticker,
        [string]$EventTicker,
        [int]$MinTs,
        [int]$MaxTs,
        [string]$ApiKeyId,
        [System.Security.Cryptography.RSA]$RsaKey,
        [string]$BaseUrl,
        [int]$Subaccount = -1
    )

    $query = @()
    if ($Limit -ne 100) { $query += "limit=$Limit" }
    if ($Cursor)        { $query += "cursor=$( [uri]::EscapeDataString($Cursor) )" }
    if ($Ticker)        { $query += "ticker=$( [uri]::EscapeDataString($Ticker) )" }
    if ($EventTicker)   { $query += "event_ticker=$( [uri]::EscapeDataString($EventTicker) )" }
    if ($MinTs)         { $query += "min_ts=$MinTs" }
    if ($MaxTs)         { $query += "max_ts=$MaxTs" }

    $path = '/portfolio/settlements'
    if ($query.Count -gt 0) { $path += '?' + ($query -join '&') }

    return Invoke-KalshiGet -Path $path -ApiKeyId $ApiKeyId -RsaKey $RsaKey -BaseUrl $BaseUrl -Subaccount $Subaccount
}

# ─── Module Export ────────────────────────────────────────────────────────────

Export-ModuleMember -Function @(
    # Credentials
    'Set-KalshiCredentials',
    'Test-KalshiCredentials',
    # Exchange
    'Get-KalshiExchangeStatus',
    'Get-KalshiExchangeAnnouncements',
    'Get-KalshiExchangeSchedule',
    'Get-KalshiSeriesFeeChanges',
    'Get-KalshiUserDataTimestamp',
    # Markets
    'Get-KalshiMarkets',
    'Get-KalshiMarket',
    'Get-KalshiOrderbook',
    'Get-KalshiMultipleOrderbooks',
    'Get-KalshiMarketCandlesticks',
    'Get-KalshiTrades',
    'Get-KalshiSeries',
    'Get-KalshiSeriesList',
    # Orders
    'New-KalshiOrder',
    'Get-KalshiOrders',
    'Get-KalshiOrder',
    'Remove-KalshiOrder',
    'Edit-KalshiOrder',
    # Portfolio
    'Get-KalshiBalance',
    'Get-KalshiAllSubaccountBalances',
    'Get-KalshiPositions',
    'Get-KalshiFills',
    'Get-KalshiSettlements'
)
