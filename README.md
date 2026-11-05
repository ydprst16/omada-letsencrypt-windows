# Install and Automate Let's Encrypt SSL Certificate Renewal on TP-Link Omada Controller (Windows 11)

This guide explains how to install a free SSL certificate from Let's Encrypt on TP-Link Omada Software Controller running on Windows 11, then configure an automated renewal workflow using win-acme, PowerShell, and Windows Task Scheduler.

The workflow includes:

- **win-acme** – to request and renew Let's Encrypt certificates.
- **Let's Encrypt** – to issue free SSL certificates.
- **XAMPP Apache** – to handle HTTP-01 domain validation.
- **OpenSSL** – to validate certificates and private keys.
- **PowerShell** – to automate backup, validation, and recovery.
- **Windows Task Scheduler** – to run the renewal workflow automatically.
- **Omada Controller** – to use the imported certificate.

> **Important:** This implementation automates certificate renewal, PEM backup, and validation. Importing the renewed certificate into Omada is still a manual Web UI operation in this setup.

## 1. What You Need

Before starting, prepare:

- Windows 11 computer.
- TP-Link Omada Software Controller installed.
- A domain name pointing to your public IP address.
- XAMPP installed and Apache running.
- Router access to configure port forwarding.
- OpenSSL available (XAMPP includes OpenSSL).
- Administrator access to Windows.

Example setup:

| Item | Example |
|---|---|
| Domain | `omada.example.com` |
| Omada HTTPS management | `8043` |
| Omada HTTPS portal | `8843` |
| HTTP validation | `80` |
| XAMPP web root | `C:\xampp\htdocs` |
| win-acme directory | `C:\tools\win-acme` |
| Certificate directory | `C:\certificates\omada` |

**Important:** Port 80 must be accessible from the internet for Let's Encrypt HTTP-01 verification. You do not need to expose Omada management port 8043 to the internet.

## 2. Configure Your Network

Before requesting the certificate:

1. Point your domain to your public IP address.
2. Forward TCP port 80 on your router to your Windows computer.
3. Allow TCP port 80 in Windows Firewall.
4. Start Apache from XAMPP.
5. Verify that the domain can reach the XAMPP web server from outside your local network.

Let's Encrypt will use port 80 to verify domain ownership through the HTTP-01 challenge.

If you use local DNS or NAT loopback, make sure that the domain also resolves correctly from your local network.

## 3. Download and Install win-acme

Download win-acme:

https://www.win-acme.com/

Steps:

1. Download the Windows x64 version.
2. Extract the ZIP file.
3. Create this folder:

   ```text
   C:\tools\win-acme
   ```

4. Copy the extracted files into that folder.
5. Open PowerShell as Administrator.
6. Run:

   ```powershell
   cd C:\tools\win-acme
   .\wacs.exe
   ```

The win-acme menu will appear.

This implementation uses win-acme 2.2.9.1701 and the Let's Encrypt production ACME endpoint.

## 4. Request a Let's Encrypt Certificate

Follow the win-acme menu.

The menu names may vary slightly depending on the version.

1. Select the option to create a new certificate.
2. Choose the option to enter the domain manually.
3. Enter your domain:

   ```text
   omada.example.com
   ```

4. Select HTTP-01 validation.
5. Choose the option to use an existing website or web root.
6. Enter the XAMPP web root:

   ```text
   C:\xampp\htdocs
   ```

7. When asked where to store the certificate, choose **PEM files**.
8. Set the output folder:

   ```text
   C:\certificates\omada
   ```

9. Complete the remaining steps.

After successful issuance, win-acme exports the certificate and private key as PEM files.

The renewal configuration is also saved by win-acme.

## 5. Understand the PEM Certificate Files

Open:

```text
C:\certificates\omada
```

You should find files similar to:

```text
omada.example.com-chain-only.pem
omada.example.com-chain.pem
omada.example.com-crt.pem
omada.example.com-key.pem
```

The files have different purposes:

| File | Purpose |
|---|---|
| `-crt.pem` | Domain/leaf certificate |
| `-key.pem` | Private key |
| `-chain-only.pem` | Certificate chain without the leaf certificate |
| `-chain.pem` | Domain certificate together with the certificate chain |

In our tested setup, `-crt.pem` contains one certificate block, while `-chain.pem` contains the leaf certificate and additional chain certificates.

The exact chain contents can change when Let's Encrypt changes its certificate chain.

**Security note:** Never upload the private key to GitHub or share it publicly.

## 6. Prepare and Validate the Certificate

Before importing the certificate into Omada, validate the exported PEM files.

XAMPP includes OpenSSL at:

```powershell
$OpenSSL = "C:\xampp\apache\bin\openssl.exe"
```

Check the domain certificate:

```powershell
& $OpenSSL x509 `
  -in "C:\certificates\omada\omada.example.com-crt.pem" `
  -noout -subject -issuer -dates
```

Check the hostname:

```powershell
& $OpenSSL x509 `
  -in "C:\certificates\omada\omada.example.com-crt.pem" `
  -noout -checkhost omada.example.com
```

Check the private key:

```powershell
& $OpenSSL pkey `
  -in "C:\certificates\omada\omada.example.com-key.pem" `
  -check -noout
```

The certificate and private key must match. The automated validation script described later also checks this relationship.

For the Omada import, use the PEM certificate/chain and private key in the format accepted by your Omada Controller version. Do not assume that every PEM file has the same contents or is interchangeable.

## 7. Import the Certificate into Omada

Open Omada Software Controller.

Navigate to the certificate or HTTPS configuration page. The exact menu location depends on the Omada Controller version.

Import the certificate using the Web UI.

For the tested workflow, the certificate was initially imported through Omada's Web UI using PEM files.

After saving the configuration, restart the Omada Controller service if required by the application.

Access the management interface:

```text
https://omada.example.com:8043
```

Check the browser's certificate information to confirm that the certificate is trusted and matches your domain.

You can also check the certificate served by Omada using OpenSSL, as described in Section 12.

## 8. Create the Automated Backup and Validation Scripts

To make renewal safer, we use two PowerShell scripts.

The scripts are stored in:

```text
C:\certificates\omada\scripts
```

The directory structure is:

```text
C:\certificates\omada
│
├── omada.example.com-chain-only.pem
├── omada.example.com-chain.pem
├── omada.example.com-crt.pem
├── omada.example.com-key.pem
│
├── backup
│   └── _pre-renewal
│
├── logs
│
└── scripts
    ├── run-renewal.ps1
    └── deploy-omada-cert.ps1
```

### 8.1 run-renewal.ps1

This is the main renewal runner.

Its responsibilities are:

1. Check that win-acme and the current PEM files exist.
2. Create a pre-renewal backup directory.
3. Copy the current PEM files into the backup directory.
4. Write backup information to a log.
5. Run win-acme renewal:

   ```powershell
   wacs.exe --renew --baseuri "https://acme-v02.api.letsencrypt.org/"
   ```

6. Capture the win-acme exit code.
7. Log the result and return an appropriate exit status.

The backup directory is:

```text
C:\certificates\omada\backup\_pre-renewal
```

The runner does not use `--force`. It allows win-acme to determine whether a certificate is due for renewal.

**Why back up before renewal?**

If a renewal produces invalid or unexpected PEM files, the previous certificate files are available for recovery.

The `_pre-renewal` folder is a working snapshot. It is overwritten on the next run, so it should not be treated as a permanent historical archive.

### 8.2 deploy-omada-cert.ps1

Despite its filename, this script does not directly replace Omada's active certificate or modify its internal keystore.

It is configured as win-acme's external installation script and performs post-export checks.

Its responsibilities include:

1. Validate the newly exported PEM files.
2. Check certificate details and validity.
3. Verify the hostname.
4. Verify that the certificate and private key match.
5. Check the certificate chain format.
6. Restore the previous PEM set from `_pre-renewal` if validation fails.
7. Archive the before-and-after PEM sets when validation succeeds.
8. Write the result to the deployment log.

Logs are stored in:

```text
C:\certificates\omada\logs
```

This approach separates certificate renewal from certificate activation in Omada.

**Important:** The script validates and manages PEM files. It does not automatically import the new certificate into Omada.

## 9. Configure win-acme to Run the Validation Script

win-acme supports installation plugins that can execute an external script after a certificate is stored.

To configure it:

1. Open PowerShell as Administrator.
2. Run:

   ```powershell
   cd C:\tools\win-acme
   .\wacs.exe
   ```

3. Open the renewal management menu.
4. Select the existing renewal configuration.
5. Choose **Edit renewal**.
6. Navigate to the **Installation** step.
7. Select the option to run an external script or program.
8. Enter:

   ```text
   C:\certificates\omada\scripts\deploy-omada-cert.ps1
   ```

9. Leave the script parameters blank if the script does not require them.
10. Save the renewal configuration.

win-acme will execute this script after exporting renewed certificate files.

The installation plugin is part of the renewal configuration. You do not need to create a separate certificate request just to configure this step.

## 10. Configure Windows Task Scheduler

win-acme creates a scheduled task for automatic renewal.

The original task is:

```text
win-acme renew (acme-v02.api.letsencrypt.org)
```

In this implementation, the task action is changed to execute our PowerShell runner instead of calling win-acme directly.

The runner creates the pre-renewal backup before calling win-acme.

### 10.1 Update the Scheduled Task Action

Open PowerShell as Administrator and run:

```powershell
$TaskName = "win-acme renew (acme-v02.api.letsencrypt.org)"

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\certificates\omada\scripts\run-renewal.ps1"' `
    -WorkingDirectory "C:\tools\win-acme"

Set-ScheduledTask -TaskName $TaskName -Action $Action
```

The task should retain its existing schedule and security settings.

In our tested configuration:

| Setting | Value |
|---|---|
| Run as | `SYSTEM` |
| Logon type | ServiceAccount |
| Run level | Highest |
| Execution | PowerShell |
| Script | `run-renewal.ps1` |
| Working directory | `C:\tools\win-acme` |

The task runs daily, with a randomized delay.

### 10.2 Verify the Scheduled Task

Run:

```powershell
$TaskName = "win-acme renew (acme-v02.api.letsencrypt.org)"

Get-ScheduledTask -TaskName $TaskName |
    Select-Object TaskName, State

Get-ScheduledTaskInfo -TaskName $TaskName |
    Format-List LastRunTime, LastTaskResult, NextRunTime
```

Expected successful result:

```text
State          : Ready
LastTaskResult : 0
```

`LastTaskResult = 0` indicates that the scheduled task completed successfully.

If you see `267009` (`0x41301`), the task is still running. Wait and check again rather than treating it as an immediate failure.

### 10.3 Check the Pre-renewal Backup

Run:

```powershell
Get-ChildItem "C:\certificates\omada\backup\_pre-renewal" |
    Select-Object Name, Length
```

The folder should contain the four PEM files and backup information:

```text
backup-info.txt
omada.example.com-chain-only.pem
omada.example.com-chain.pem
omada.example.com-crt.pem
omada.example.com-key.pem
```

This confirms that the runner created the pre-renewal snapshot.

## 11. Understand the Automated Renewal Workflow

The complete workflow is:

```text
Windows Task Scheduler
          |
          v
    run-renewal.ps1
          |
          v
  Backup current PEM files
          |
          v
      wacs.exe --renew
          |
          v
  Is renewal due?
          |
     +----+----+
     |         |
    No         Yes
     |         |
     v         v
  Finish    Export new PEM
               |
               v
    deploy-omada-cert.ps1
               |
               v
      Validate certificate
               |
          +----+----+
          |         |
        Valid     Invalid
          |         |
          v         v
      Archive     Restore
      PEM files   previous PEM
          |         |
          v         v
        Finish    Log failure
```

There are two important points:

- If the certificate is not due for renewal, win-acme completes its check without forcing a new certificate.
- If a new certificate is issued, win-acme exports the PEM files and invokes the configured installation script.

The workflow keeps a pre-renewal snapshot and supports recovery of the previous PEM files if validation fails.

## 12. Verify the Certificate Served by Omada

Renewing the PEM files does not automatically mean that Omada is serving the new certificate.

Use OpenSSL to inspect the active certificate.

For the management interface:

```powershell
$OpenSSL = "C:\xampp\apache\bin\openssl.exe"

"" | & $OpenSSL s_client `
    -connect 127.0.0.1:8043 `
    -servername omada.example.com 2>$null |
    & $OpenSSL x509 -noout -subject -issuer -dates
```

For the portal interface:

```powershell
"" | & $OpenSSL s_client `
    -connect 127.0.0.1:8843 `
    -servername omada.example.com 2>$null |
    & $OpenSSL x509 -noout -subject -issuer -dates
```

Compare the certificate issuer and expiration date with the files in:

```text
C:\certificates\omada
```

If the active Omada certificate is older than the newly exported PEM certificate, import the updated certificate through the Omada Web UI.

Do not assume that replacing PEM files in the win-acme output folder updates Omada's active certificate.

## 13. Important Security Considerations

- Do not expose Omada management port 8043 directly to the public internet unless you have a separate security requirement and appropriate controls.
- Keep TCP port 80 available for HTTP-01 validation.
- Protect the private key file.
- Restrict access to the certificate directory and its backups.
- Keep the scripts and logs away from public repositories.
- Do not use `--force` for routine renewal testing.
- Do not manually modify Omada's internal keystore unless you have a verified, supported procedure and a recovery plan.
- Test certificate validation and backup recovery before relying on the automation in production.

## 14. Current Implementation Status

The workflow has been tested on Windows 11 with Omada Software Controller 6.3.0.111 and win-acme 2.2.9.1701.

| Component | Status |
|---|---|
| Let's Encrypt certificate issuance | Tested |
| HTTP-01 validation through XAMPP | Configured |
| PEM file export | Tested |
| Certificate and key validation | Tested |
| Pre-renewal backup | Tested |
| Post-export validation script | Configured and executed |
| Rollback logic for invalid PEM files | Included in script |
| Windows Task Scheduler integration | Tested |
| Scheduled renewal runner | Tested successfully |
| Automatic Omada Web UI import | Not implemented |
| Active certificate verification | Available through OpenSSL |

The scheduled task test completed with `LastTaskResult = 0`, and the pre-renewal backup contained all four PEM files.

## Conclusion

Let's Encrypt and win-acme provide a practical way to manage SSL certificates for TP-Link Omada Software Controller on Windows 11.

The implementation can be divided into three stages:

1. **Certificate management:** win-acme requests, exports, and renews the Let's Encrypt certificate.
2. **Automation and recovery:** PowerShell backs up the previous PEM files, validates new exports, and supports rollback.
3. **Omada activation:** the updated certificate is imported through Omada Web UI and verified on ports 8043 and 8843.

This approach provides automated renewal checks and certificate file management while keeping the final Omada certificate activation under controlled administration.

The next improvement would be to investigate a supported and reliable way to automate Omada certificate import without directly modifying undocumented internal keystore files.
