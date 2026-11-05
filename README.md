# Let's Encrypt SSL Certificate for TP-Link Omada Software Controller on Windows 11

This guide explains how to obtain and renew a free SSL certificate from Let's Encrypt for **TP-Link Omada Software Controller** running on Windows 11.

The process uses:

- **win-acme** to request and renew the SSL certificate.
- **Let's Encrypt** as the certificate authority.
- **XAMPP Apache** to handle HTTP-01 domain validation.
- **OpenSSL** to check the certificate and prepare the PEM files.
- **Omada Software Controller** to install the certificate.

## 1. Environment

This guide uses the following example environment:

| Component | Example |
|---|---|
| Operating System | Windows 11 |
| Omada Controller | Software Controller 6.x |
| Domain | `omada.example.com` |
| Omada HTTPS Management | TCP 8043 |
| Omada HTTPS Portal | TCP 8843 |
| HTTP Validation | TCP 80 |
| Web Server | XAMPP Apache |
| Certificate Authority | Let's Encrypt |

Replace the example domain and paths with your own environment.

## 2. Prepare the Domain and Network

Before requesting a certificate, make sure:

1. Your domain points to your public IP address.
2. TCP port **80** is forwarded from your router to the Windows machine running XAMPP.
3. Windows Firewall allows inbound TCP port 80.
4. XAMPP Apache is running and accessible through HTTP.

Let's Encrypt uses HTTP-01 validation to verify domain ownership.

**Important:** You only need port 80 for certificate validation. Do not expose Omada management port 8043 directly to the internet.

If you access Omada from inside your local network, you can configure local DNS on your router to point the domain to the Omada server's LAN IP address.

## 3. Install win-acme

Download win-acme from:

https://www.win-acme.com/

1. Download the latest Windows x64 version.
2. Extract the ZIP file.
3. Create a folder:

   ```text
   C:\tools\win-acme
   ```

4. Extract the downloaded files into that folder.
5. Open PowerShell as Administrator.
6. Navigate to the folder:

   ```powershell
   cd C:\tools\win-acme
   ```

7. Run:

   ```powershell
   .\wacs.exe
   ```

The win-acme menu will appear.

## 4. Request a Let's Encrypt Certificate

Follow the interactive menu in win-acme.

The menu wording may differ slightly between versions.

1. Select the option to create a new certificate.
2. Choose the option to enter the domain manually.
3. Enter your domain:

   ```text
   omada.example.com
   ```

4. Select HTTP-01 validation.
5. Configure the validation to use the XAMPP Apache web root:

   ```text
   C:\xampp\htdocs
   ```

6. Choose the PEM files installation/store option.
7. Set the output directory:

   ```text
   C:\certificates\omada
   ```

8. Complete the remaining prompts.

If validation succeeds, win-acme will request and store the certificate.

You should see output indicating that the certificate was successfully created and the PEM files were exported.

## 5. Check the Generated Files

Open:

```text
C:\certificates\omada
```

The generated files should look similar to:

```text
omada.example.com-chain-only.pem
omada.example.com-chain.pem
omada.example.com-crt.pem
omada.example.com-key.pem
```

The important files are:

| File | Description |
|---|---|
| `-crt.pem` | Domain certificate |
| `-key.pem` | Private key |
| `-chain.pem` | Certificate and certificate chain |
| `-chain-only.pem` | Certificate chain without the domain certificate |

Keep the private key secure. Never upload it to GitHub or share it publicly.

## 6. Prepare the Certificate for Omada

For this setup, prepare two files:

- Full chain certificate
- Private key

Create a staging folder:

```powershell
$CertDir = "C:\certificates\omada"
$Stage = "$CertDir\staging"

New-Item -ItemType Directory -Path $Stage -Force
```

Set the source files:

```powershell
$CertFile = "$CertDir\omada.example.com-crt.pem"
$ChainFile = "$CertDir\omada.example.com-chain-only.pem"
$KeyFile = "$CertDir\omada.example.com-key.pem"
```

Extract the first certificate from the chain file. In this example, it is the intermediate certificate:

```powershell
$ChainContent = Get-Content $ChainFile -Raw

$CertBlocks = [regex]::Matches(
    $ChainContent,
    '(?s)-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----'
)

if ($CertBlocks.Count -lt 1) {
    throw "Intermediate certificate not found."
}

$Intermediate = $CertBlocks[0].Value
```

Combine the domain certificate and intermediate certificate:

```powershell
$FullChain = (Get-Content $CertFile -Raw).Trim() +
    "`r`n" +
    $Intermediate.Trim() +
    "`r`n"

[System.IO.File]::WriteAllText(
    "$Stage\omada.example.com-fullchain.pem",
    $FullChain,
    [System.Text.Encoding]::ASCII
)
```

Copy the private key:

```powershell
Copy-Item $KeyFile "$Stage\omada.example.com-key.pem" -Force
```

Your staging folder should now contain:

```text
staging\
├── omada.example.com-fullchain.pem
└── omada.example.com-key.pem
```

The full chain should contain the domain certificate followed by its intermediate certificate. Do not include the root certificate.

**Note:** Certificate chain contents may change. Check the certificate blocks before preparing the full chain rather than assuming the intermediate certificate is always in the same position.

## 7. Validate the Certificate

XAMPP includes OpenSSL. In this example, the executable is:

```powershell
$OpenSSL = "C:\xampp\apache\bin\openssl.exe"
```

Set the certificate paths:

```powershell
$FullChain = "C:\certificates\omada\staging\omada.example.com-fullchain.pem"
$KeyFile = "C:\certificates\omada\staging\omada.example.com-key.pem"
```

Check the certificate details:

```powershell
& $OpenSSL x509 -in $FullChain -noout -subject -issuer -dates
```

Check the domain name:

```powershell
& $OpenSSL x509 -in $FullChain -noout -checkhost omada.example.com
```

Check the private key:

```powershell
& $OpenSSL pkey -in $KeyFile -check -noout
```

Continue only if the certificate and private key checks succeed.

## 8. Import the Certificate into Omada

Open the Omada Software Controller administration interface.

Navigate to the certificate or HTTPS configuration section. The exact menu location may vary depending on the controller version.

Upload:

| Omada field | File |
|---|---|
| Certificate / Full Chain | `omada.example.com-fullchain.pem` |
| Private Key | `omada.example.com-key.pem` |

Save or apply the configuration.

Restart the controller service if required by your Omada version.

Then access Omada using:

```text
https://omada.example.com:8043
```

Check the browser certificate information to confirm that the new certificate is being served.

## 9. Configure Automatic Renewal

win-acme creates a renewal configuration after successfully requesting the certificate.

It also supports automatic renewal through Windows Task Scheduler.

Check the existing renewal configuration:

```powershell
cd C:\tools\win-acme
.\wacs.exe --list
```

To check renewal manually:

```powershell
.\wacs.exe --renew
```

The renewal command checks the configured certificates and renews certificates when they are due. It does not issue a new certificate every time it runs.

### Windows Task Scheduler

Open Task Scheduler and look for the task created by win-acme:

```text
win-acme renew (acme-v02.api.letsencrypt.org)
```

The task runs a command similar to:

```powershell
C:\tools\win-acme\wacs.exe --renew --baseuri "https://acme-v02.api.letsencrypt.org/"
```

You can review the task's trigger and execution settings in Task Scheduler.

**Important:** Automatic renewal updates the certificate files. It does not automatically guarantee that Omada is using the renewed certificate. The new PEM files must also be deployed to Omada.

## 10. After Certificate Renewal

After win-acme renews the certificate:

1. Check the new certificate files in the output directory.
2. Prepare the updated full chain and private key.
3. Validate the certificate and key.
4. Back up the currently deployed certificate if needed.
5. Import the new files into Omada.
6. Verify the certificate served by Omada.

You can inspect the certificate currently served on port 8043 using OpenSSL:

```powershell
$OpenSSL = "C:\xampp\apache\bin\openssl.exe"

"" | & $OpenSSL s_client `
    -connect 127.0.0.1:8043 `
    -servername omada.example.com 2>$null |
    & $OpenSSL x509 -noout -subject -issuer -dates
```

You can also check the portal HTTPS port 8843:

```powershell
"" | & $OpenSSL s_client `
    -connect 127.0.0.1:8843 `
    -servername omada.example.com 2>$null |
    & $OpenSSL x509 -noout -subject -issuer -dates
```

Check that the displayed certificate dates and issuer match the renewed certificate.

## 11. Security Notes

- Never upload private key files (`*-key.pem`) to GitHub.
- Do not expose Omada management ports directly to the public internet.
- Keep a backup of the certificate and private key in a secure location.
- Monitor the win-acme renewal task.
- Remember that certificate renewal and Omada certificate deployment are separate steps.
- Do not publish real domains, public IP addresses, private keys, or account credentials in your repository.

## Conclusion

With win-acme and Let's Encrypt, you can obtain a free SSL certificate for TP-Link Omada Software Controller on Windows 11.

The process is straightforward:

1. Prepare the domain and HTTP port 80.
2. Install win-acme.
3. Request a Let's Encrypt certificate.
4. Export the PEM files.
5. Prepare and validate the full chain and private key.
6. Import the certificate into Omada.
7. Configure automatic renewal and deploy renewed certificates when needed.

This approach provides a practical way to manage SSL certificates for a self-hosted Omada Controller without purchasing a commercial certificate.
