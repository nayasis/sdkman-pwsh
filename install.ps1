#
#   Installer for the PowerShell port of SDKMAN!
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
<#
.SYNOPSIS
    Installs the SDKMAN! PowerShell module and hooks it into the PowerShell profiles.
.PARAMETER SdkmanDir
    SDKMAN home. Defaults to $env:SDKMAN_DIR or ~\.sdkman (shared with an existing bash install).
.PARAMETER NoProfile
    Do not modify the PowerShell profiles.
#>
[CmdletBinding()]
param(
    [string]$SdkmanDir = $(if ($env:SDKMAN_DIR) { $env:SDKMAN_DIR } else { Join-Path $HOME '.sdkman' }),
    [switch]$NoProfile
)

$ErrorActionPreference = 'Stop'
# Resolve relative paths against the PowerShell location, not the process working directory
$SdkmanDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SdkmanDir).TrimEnd('\')
$candidatesApi = if ($env:SDKMAN_CANDIDATES_API) { $env:SDKMAN_CANDIDATES_API.TrimEnd('/') } else { 'https://api.sdkman.io/2' }
$utf8 = New-Object System.Text.UTF8Encoding $false

Write-Host ''
Write-Host 'Installing SDKMAN! for PowerShell...' -ForegroundColor Cyan
Write-Host "SDKMAN_DIR: $SdkmanDir"

foreach ($dir in 'candidates', 'tmp', 'ext', 'etc', 'var', 'var\metadata', 'pwsh') {
    New-Item -ItemType Directory -Path (Join-Path $SdkmanDir $dir) -Force | Out-Null
}

$platformFile = Join-Path $SdkmanDir 'var\platform'
if (-not (Test-Path -LiteralPath $platformFile)) {
    [IO.File]::WriteAllText($platformFile, "windowsx64`n", $utf8)
}

$configFile = Join-Path $SdkmanDir 'etc\config'
if (-not (Test-Path -LiteralPath $configFile)) {
    $config = @(
        'sdkman_auto_answer=false'
        'sdkman_auto_complete=true'
        'sdkman_auto_env=false'
        'sdkman_beta_channel=false'
        'sdkman_checksum_enable=true'
        'sdkman_colour_enable=true'
        'sdkman_curl_connect_timeout=7'
        'sdkman_curl_max_time=10'
        'sdkman_curl_retry=0'
        'sdkman_debug_mode=false'
        'sdkman_insecure_ssl=false'
    ) -join "`n"
    [IO.File]::WriteAllText($configFile, "$config`n", $utf8)
}

$candidatesFile = Join-Path $SdkmanDir 'var\candidates'
if (-not (Test-Path -LiteralPath $candidatesFile) -or -not ([IO.File]::ReadAllText($candidatesFile).Trim())) {
    Write-Host 'Fetching candidate list...'
    if ($PSVersionTable.PSEdition -ne 'Core') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    $candidates = (Invoke-WebRequest -Uri "$candidatesApi/candidates/all" -UseBasicParsing).Content.Trim()
    [IO.File]::WriteAllText($candidatesFile, "$candidates`n", $utf8)
}

$moduleDir = Join-Path $SdkmanDir 'pwsh\Sdkman'
if (Test-Path -LiteralPath $moduleDir) {
    Remove-Item -LiteralPath $moduleDir -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src\Sdkman') -Destination $moduleDir -Recurse
Get-ChildItem -LiteralPath $moduleDir -Recurse -File | Unblock-File

$manifest = Join-Path $moduleDir 'Sdkman.psd1'
$marker = '# >>> sdkman (PowerShell) >>>'
$snippet = @(
    $marker
    "`$env:SDKMAN_DIR = '$($SdkmanDir.Replace("'", "''"))'"
    "Import-Module '$($manifest.Replace("'", "''"))'"
    '# <<< sdkman (PowerShell) <<<'
) -join [Environment]::NewLine

if (-not $NoProfile) {
    # Windows PowerShell 5.1 and PowerShell 7 keep separate profiles
    $documents = [Environment]::GetFolderPath('MyDocuments')
    foreach ($profileDir in 'WindowsPowerShell', 'PowerShell') {
        $profilePath = Join-Path $documents "$profileDir\profile.ps1"
        $content = ''
        if (Test-Path -LiteralPath $profilePath) {
            $content = [IO.File]::ReadAllText($profilePath)
        }
        if ($content.Contains($marker)) {
            Write-Host "Profile already configured: $profilePath"
            continue
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
        $separator = if ($content -and -not $content.EndsWith("`n")) { [Environment]::NewLine } else { '' }
        [IO.File]::WriteAllText($profilePath, $content + $separator + $snippet + [Environment]::NewLine, $utf8)
        Write-Host "Updated profile: $profilePath"
    }
}

$policy = try { [string](Get-ExecutionPolicy) } catch { '' }
if ($policy -in 'Restricted', 'AllSigned') {
    Write-Host ''
    Write-Host "The current execution policy ($policy) prevents profiles and modules from loading. Run:" -ForegroundColor Yellow
    Write-Host '    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned' -ForegroundColor Yellow
}

# Load the module into the calling session too, so `sdk` works without opening a new window
$loaded = $false
try {
    $env:SDKMAN_DIR = $SdkmanDir
    Import-Module $manifest -Global -Force
    $loaded = $true
} catch {
    Write-Host ''
    Write-Host "Could not load the module into this session: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'All done!' -ForegroundColor Green
Write-Host ''
if ($NoProfile) {
    Write-Host 'Add the following to your PowerShell profile:'
    Write-Host ''
    Write-Host $snippet
    Write-Host ''
}
if ($loaded) {
    Write-Host 'The sdk command is ready to use in this session.'
} else {
    Write-Host 'Open a new PowerShell window, or run the following in this one:'
    Write-Host ''
    Write-Host "    Import-Module '$manifest'"
}
Write-Host ''
Write-Host 'Try:'
Write-Host '    sdk version'
Write-Host '    sdk list java'
Write-Host ''
