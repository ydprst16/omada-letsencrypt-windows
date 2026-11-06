# ============================================================
# OMADA - POST-RENEWAL CERTIFICATE VALIDATION + ARCHIVING
# Windows PowerShell 5.1
# ============================================================
# Called by win-acme after PEM export. This script does NOT
# import the certificate into Omada or modify its keystore.
$ErrorActionPreference = 'Stop'

$CertDir = 'C:\certificates\omada'
$LogDir = Join-Path $CertDir 'logs'
$BackupDir = Join-Path $CertDir 'backup'
$StageDir = Join-Path $BackupDir '_pre-renewal'
$Domain = 'bpsdumai.myddns.me'
$CertFile = Join-Path $CertDir "$Domain-crt.pem"
$KeyFile = Join-Path $CertDir "$Domain-key.pem"
$ChainFile = Join-Path $CertDir "$Domain-chain.pem"
$ChainOnlyFile = Join-Path $CertDir "$Domain-chain-only.pem"
$OpenSSL = 'C:\xampp\apache\bin\openssl.exe'
$TempCertPub = Join-Path $env:TEMP "omada-cert-public-$PID.pem"
$TempKeyPub = Join-Path $env:TEMP "omada-key-public-$PID.pem"
$LogFile = Join-Path $LogDir 'deployment.log'
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

$ValidationSucceeded = $false
try {
    Write-Log '================================================'
    Write-Log 'Starting post-renewal certificate validation'
    Write-Log "Domain: $Domain"

    foreach ($file in @($CertFile, $KeyFile, $ChainFile, $ChainOnlyFile, $OpenSSL)) {
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Required file not found: $file"
        }
    }
    Write-Log 'Required certificate files found.'

    $certInfo = & $OpenSSL x509 -in $CertFile -noout -subject -issuer -dates 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'OpenSSL could not read the domain certificate.' }
    foreach ($line in $certInfo) { Write-Log "$line" }

    $hostResult = (& $OpenSSL x509 -in $CertFile -noout -checkhost $Domain 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $hostResult -notmatch 'does match certificate') {
        throw "Certificate hostname validation failed for $Domain. $hostResult"
    }
    Write-Log 'Certificate hostname validation successful.'

    $endDate = & $OpenSSL x509 -in $CertFile -noout -enddate 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read certificate expiration date.' }
    $expiryString = [regex]::Replace((($endDate -replace '^notAfter=', '').Trim()), '\s+', ' ')
    $expiryDate = [DateTime]::ParseExact(
        $expiryString,
        'MMM d HH:mm:ss yyyy ''GMT''',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal
    ).ToUniversalTime()
    & $OpenSSL x509 -in $CertFile -noout -checkend 0 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Certificate has expired.' }
    Write-Log "Certificate expiry: $($expiryDate.ToString('yyyy-MM-dd HH:mm:ss')) UTC"
    Write-Log 'Certificate validity check successful.'

    & $OpenSSL x509 -in $CertFile -pubkey -noout -out $TempCertPub
    if ($LASTEXITCODE -ne 0) { throw 'Unable to extract certificate public key.' }
    & $OpenSSL pkey -in $KeyFile -pubout -out $TempKeyPub
    if ($LASTEXITCODE -ne 0) { throw 'Unable to extract private-key public component.' }
    $certHash = (Get-FileHash -LiteralPath $TempCertPub -Algorithm SHA256).Hash
    $keyHash = (Get-FileHash -LiteralPath $TempKeyPub -Algorithm SHA256).Hash
    if ($certHash -ne $keyHash) { throw 'Certificate and private key do not match.' }
    Write-Log 'Certificate and private key match.'

    & $OpenSSL crl2pkcs7 -nocrl -certfile $ChainFile -outform DER -out NUL 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Certificate chain PEM structure validation failed.' }
    & $OpenSSL crl2pkcs7 -nocrl -certfile $ChainOnlyFile -outform DER -out NUL 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Chain-only PEM structure validation failed.' }
    Write-Log 'Certificate chain PEM structure validation successful.'

    $ValidationSucceeded = $true
}
catch {
    Write-Log "VALIDATION ERROR: $($_.Exception.Message)" 'ERROR'
}
finally {
    Remove-Item -LiteralPath $TempCertPub, $TempKeyPub -Force -ErrorAction SilentlyContinue
}

if (!$ValidationSucceeded) {
    # Roll back the four PEM outputs if a pre-renewal snapshot exists.
    # Keep the snapshot for investigation and recovery.
    $stageComplete = $true
    foreach ($name in $PemNames) {
        if (!(Test-Path -LiteralPath (Join-Path $StageDir $name) -PathType Leaf)) { $stageComplete = $false }
    }
    if ($stageComplete) {
        try {
            foreach ($name in $PemNames) {
                Copy-Item -LiteralPath (Join-Path $StageDir $name) -Destination (Join-Path $CertDir $name) -Force
            }
            Write-Log "Validation failed; previous PEM set restored from $StageDir" 'WARN'
        }
        catch {
            Write-Log "AUTOMATIC RESTORE FAILED: $($_.Exception.Message). Preserve $StageDir and restore manually." 'ERROR'
        }
    }
    else {
        Write-Log 'No complete pre-renewal snapshot found; no automatic rollback performed.' 'WARN'
    }
    Write-Log 'Omada active certificate has NOT been modified.'
    Write-Log '================================================'
    exit 1
}

try {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $archivePath = Join-Path $BackupDir $timestamp
    New-Item -ItemType Directory -Force -Path $archivePath | Out-Null

    $beforePath = Join-Path $archivePath 'before-renewal'
    $afterPath = Join-Path $archivePath 'after-renewal'
    New-Item -ItemType Directory -Force -Path $beforePath, $afterPath | Out-Null

    $stageComplete = $true
    foreach ($name in $PemNames) {
        if (!(Test-Path -LiteralPath (Join-Path $StageDir $name) -PathType Leaf)) { $stageComplete = $false }
    }
    if ($stageComplete) {
        foreach ($name in $PemNames) {
            Copy-Item -LiteralPath (Join-Path $StageDir $name) -Destination $beforePath -Force
        }
        Copy-Item -LiteralPath (Join-Path $StageDir 'backup-info.txt') -Destination $beforePath -Force -ErrorAction SilentlyContinue
        Write-Log "Pre-renewal certificate set archived: $beforePath"
    }
    else {
        Write-Log 'No complete pre-renewal snapshot found; only the validated current PEM set will be archived.' 'WARN'
    }

    foreach ($name in $PemNames) {
        Copy-Item -LiteralPath (Join-Path $CertDir $name) -Destination $afterPath -Force
        Write-Log "Validated PEM archived: $name"
    }

    if ($stageComplete) {
        Remove-Item -LiteralPath $StageDir -Recurse -Force
        Write-Log 'Pre-renewal staging snapshot promoted to permanent archive and cleared.'
    }

    Write-Log "Backup completed: $archivePath"
    Write-Log 'Certificate validation completed successfully.'
    Write-Log 'Omada active certificate has NOT been modified.'
    Write-Log '================================================'
    exit 0
}
catch {
    Write-Log "ARCHIVE ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Log 'Validated PEM files remain in the main certificate directory. Review the staging and archive folders.' 'ERROR'
    exit 1
}
