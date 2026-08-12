# Debug-run Signata on a connected device/emulator.
# Uses google_oauth.env when present so Google Sign-In works without a release build.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path','User')

$envFile = Join-Path $root 'google_oauth.env'
$flutterArgs = @('run')
if ((Test-Path $envFile) -and
    ((Get-Content $envFile -Raw) -notmatch 'YOUR_WEB_CLIENT_ID')) {
  Write-Host "Using $envFile"
  $flutterArgs += '--dart-define-from-file=google_oauth.env'
} else {
  Write-Host 'No google_oauth.env — Google button stays hidden; email login works.'
}

flutter @flutterArgs
