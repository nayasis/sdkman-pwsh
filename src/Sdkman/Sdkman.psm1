#
#   PowerShell port of SDKMAN! - sdkman-main.sh and sdkman-init.sh
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#

Set-StrictMode -Version 2.0

foreach ($file in Get-ChildItem -LiteralPath ([IO.Path]::Combine($PSScriptRoot, 'lib')) -Filter 'sdkman-*.ps1') {
    . $file.FullName
}

$script:SdkmanVersion = (Import-PowerShellDataFile -LiteralPath ([IO.Path]::Combine($PSScriptRoot, 'Sdkman.psd1'))).ModuleVersion

$script:CommandAliases = @{
    l  = 'list'
    ls = 'list'
    v  = 'version'
    u  = 'use'
    i  = 'install'
    rm = 'uninstall'
    c  = 'current'
    ug = 'upgrade'
    d  = 'default'
    h  = 'home'
    e  = 'env'
}

$script:Commands = [ordered]@{
    install   = { Invoke-SdkInstall $Qualifier $Version $Folder }
    uninstall = { Invoke-SdkUninstall $Qualifier $Version }
    list      = { Invoke-SdkList $Qualifier }
    use       = { Invoke-SdkUse $Qualifier $Version }
    config    = { Invoke-SdkConfig }
    default   = { Invoke-SdkDefault $Qualifier $Version }
    home      = { Invoke-SdkHome $Qualifier $Version }
    env       = { Invoke-SdkEnv $Qualifier }
    current   = { Invoke-SdkCurrent $Qualifier }
    upgrade   = { Invoke-SdkUpgrade $Qualifier }
    version   = { Invoke-SdkVersion }
    help      = { Invoke-SdkHelp }
    offline   = { Invoke-SdkOffline $Qualifier }
    update    = { Invoke-SdkUpdate }
    flush     = { Invoke-SdkFlush $Qualifier }
}

# Commands whose qualifier must be a known candidate
$script:CandidateCommands = @('install', 'uninstall', 'list', 'use', 'default', 'home', 'current', 'upgrade')

function sdk {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Command,
        [Parameter(Position = 1)][string]$Qualifier,
        [Parameter(Position = 2)][string]$Version,
        [Parameter(Position = 3)][string]$Folder
    )

    $ErrorActionPreference = 'Stop'
    $global:LASTEXITCODE = 0

    if ($script:CommandAliases.Contains($Command)) {
        $Command = $script:CommandAliases[$Command]
    }

    # Load the sdkman config and candidates cache if they exist.
    Import-SdkmanConfig
    Import-SdkmanCandidates

    # Check candidates cache
    if ($Command -ne 'update' -and -not (Test-SdkmanCandidatesCache)) {
        $global:LASTEXITCODE = 1
        return
    }

    # Always presume internet availability, unless proven otherwise
    $script:Available = $true
    Update-SdkmanServiceAvailability $Command $Qualifier

    # no command provided
    if (-not $Command) {
        Invoke-SdkHelp
        $global:LASTEXITCODE = 1
        return
    }

    if (-not $script:Commands.Contains($Command)) {
        Write-Host ''
        Write-SdkmanRed "Invalid command: $Command"
        Write-Host ''
        Invoke-SdkHelp
        $global:LASTEXITCODE = 1
        return
    }

    # Validate offline qualifier
    if ($Command -eq 'offline' -and $Qualifier -and @('enable', 'disable') -notcontains $Qualifier) {
        Write-Host ''
        Write-SdkmanRed "Stop! $Qualifier is not a valid offline mode."
        $global:LASTEXITCODE = 1
        return
    }

    # Check whether the candidate exists
    if ($Qualifier -and $script:CandidateCommands -contains $Command -and $script:Candidates -cnotcontains $Qualifier) {
        Write-Host ''
        Write-SdkmanRed "Stop! $Qualifier is not a valid candidate."
        $global:LASTEXITCODE = 1
        return
    }

    try {
        & $script:Commands[$Command]
    } catch {
        if ($_.Exception.Message -ne $script:SdkmanStop) {
            Write-SdkmanRed "Stop! $($_.Exception.Message)"
            Write-SdkmanDebug $_.ScriptStackTrace
        }
        $global:LASTEXITCODE = 1
    }
}

#
# Initialisation (sdkman-init.sh)
#

if (-not $env:SDKMAN_CANDIDATES_API) {
    $env:SDKMAN_CANDIDATES_API = 'https://api.sdkman.io/2'
}

if (-not $env:SDKMAN_BROKER_API) {
    $env:SDKMAN_BROKER_API = 'https://broker.sdkman.io'
}

if (-not $env:SDKMAN_DIR) {
    $env:SDKMAN_DIR = [IO.Path]::Combine($HOME, '.sdkman')
}

$script:SdkmanDir = (Get-SdkmanFullPath $env:SDKMAN_DIR).TrimEnd('\')
$script:CandidatesApi = $env:SDKMAN_CANDIDATES_API.TrimEnd('/')
$script:BrokerApi = $env:SDKMAN_BROKER_API.TrimEnd('/')
$script:CandidatesDir = [IO.Path]::Combine($script:SdkmanDir, 'candidates')
$script:CandidatesCache = [IO.Path]::Combine($script:SdkmanDir, 'var', 'candidates')
$script:OfflineMode = $false
$script:Available = $true
$script:AutoAnswerUpgrade = $false
$script:SdkmanEnv = ''
$script:SdkmanOldPwd = ''

$platformFile = [IO.Path]::Combine($script:SdkmanDir, 'var', 'platform')
$script:Platform = 'windowsx64'
if (Test-Path -LiteralPath $platformFile -PathType Leaf) {
    $script:Platform = ([IO.File]::ReadAllText($platformFile)).Trim()
}

$env:SDKMAN_DIR = $script:SdkmanDir
$env:SDKMAN_PLATFORM = $script:Platform
$env:SDKMAN_CANDIDATES_DIR = $script:CandidatesDir

Import-SdkmanConfig
Import-SdkmanCandidates

foreach ($candidateName in $script:Candidates) {
    $candidateDir = Get-SdkmanCandidateDir $candidateName 'current'
    if (Test-Path -LiteralPath $candidateDir -PathType Container) {
        Set-SdkmanCandidateHome $candidateName $candidateDir
        Add-SdkmanCandidateDirToPath $candidateDir
    }
}

if (Test-SdkmanConfig 'sdkman_auto_complete') {
    . ([IO.Path]::Combine($PSScriptRoot, 'completion.ps1'))
}

if (Test-SdkmanConfig 'sdkman_auto_env') {
    if (-not (Get-Variable -Name __SdkmanOriginalPrompt -Scope Global -ErrorAction SilentlyContinue)) {
        $global:__SdkmanOriginalPrompt = $function:global:prompt
        Set-Item -Path function:global:prompt -Value {
            Invoke-SdkmanAutoEnv
            & $global:__SdkmanOriginalPrompt
        }
    }
}

$ExecutionContext.SessionState.Module.OnRemove = {
    if (Get-Variable -Name __SdkmanOriginalPrompt -Scope Global -ErrorAction SilentlyContinue) {
        Set-Item -Path function:global:prompt -Value $global:__SdkmanOriginalPrompt
        Remove-Variable -Name __SdkmanOriginalPrompt -Scope Global
    }
    foreach ($client in $script:HttpClients.Values) {
        $client.Dispose()
    }
}
