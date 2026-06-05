#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick-start demo for the KalshiPowerShell module.
    Run this after configuring your Kalshi API credentials.

.DESCRIPTION
    Walks through: credential setup → check exchange → browse markets → check balance
    Replace the placeholders below with your actual Kalshi API key.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ApiKeyId,
    [Parameter(Mandatory)]
    [string]$PrivateKeyPath,
    [ValidateSet('prod','demo')]
    [string]$Environment = 'demo'
)

$ErrorActionPreference = 'Stop'

# Resolve module path (assumes this script lives next to the module folder)
$scriptDir = Split-Path -Parent $PSCommandPath
$modulePath = Join-Path $scriptDir 'KalshiPowerShell'

# Import the module
Write-Host "Importing KalshiPowerShell..." -ForegroundColor Cyan
Import-Module $modulePath -Force -ErrorAction Stop

# Configure credentials
Write-Host "Setting credentials (env: $Environment)..." -ForegroundColor Cyan
Set-KalshiCredentials -ApiKeyId $ApiKeyId -PrivateKeyPath $PrivateKeyPath -Environment $Environment

# --- Demo ---

Write-Host "`n=== Exchange Status ===" -ForegroundColor Yellow
$status = Get-KalshiExchangeStatus
Write-Host "  Exchange active: $($status.exchange_active)"
Write-Host "  Trading active:  $($status.trading_active)"
if ($status.exchange_estimated_resume_time) {
    Write-Host "  Resume time:     $($status.exchange_estimated_resume_time)"
}

Write-Host "`n=== Open Markets (top 5) ===" -ForegroundColor Yellow
$markets = Get-KalshiMarkets -Status open -Limit 5
foreach ($m in $markets.markets) {
    Write-Host "  $($m.ticker) — $($m.title)"
    Write-Host "    Yes bid: $($m.yes_bid_dollars) | Yes ask: $($m.yes_ask_dollars)"
}

if ($Environment -ne 'demo') {
    Write-Host "`n=== Portfolio Balance ===" -ForegroundColor Yellow
    $balance = Get-KalshiBalance
    Write-Host "  Balance:       `$$($balance.balance / 100)" -NoNewline
    Write-Host " ($($balance.balance_dollars))"
    Write-Host "  Portfolio val: `$$($balance.portfolio_value / 100)"
} else {
    Write-Host "`n(Skipping portfolio calls — demo environment)" -ForegroundColor DarkYellow
}

Write-Host "`nDone. KalshiPowerShell is working correctly." -ForegroundColor Green
