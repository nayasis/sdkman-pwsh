#
#   PowerShell port of SDKMAN! - sdkman-utils.sh
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#

# Thrown to abort the current sdk command after an error message has been printed.
$script:SdkmanStop = 'SDKMAN_STOP'

function Stop-SdkmanCommand {
    throw $script:SdkmanStop
}

function Test-SdkmanConfig([string]$Key) {
    return $script:Config[$Key] -eq 'true'
}

function Write-SdkmanColour([string]$Message, [ConsoleColor]$Colour) {
    if ($script:Config['sdkman_colour_enable'] -eq 'false') {
        Write-Host $Message
    } else {
        Write-Host $Message -ForegroundColor $Colour
    }
}

function Write-SdkmanRed([string]$Message) { Write-SdkmanColour $Message Red }

function Write-SdkmanYellow([string]$Message) { Write-SdkmanColour $Message Yellow }

function Write-SdkmanGreen([string]$Message) { Write-SdkmanColour $Message Green }

function Write-SdkmanCyan([string]$Message) { Write-SdkmanColour $Message Cyan }

function Write-SdkmanNoColour([string]$Message) { Write-Host $Message }

function Write-SdkmanDebug([string]$Message) {
    if (Test-SdkmanConfig 'sdkman_debug_mode') {
        Write-Host $Message -ForegroundColor DarkGray
    }
}

function Read-SdkmanConfirm([string]$Prompt) {
    if ($script:Config['sdkman_colour_enable'] -eq 'false') {
        Write-Host $Prompt -NoNewline
    } else {
        Write-Host $Prompt -NoNewline -ForegroundColor Yellow
    }
    return Read-Host
}

function Write-SdkmanPaged([string]$Text) {
    if ($env:PAGER) {
        $Text | & ([scriptblock]::Create("`$input | $env:PAGER"))
    } else {
        $Text -split "`r?`n"
    }
}

function Import-SdkmanConfig {
    $config = @{
        sdkman_auto_answer          = 'false'
        sdkman_auto_complete        = 'true'
        sdkman_auto_env             = 'false'
        sdkman_beta_channel         = 'false'
        sdkman_checksum_enable      = 'true'
        sdkman_colour_enable        = 'true'
        sdkman_curl_connect_timeout = '7'
        sdkman_curl_max_time        = '10'
        sdkman_curl_retry           = '0'
        sdkman_debug_mode           = 'false'
        sdkman_insecure_ssl         = 'false'
    }

    $file = [IO.Path]::Combine($script:SdkmanDir, 'etc', 'config')
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $file) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
                $config[$Matches[1]] = $Matches[2].Trim('"', "'")
            }
        }
    }

    $script:Config = $config
}

function Import-SdkmanCandidates {
    $script:CandidatesCsv = ''
    if (Test-Path -LiteralPath $script:CandidatesCache -PathType Leaf) {
        $script:CandidatesCsv = ([IO.File]::ReadAllText($script:CandidatesCache)).Trim()
    }
    $script:Candidates = @($script:CandidatesCsv -split ',' | Where-Object { $_ })
}

function Write-SdkmanTextFile([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding $false))
}

function New-SdkmanDirectory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-SdkmanFullPath([string]$Path) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}
