@{
    RootModule           = 'KalshiPowerShell.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author               = 'Alex'
    CompanyName          = ''
    Copyright            = '(c) 2025. MIT License.'
    Description          = 'PowerShell 7+ module for the Kalshi prediction market trading API. Supports exchange, market, order, and portfolio operations with RSA-PSS/SHA256 authentication.'

    PowerShellVersion    = '7.0'

    FunctionsToExport    = @(
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

    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('kalshi', 'prediction-market', 'trading', 'api', 'finance')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://docs.kalshi.com'
            ReleaseNotes = 'Initial release. All exchange, market, order, and portfolio GET endpoints + order creation/amendment/cancellation (V2).'
        }
    }
}
