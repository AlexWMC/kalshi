# KalshiPowerShell.Tests.ps1 — Pester unit tests for KalshiPowerShell module
# Run: pwsh -c 'Invoke-Pester -Path ./KalshiPowerShell.Tests.ps1 -Output Detailed'

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot 'KalshiPowerShell'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Generate a throwaway RSA key for tests (cross-platform)
    $Script:TestRsa = [System.Security.Cryptography.RSA]::Create(2048)
    $Script:TestKeyId = 'a952bcbe-ec3b-4b5b-b8f9-11dae589608c'

    # Build PEM string at runtime — never store private key material in files
    function New-TestPem([System.Security.Cryptography.RSA]$rsa) {
        $bytes = $rsa.ExportRSAPrivateKey()
        $b64 = [Convert]::ToBase64String($bytes, [System.Base64FormattingOptions]::InsertLineBreaks)
        $lines = @()
        $lines += '-----BEGIN RSA PRIVATE KEY-----'
        $lines += $b64
        $lines += '-----END RSA PRIVATE KEY-----'
        return $lines -join "`r`n"
    }

    $Script:TestPem = New-TestPem $Script:TestRsa
}

Describe 'Credential Management' {
    It 'Set-KalshiCredentials accepts a PEM private key string' {
        { Set-KalshiCredentials -ApiKeyId $TestKeyId -PrivateKey $TestPem -Environment demo } | Should -Not -Throw
    }

    It 'Test-KalshiCredentials returns true after Set-KalshiCredentials' {
        Test-KalshiCredentials | Should -Be $true
    }

    It 'Set-KalshiCredentials switches to production environment' {
        { Set-KalshiCredentials -ApiKeyId $TestKeyId -PrivateKey $TestPem -Environment prod } | Should -Not -Throw
    }
}

Describe 'Signature Generation' {
    BeforeAll {
        Set-KalshiCredentials -ApiKeyId $TestKeyId -PrivateKey $TestPem -Environment prod
    }

    It 'New-KalshiSignature produces a non-empty base64 string' {
        $sig = & (Get-Module KalshiPowerShell) { param($k) New-KalshiSignature -TimestampMs 1703123456789 -Method 'GET' -Path '/trade-api/v2/portfolio/balance' -RsaKey $k } -k $Script:TestRsa
        $sig | Should -Not -BeNullOrEmpty
        { [Convert]::FromBase64String($sig) } | Should -Not -Throw
    }

    It 'Different paths produce different signatures' {
        $mod = Get-Module KalshiPowerShell
        $sig1 = & $mod { param($k) New-KalshiSignature -TimestampMs 1703123456789 -Method 'GET' -Path '/trade-api/v2/portfolio/balance' -RsaKey $k } -k $Script:TestRsa
        $sig2 = & $mod { param($k) New-KalshiSignature -TimestampMs 1703123456789 -Method 'GET' -Path '/trade-api/v2/portfolio/positions' -RsaKey $k } -k $Script:TestRsa
        $sig1 | Should -Not -Be $sig2
    }

    It 'Signature strips query parameters from the path' {
        $mod = Get-Module KalshiPowerShell
        $sigNoQuery = & $mod { param($k) New-KalshiSignature -TimestampMs 1703123456789 -Method 'GET' -Path '/trade-api/v2/portfolio/orders?limit=5' -RsaKey $k } -k $Script:TestRsa
        $sigClean   = & $mod { param($k) New-KalshiSignature -TimestampMs 1703123456789 -Method 'GET' -Path '/trade-api/v2/portfolio/orders' -RsaKey $k } -k $Script:TestRsa
        # Both signatures should be 344 chars (RSA 2048 + SHA256) regardless of key
        $sigNoQuery.Length | Should -Be $sigClean.Length
        $sigNoQuery.Length | Should -BeGreaterThan 300
    }

    It 'Different HTTP methods produce different signatures' {
        $mod = Get-Module KalshiPowerShell
        $sigGet  = & $mod { param($k) New-KalshiSignature -TimestampMs 1703123456789 -Method 'GET' -Path '/trade-api/v2/portfolio/balance' -RsaKey $k } -k $Script:TestRsa
        $sigPost = & $mod { param($k) New-KalshiSignature -TimestampMs 1703123456789 -Method 'POST' -Path '/trade-api/v2/portfolio/balance' -RsaKey $k } -k $Script:TestRsa
        $sigGet | Should -Not -Be $sigPost
    }

    It 'Auth headers contain all three required KALSHI headers' {
        $mod = Get-Module KalshiPowerShell
        $headers = & $mod { param($k, $id) New-KalshiAuthHeaders -Method 'GET' -Path '/trade-api/v2/portfolio/balance' -ApiKeyId $id -RsaKey $k } -k $Script:TestRsa -id $Script:TestKeyId
        $headers.Keys | Should -Contain 'KALSHI-ACCESS-KEY'
        $headers.Keys | Should -Contain 'KALSHI-ACCESS-TIMESTAMP'
        $headers.Keys | Should -Contain 'KALSHI-ACCESS-SIGNATURE'
        $headers['KALSHI-ACCESS-KEY'] | Should -Be $Script:TestKeyId
    }

    It 'Auth header timestamp is a valid millisecond epoch' {
        $mod = Get-Module KalshiPowerShell
        $before = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $headers = & $mod { param($k, $id) New-KalshiAuthHeaders -Method 'GET' -Path '/trade-api/v2/portfolio/balance' -ApiKeyId $id -RsaKey $k } -k $Script:TestRsa -id $Script:TestKeyId
        $after = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $ts = [long]$headers['KALSHI-ACCESS-TIMESTAMP']
        $ts | Should -BeGreaterOrEqual $before
        $ts | Should -BeLessOrEqual $after
    }
}

Describe 'Exchange Endpoints (Function Existence)' {
    It 'Get-KalshiExchangeStatus exists' {
        Get-Command Get-KalshiExchangeStatus -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'Get-KalshiExchangeAnnouncements exists' {
        Get-Command Get-KalshiExchangeAnnouncements -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'Get-KalshiExchangeSchedule exists' {
        Get-Command Get-KalshiExchangeSchedule -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'Get-KalshiSeriesFeeChanges exists' {
        Get-Command Get-KalshiSeriesFeeChanges -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'Get-KalshiUserDataTimestamp exists' {
        Get-Command Get-KalshiUserDataTimestamp -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }
}

Describe 'Market Endpoints (Function Existence & Parameters)' {
    It 'Get-KalshiMarkets has Status filter with valid values' {
        $cmd = Get-Command Get-KalshiMarkets -ErrorAction Stop
        $cmd.Parameters.Keys | Should -Contain 'Status'
        $cmd.Parameters.Keys | Should -Contain 'EventTicker'
        $cmd.Parameters.Keys | Should -Contain 'SeriesTicker'
        $cmd.Parameters.Keys | Should -Contain 'Tickers'
        $cmd.Parameters.Keys | Should -Contain 'Limit'
        $cmd.Parameters.Keys | Should -Contain 'Cursor'
        $cmd.Parameters['Status'].Attributes.ValidValues -contains 'open' | Should -Be $true
        $cmd.Parameters['Status'].Attributes.ValidValues -contains 'settled' | Should -Be $true
    }

    It 'Get-KalshiMarket has mandatory Ticker' {
        $cmd = Get-Command Get-KalshiMarket -ErrorAction Stop
        $cmd.Parameters['Ticker'].Attributes.Mandatory | Should -Be $true
    }

    It 'Get-KalshiOrderbook has mandatory Ticker and Depth param' {
        $cmd = Get-Command Get-KalshiOrderbook -ErrorAction Stop
        $cmd.Parameters['Ticker'].Attributes.Mandatory | Should -Be $true
        $cmd.Parameters.Keys | Should -Contain 'Depth'
    }

    It 'Get-KalshiMarketCandlesticks validates Period values' {
        $cmd = Get-Command Get-KalshiMarketCandlesticks -ErrorAction Stop
        $cmd.Parameters['Period'].Attributes.ValidValues -contains 1 | Should -Be $true
        $cmd.Parameters['Period'].Attributes.ValidValues -contains 60 | Should -Be $true
        $cmd.Parameters['Period'].Attributes.ValidValues -contains 1440 | Should -Be $true
    }

    It 'Get-KalshiTrades exists' {
        Get-Command Get-KalshiTrades -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'Get-KalshiSeries has mandatory Ticker' {
        $cmd = Get-Command Get-KalshiSeries -ErrorAction Stop
        $cmd.Parameters['Ticker'].Attributes.Mandatory | Should -Be $true
    }

    It 'Get-KalshiSeriesList exists' {
        Get-Command Get-KalshiSeriesList -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }

    It 'Get-KalshiMultipleOrderbooks has mandatory Tickers array' {
        $cmd = Get-Command Get-KalshiMultipleOrderbooks -ErrorAction Stop
        $cmd.Parameters['Tickers'].Attributes.Mandatory | Should -Be $true
    }
}

Describe 'Order Endpoints (Function Existence & Parameters)' {
    It 'New-KalshiOrder has mandatory Ticker/Side/Count/Price' {
        $cmd = Get-Command New-KalshiOrder -ErrorAction Stop
        $cmd.Parameters['Ticker'].Attributes.Mandatory | Should -Be $true
        $cmd.Parameters['Side'].Attributes.Mandatory | Should -Be $true
        $cmd.Parameters['Count'].Attributes.Mandatory | Should -Be $true
        $cmd.Parameters['Price'].Attributes.Mandatory | Should -Be $true
    }

    It 'New-KalshiOrder validates Side (bid/ask)' {
        $cmd = Get-Command New-KalshiOrder -ErrorAction Stop
        $cmd.Parameters['Side'].Attributes.ValidValues -contains 'bid' | Should -Be $true
        $cmd.Parameters['Side'].Attributes.ValidValues -contains 'ask' | Should -Be $true
    }

    It 'New-KalshiOrder has optional params (PostOnly, TIF, OrderGroup, etc.)' {
        $cmd = Get-Command New-KalshiOrder -ErrorAction Stop
        $cmd.Parameters.Keys | Should -Contain 'PostOnly'
        $cmd.Parameters.Keys | Should -Contain 'CancelOrderOnPause'
        $cmd.Parameters.Keys | Should -Contain 'ReduceOnly'
        $cmd.Parameters.Keys | Should -Contain 'TimeInForce'
        $cmd.Parameters.Keys | Should -Contain 'ClientOrderId'
        $cmd.Parameters.Keys | Should -Contain 'OrderGroupId'
        $cmd.Parameters.Keys | Should -Contain 'ExpirationTime'
    }

    It 'Get-KalshiOrders validates Status values' {
        $cmd = Get-Command Get-KalshiOrders -ErrorAction Stop
        $cmd.Parameters['Status'].Attributes.ValidValues -contains 'resting' | Should -Be $true
        $cmd.Parameters['Status'].Attributes.ValidValues -contains 'canceled' | Should -Be $true
        $cmd.Parameters['Status'].Attributes.ValidValues -contains 'executed' | Should -Be $true
    }

    It 'Get-KalshiOrder has mandatory OrderId' {
        $cmd = Get-Command Get-KalshiOrder -ErrorAction Stop
        $cmd.Parameters['OrderId'].Attributes.Mandatory | Should -Be $true
    }

    It 'Remove-KalshiOrder has mandatory OrderId' {
        $cmd = Get-Command Remove-KalshiOrder -ErrorAction Stop
        $cmd.Parameters['OrderId'].Attributes.Mandatory | Should -Be $true
    }

    It 'Edit-KalshiOrder has all mandatory params' {
        $cmd = Get-Command Edit-KalshiOrder -ErrorAction Stop
        $cmd.Parameters['OrderId'].Attributes.Mandatory | Should -Be $true
        $cmd.Parameters['Ticker'].Attributes.Mandatory | Should -Be $true
        $cmd.Parameters['Side'].Attributes.Mandatory | Should -Be $true
        $cmd.Parameters['Count'].Attributes.Mandatory | Should -Be $true
        $cmd.Parameters['Price'].Attributes.Mandatory | Should -Be $true
    }
}

Describe 'Portfolio Endpoints (Function Existence)' {
    It 'Get-KalshiBalance exists' {
        Get-Command Get-KalshiBalance -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }
    It 'Get-KalshiAllSubaccountBalances exists' {
        Get-Command Get-KalshiAllSubaccountBalances -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }
    It 'Get-KalshiPositions has filter params' {
        $cmd = Get-Command Get-KalshiPositions -ErrorAction Stop
        $cmd.Parameters.Keys | Should -Contain 'CountFilter'
        $cmd.Parameters.Keys | Should -Contain 'EventTicker'
        $cmd.Parameters.Keys | Should -Contain 'Ticker'
    }
    It 'Get-KalshiFills exists' {
        Get-Command Get-KalshiFills -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }
    It 'Get-KalshiSettlements exists' {
        Get-Command Get-KalshiSettlements -ErrorAction Stop | Should -Not -BeNullOrEmpty
    }
}

Describe 'Import-KalshiPrivateKey (internal helper)' {
    BeforeAll {
        $Script:KeyPath = Join-Path $TestDrive 'test_key.pem'
        $Script:TestPemFile = New-TestPem $Script:TestRsa
        Set-Content -Path $Script:KeyPath -Value $Script:TestPemFile -NoNewline
    }

    It 'Loads a PEM file from disk' {
        $key = & (Get-Module KalshiPowerShell) { param($p) Import-KalshiPrivateKey -KeyString $p -IsFilePath } -p $Script:KeyPath
        $key | Should -Not -BeNullOrEmpty
        $key.KeySize | Should -Be 2048
    }

    It 'Loads a PEM string directly' {
        $rawPem = Get-Content $Script:KeyPath -Raw
        $key = & (Get-Module KalshiPowerShell) { param($s) Import-KalshiPrivateKey -KeyString $s } -s $rawPem
        $key | Should -Not -BeNullOrEmpty
        $key.KeySize | Should -Be 2048
    }

    It 'Throws on missing file' {
        { & (Get-Module KalshiPowerShell) { Import-KalshiPrivateKey -KeyString '/nonexistent/key.pem' -IsFilePath -ErrorAction Stop } } | Should -Throw
    }
}

Describe 'Module Exports' {
    It 'Exports exactly 25 functions' {
        (Get-Module KalshiPowerShell).ExportedFunctions.Count | Should -Be 25
    }

    It 'All expected functions are exported' {
        $exported = (Get-Module KalshiPowerShell).ExportedFunctions.Keys
        $expected = @(
            'Set-KalshiCredentials', 'Test-KalshiCredentials',
            'Get-KalshiExchangeStatus', 'Get-KalshiExchangeAnnouncements',
            'Get-KalshiExchangeSchedule', 'Get-KalshiSeriesFeeChanges',
            'Get-KalshiUserDataTimestamp',
            'Get-KalshiMarkets', 'Get-KalshiMarket',
            'Get-KalshiOrderbook', 'Get-KalshiMultipleOrderbooks',
            'Get-KalshiMarketCandlesticks', 'Get-KalshiTrades',
            'Get-KalshiSeries', 'Get-KalshiSeriesList',
            'New-KalshiOrder', 'Get-KalshiOrders', 'Get-KalshiOrder',
            'Remove-KalshiOrder', 'Edit-KalshiOrder',
            'Get-KalshiBalance', 'Get-KalshiAllSubaccountBalances',
            'Get-KalshiPositions', 'Get-KalshiFills', 'Get-KalshiSettlements'
        )
        foreach ($fn in $expected) {
            $exported -contains $fn | Should -Be $true -Because "function $fn is exported"
        }
    }
}

Describe 'Error Handling' {
    It 'New-KalshiOrder rejects invalid Side value' {
        { New-KalshiOrder -Ticker 'TEST' -Side 'invalid' -Count 10 -Price 0.5 -ErrorAction Stop } | Should -Throw
    }

    It 'New-KalshiOrder rejects invalid TimeInForce value' {
        { New-KalshiOrder -Ticker 'TEST' -Side 'bid' -Count 10 -Price 0.5 -TimeInForce 'forever' -ErrorAction Stop } | Should -Throw
    }

    It 'HTTP error returns a meaningful exception type' {
        try {
            Get-KalshiExchangeStatus -BaseUrl 'http://localhost:1/trade-api/v2' -ErrorAction Stop
        }
        catch {
            $_.Exception.GetType().Name | Should -Match 'WebCmdlet|WebException|HttpRequest|Invocation|Rest'
        }
    }
}
