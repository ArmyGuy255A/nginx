#requires -Version 7.0
<#
.SYNOPSIS
    Builds the appeid.app PFX from a cert + private key + intermediate
    chain and uploads it (plus the standalone chain certs) into the
    appeid-edge Key Vault.

.DESCRIPTION
    This is the one-time manual step in the appeid-edge cutover. Run it
    after `terraform apply -var "bind_custom_domain=false"` has provisioned
    the Key Vault, but before the second-pass apply that binds the apex
    custom domains.

    Steps performed:
      1. Validate the four input files exist + match (cert <-> key, cert
         <-> intermediate chain).
      2. Build a password-less PFX bundle (cert + key + intermediate). The
         root cert is NOT bundled — clients have it in their trust store.
      3. Import the PFX into the KV as a Certificate named -PfxCertificateName
         (default: appeid-tls). ACA env-cert resource reads this via TF.
      4. Import the intermediate and root as separate KV Certificates so
         they're available standalone for future mTLS / audit use.

    Idempotent: re-running with the same files is a no-op for KV; new
    inputs roll a new KV Certificate version.

.PARAMETER KeyVaultName
    Target Key Vault. Get with:
      terraform -chdir=terraform/prod output -raw key_vault_name

.PARAMETER CertPath
    Path to the leaf cert (PEM/CRT). E.g. ...\appeid.app-certificate.crt.

.PARAMETER KeyPath
    Path to the private key (PEM). You retrieved this from GoDaddy.

.PARAMETER IntermediatePath
    Path to the intermediate CA bundle (PEM). E.g.
    ...\appeid.app-intermediate.pem.

.PARAMETER RootPath
    Optional. Path to the root CA cert (PEM). Uploaded for completeness;
    not bundled in the PFX.

.PARAMETER PfxCertificateName
    KV Certificate name to import the PFX under. Must match
    var.pfx_certificate_name in terraform/prod (default: appeid-tls).

.PARAMETER OpenSslPath
    Optional path to openssl.exe. Defaults to PATH lookup.

.EXAMPLE
    .\upload-certs.ps1 `
        -KeyVaultName kv-appeid-edge-abc123 `
        -CertPath  D:\certs\appeid.app-certificate.crt `
        -KeyPath   D:\certs\appeid.app.key `
        -IntermediatePath D:\certs\appeid.app-intermediate.pem `
        -RootPath D:\certs\appeid.app-root.pem
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $KeyVaultName,
    [Parameter(Mandatory)] [string] $CertPath,
    [Parameter(Mandatory)] [string] $KeyPath,
    [Parameter(Mandatory)] [string] $IntermediatePath,
    [string] $RootPath,
    [string] $PfxCertificateName     = "appeid-tls",
    [string] $IntermediateCertName   = "appeid-ca-intermediate",
    [string] $RootCertName           = "appeid-ca-root",
    [string] $OpenSslPath
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath {
    param([string] $Path)
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    return (Resolve-Path $Path).Path
}

function Invoke-Az {
    param([Parameter(ValueFromRemainingArguments)] $Args)
    & az @Args
    if ($LASTEXITCODE -ne 0) { throw "az $($Args -join ' ') exited $LASTEXITCODE" }
}

# 1. Validate inputs ───────────────────────────────────────────────────
$CertPath         = Resolve-FullPath $CertPath
$KeyPath          = Resolve-FullPath $KeyPath
$IntermediatePath = Resolve-FullPath $IntermediatePath
if ($RootPath) { $RootPath = Resolve-FullPath $RootPath }

if (-not $OpenSslPath) {
    $OpenSslPath = (Get-Command openssl -ErrorAction SilentlyContinue)?.Path
    if (-not $OpenSslPath) {
        throw "openssl not found on PATH. Install OpenSSL or pass -OpenSslPath."
    }
}

Write-Host "[1/5] Validating cert <-> key match" -ForegroundColor Cyan
$certModulus = (& $OpenSslPath x509  -noout -modulus -in $CertPath) | Out-String
$keyModulus  = (& $OpenSslPath rsa   -noout -modulus -in $KeyPath ) | Out-String
if ($certModulus.Trim() -ne $keyModulus.Trim()) {
    throw "Private key does not match the public cert (modulus mismatch)."
}

Write-Host "[2/5] Validating chain (cert issued by intermediate)" -ForegroundColor Cyan
$verify = & $OpenSslPath verify -CAfile $IntermediatePath $CertPath 2>&1
if ($LASTEXITCODE -ne 0) {
    # `verify` exits non-zero for self-signed roots etc., but it'll print
    # `OK` on the cert line we care about. Filter to that signal.
    if ($verify -notmatch ': OK\b') {
        throw "Chain validation failed: $verify"
    }
}

# 2. Build a password-less PFX ────────────────────────────────────────
$tmp = New-TemporaryFile
$pfxPath = "$($tmp.FullName).pfx"
Remove-Item $tmp -Force

Write-Host "[3/5] Building PFX at $pfxPath" -ForegroundColor Cyan
& $OpenSslPath pkcs12 -export `
    -out      $pfxPath `
    -inkey    $KeyPath `
    -in       $CertPath `
    -certfile $IntermediatePath `
    -passout  "pass:"
if ($LASTEXITCODE -ne 0) { throw "openssl pkcs12 -export failed" }

# 3. Upload the PFX as a KV Certificate ───────────────────────────────
Write-Host "[4/5] Importing PFX into $KeyVaultName/$PfxCertificateName" -ForegroundColor Cyan
Invoke-Az keyvault certificate import `
    --vault-name $KeyVaultName `
    --name       $PfxCertificateName `
    --file       $pfxPath `
    --password   "" `
    --output table

Remove-Item $pfxPath -Force

# 4. Upload standalone chain certs ───────────────────────────────────
Write-Host "[5/5] Importing standalone chain certs" -ForegroundColor Cyan
Invoke-Az keyvault certificate import `
    --vault-name $KeyVaultName `
    --name       $IntermediateCertName `
    --file       $IntermediatePath `
    --output table

if ($RootPath) {
    Invoke-Az keyvault certificate import `
        --vault-name $KeyVaultName `
        --name       $RootCertName `
        --file       $RootPath `
        --output table
}

Write-Host ""
Write-Host "Done. Next:" -ForegroundColor Green
Write-Host "  cd ..\prod"
Write-Host "  terraform apply -var ""bind_custom_domain=true"" \\"
Write-Host "                  -var ""swa_upstream=<the SWA default hostname>"""
