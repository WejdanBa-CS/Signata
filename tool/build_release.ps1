# Builds a Play-ready Android App Bundle with Google Sign-In configured.
#
# Prerequisites:
# 1. Copy google_oauth.example.env → google_oauth.env and set GOOGLE_SERVER_CLIENT_ID
# 2. android/key.properties + android/upload-keystore.jks (created locally)
# 3. Google Cloud Android OAuth client with debug + release SHA-1s

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$envFile = Join-Path $root 'google_oauth.env'
if (-not (Test-Path $envFile)) {
  Write-Host 'Missing google_oauth.env'
  Write-Host 'Copy google_oauth.example.env to google_oauth.env and paste your Web client ID.'
  exit 1
}

$content = Get-Content $envFile -Raw
if ($content -notmatch 'GOOGLE_SERVER_CLIENT_ID=.+\.apps\.googleusercontent\.com' -or
    $content -match 'YOUR_WEB_CLIENT_ID') {
  Write-Host 'google_oauth.env still has a placeholder Web client ID.'
  Write-Host 'Paste the real Web OAuth client ID from Google Cloud Console.'
  exit 1
}

$keyProps = Join-Path $root 'android\key.properties'
$keystore = Join-Path $root 'android\upload-keystore.jks'
if (-not (Test-Path $keyProps) -or -not (Test-Path $keystore)) {
  Write-Host 'Missing release signing files (android/key.properties or upload-keystore.jks).'
  exit 1
}

$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path','User')

Write-Host 'Building release App Bundle…'
flutter build appbundle --release --dart-define-from-file=google_oauth.env

$aab = Join-Path $root 'build\app\outputs\bundle\release\app-release.aab'
if (Test-Path $aab) {
  Write-Host ''
  Write-Host "Ready for Play Console: $aab"
  Write-Host 'After first upload, add Play App Signing SHA-1 to the Android OAuth client.'
} else {
  Write-Host 'Build finished but AAB was not found.'
  exit 1
}
