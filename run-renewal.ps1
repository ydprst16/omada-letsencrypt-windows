# ============================================================
# OMADA - PRE-BACKUP + WIN-ACME RENEWAL RUNNER
# Windows PowerShell 5.1
# ============================================================
$ErrorActionPreference = 'Stop'

$CertDir = 'C:\certificates\omada'
$ScriptDir = Join-Path $CertDir 'scripts'
$BackupDir = Join-Path $CertDir 'backup'
$StageDir = Join-Path $BackupDir '_pre-renewal'
$LogDir = Join-Path $CertDir 'logs'
$LogFile = Join-Path $LogDir 'renewal-runner.log'
$Wacs = 'C:\tools\win-acme\wacs.exe'
$BaseUri = 'https://acme-v02.api.letsencrypt.org/'
$Domain = 'bpsdumai.myddns.me'
$PemNames = @(
    "$Domain-crt.pem",
    "$Domain-key.pem",
    "$Domain-chain.pem",
    "$Domain-chain-only.pem"
)

New-Item -ItemType Directory -Force -Path $LogDir, $BackupDir | Out-Null
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -LiteralPath $LogFile -Value $line
    Write-Host $line
}

try {
    Write-Log '================================================'
    Write-Log 'Starting pre-renewal backup and win-acme renewal'

    if (!(Test-Path -LiteralPath $Wacs -PathType Leaf)) {
        throw "win-acme executable not found: $Wacs"
    }

    # A stable staging directory is overwritten on every scheduled run.
    # It therefore always contains the most recent pre-renewal PEM set.
    $missing = @()
    foreach ($name in $PemNames) {
        $path = Join-Path $CertDir $name
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { $missing += $name }
    }
    if ($missing.Count -gt 0) {
        throw "Cannot create pre-renewal backup; missing PEM file(s): $($missing -join ', ')"
    }

    if (Test-Path -LiteralPath $StageDir) {
        Remove-Item -LiteralPath $StageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

    foreach ($name in $PemNames) {
        Copy-Item -LiteralPath (Join-Path $CertDir $name) -Destination $StageDir -Force
    }
    @(
        "Domain: $Domain"
        "Captured before win-acme renewal attempt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
        "This staging set is promoted to a permanent backup only if the post-renewal validation script runs successfully."
    ) | Set-Content -LiteralPath (Join-Path $StageDir 'backup-info.txt') -Encoding UTF8
    Write-Log "Pre-renewal PEM snapshot prepared: $StageDir"

    Write-Log 'Starting win-acme renewal check...'
    & $Wacs --renew --baseuri $BaseUri
    $wacsExit = $LASTEXITCODE
    Write-Log "win-acme exit code: $wacsExit"

    if ($wacsExit -ne 0) {
        throw "win-acme returned exit code $wacsExit. Pre-renewal snapshot retained at $StageDir"
    }

    Write-Log 'win-acme renewal check completed.'
    Write-Log 'If a certificate was renewed, the configured installation script validates it and archives the before/after sets.'
    Write-Log '================================================'
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    Write-Log 'Renewal runner failed. Any pre-renewal snapshot is retained for recovery.' 'ERROR'
    exit 1
}
