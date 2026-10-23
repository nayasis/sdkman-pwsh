#
#   Uninstaller for the PowerShell port of SDKMAN!
#
<#
.SYNOPSIS
    Removes the SDKMAN! PowerShell module and its profile hooks.
    Installed candidates, configuration and caches in SDKMAN_DIR are kept
    unless -RemoveSdkmanDir is given.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SdkmanDir = $(if ($env:SDKMAN_DIR) { $env:SDKMAN_DIR } else { Join-Path $HOME '.sdkman' }),
    [switch]$RemoveSdkmanDir
)

$ErrorActionPreference = 'Stop'
# Resolve relative paths against the PowerShell location, not the process working directory
$SdkmanDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SdkmanDir).TrimEnd('\')
$utf8 = New-Object System.Text.UTF8Encoding $false

Remove-Module Sdkman -ErrorAction SilentlyContinue

$documents = [Environment]::GetFolderPath('MyDocuments')
foreach ($profileDir in 'WindowsPowerShell', 'PowerShell') {
    $profilePath = Join-Path $documents "$profileDir\profile.ps1"
    if (-not (Test-Path -LiteralPath $profilePath)) {
        continue
    }
    $content = [IO.File]::ReadAllText($profilePath)
    $cleaned = [regex]::Replace($content, '(?s)# >>> sdkman \(PowerShell\) >>>.*?# <<< sdkman \(PowerShell\) <<<\r?\n?', '')
    if ($cleaned -ne $content -and $PSCmdlet.ShouldProcess($profilePath, 'Remove sdkman hook')) {
        [IO.File]::WriteAllText($profilePath, $cleaned, $utf8)
        Write-Host "Updated profile: $profilePath"
    }
}

$moduleDir = Join-Path $SdkmanDir 'pwsh'
if ($RemoveSdkmanDir) {
    # Remove 'current' junctions first so that recursive deletion never follows them
    Get-ChildItem -LiteralPath (Join-Path $SdkmanDir 'candidates') -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -Force } |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
        ForEach-Object { if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove link')) { [IO.Directory]::Delete($_.FullName) } }
    if ($PSCmdlet.ShouldProcess($SdkmanDir, 'Remove directory')) {
        Remove-Item -LiteralPath $SdkmanDir -Recurse -Force
    }
} elseif ((Test-Path -LiteralPath $moduleDir) -and $PSCmdlet.ShouldProcess($moduleDir, 'Remove directory')) {
    Remove-Item -LiteralPath $moduleDir -Recurse -Force
}

Write-Host 'SDKMAN! for PowerShell has been uninstalled. Open a new PowerShell window.' -ForegroundColor Green
