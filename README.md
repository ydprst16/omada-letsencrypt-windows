# Install Let's Encrypt SSL Certificate on TP-Link Omada Controller (Windows 11)

This guide shows how to install a free SSL certificate from Let's Encrypt on TP-Link Omada Software Controller running on Windows 11.

We will use:

- **win-acme** – to get and renew the SSL certificate.
- **Let's Encrypt** – to provide the free SSL certificate.
- **XAMPP Apache** – to verify domain ownership.
- **OpenSSL** – to check the certificate.
- **Omada Controller** – to use the certificate.

## 1. What You Need

Before starting, prepare:

- Windows 11 computer.
- TP-Link Omada Software Controller installed.
- A domain name pointing to your public IP address.
- XAMPP installed and Apache running.
- Router access to configure port forwarding.

Example setup:

| Item | Example |
|---|---|
| Domain | `omada.example.com` |
| Omada HTTPS | `8043` |
| Portal HTTPS | `8843` |
| HTTP validation | `80` |
| XAMPP web root | `C:\xampp\htdocs` |

**Important:** Port 80 must be accessible from the internet for Let's Encrypt verification. You do not need to expose Omada port 8043 to the internet.

## 2. Configure Your Network

Before requesting the certificate:

1. Point your domain to your public IP address.
2. Forward TCP port 80 on your router to your Windows computer.
3. Allow TCP port 80 in Windows Firewall.
4. Start Apache from XAMPP.

Let's Encrypt will use port 80 to check whether you own the domain.

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

## 4. Request a Certificate

Follow the win-acme menu.

The menu names may be slightly different depending on your win-acme version.

1. Select **Create new certificate**.
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

If everything works, win-acme will request the certificate and save the PEM files.

## 5. Check the Certificate Files

Open this folder:

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

The files we need are:

| File | Purpose |
|---|---|
| `-crt.pem` | Domain certificate |
| `-key.pem` | Private key |
| `-chain-only.pem` | Intermediate and root certificates |
| `-chain.pem` | Domain certificate and certificate chain |

Keep the private key safe. Never upload it to GitHub.

## 6. Prepare the Certificate for Omada

Omada needs the certificate chain and private key.

First, create a staging folder:

```powershell
$CertDir = "C:\certificates\omada"
$Stage = "$CertDir\staging"

New-Item -ItemType Directory -Path $Stage -Force
```

Set the file paths:

```powershell
$CertFile = "$CertDir\omada.example.com-crt.pem"
$ChainFile = "$CertDir\omada.example.com-chain-only.pem"
$KeyFile = "$CertDir\omada.example.com-key.pem"
```

Prepare the full chain:

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

$FullChain = (Get-Content $CertFile -Raw).Trim() +
    "`r`n" +
    $Intermediate.Trim() +
    "`r`n"

[System.IO.File]::WriteAllText(
    "$Stage\omada.example.com-fullchain.pem",
    $FullChain,
    [System.Text.Encoding]::ASCII
)

Copy-Item $KeyFile "$Stage\omada.example.com-key.pem" -Force
```

The staging folder should contain:

```text
staging/
├── omada.example.com-fullchain.pem
└── omada.example.com-key.pem
```

The full chain contains the domain certificate and its intermediate certificate. The root certificate is not included.

**Note:** Check the certificate order before using this command. The intermediate certificate may not always be in the same position.

## 7. Check the Certificate

XAMPP includes OpenSSL.

Open PowerShell and run:

```powershell
$OpenSSL = "C:\xampp\apache\bin\openssl.exe"
```

Check the certificate:

```powershell
& $OpenSSL x509 `
  -in "C:\certificates\omada\staging\omada.example.com-fullchain.pem" `
  -noout -subject -issuer -dates
```

Check the domain:

```powershell
& $OpenSSL x509 `
  -in "C:\certificates\omada\staging\omada.example.com-fullchain.pem" `
  -noout -checkhost omada.example.com
```

Check the private key:

```powershell
& $OpenSSL pkey `
  -in "C:\certificates\omada\staging\omada.example.com-key.pem" `
  -check -noout
```

If the checks are successful, the files are ready to be imported into Omada.

## 8. Import the Certificate into Omada

Open your Omada Controller.

Go to the certificate or HTTPS configuration page. The menu location may depend on your Omada version.

Upload these two files:

| Omada field | File |
|---|---|
| Certificate / Full Chain | `omada.example.com-fullchain.pem` |
| Private Key | `omada.example.com-key.pem` |

Save the configuration.

Restart the Omada Controller service if required.

Open your Omada Controller using:

```text
https://omada.example.com:8043
```

Check the browser's certificate information to confirm that the new certificate is active.

## 9. Automatic Certificate Renewal

win-acme creates a renewal configuration after the first successful certificate request.

It also creates a scheduled task in Windows Task Scheduler.

To check your certificate renewal configuration, run:

```powershell
cd C:\tools\win-acme
.\wacs.exe --list
```

To check for certificates that are due for renewal:

```powershell
.\wacs.exe --renew
```

You do not need to renew the certificate every day. win-acme checks the renewal configuration and renews certificates when they are due.

Open **Windows Task Scheduler** and look for:

```text
win-acme renew (acme-v02.api.letsencrypt.org)
```

This task runs the renewal command automatically.

### Important: Renewal Is Not the Same as Omada Deployment

win-acme can renew and update the PEM files, but this does not automatically mean Omada is using the new certificate.

After renewal, you still need to:

1. Prepare the updated full chain and private key.
2. Check the certificate.
3. Import the new files into Omada.
4. Verify that Omada is serving the new certificate.

## 10. Verify the Certificate Used by Omada

You can check the certificate served by Omada using OpenSSL.

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

Check the issuer and expiration date.

## 11. Final Notes

- Let's Encrypt certificates are free.
- win-acme handles certificate requests and renewal.
- XAMPP Apache handles HTTP-01 validation in this setup.
- OpenSSL helps check the certificate and private key.
- Omada must be updated with the renewed certificate.
- Never share your private key.
- Do not upload real certificates or private keys to a public GitHub repository.

## Conclusion

You can use win-acme and Let's Encrypt to secure your TP-Link Omada Software Controller with a free SSL certificate.

The process is simple:

1. Prepare your domain and port 80.
2. Install win-acme.
3. Request the certificate.
4. Prepare the PEM files.
5. Import the certificate into Omada.
6. Let win-acme check and renew the certificate when needed.

This setup is useful for anyone running Omada Software Controller on Windows 11.
