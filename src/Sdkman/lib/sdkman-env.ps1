#
#   PowerShell port of SDKMAN! - sdkman-env.sh
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#

$script:SdkmanRc = '.sdkmanrc'

function Invoke-SdkEnv([string]$Subcommand) {
    $sdkmanrc = Get-SdkmanFullPath $script:SdkmanRc

    switch ($Subcommand) {
        '' { Import-SdkmanEnv $sdkmanrc }
        'init' { New-SdkmanEnvFile $sdkmanrc }
        'install' { Install-SdkmanEnv $sdkmanrc }
        'clear' { Clear-SdkmanEnv }
        default {
            Write-SdkmanRed "Stop! $Subcommand is not a valid env subcommand."
            Stop-SdkmanCommand
        }
    }
}

function Assert-SdkmanEnvFile([string]$Sdkmanrc) {
    if (-not (Test-Path -LiteralPath $Sdkmanrc -PathType Leaf)) {
        Write-SdkmanRed "Could not find $script:SdkmanRc in the current directory."
        Write-Host ''
        Write-SdkmanYellow "Run 'sdk env init' to create it."
        Stop-SdkmanCommand
    }
}

function Install-SdkmanEnv([string]$Sdkmanrc) {
    Assert-SdkmanEnvFile $Sdkmanrc

    foreach ($entry in Get-SdkmanEnvEntries $Sdkmanrc) {
        Invoke-SdkInstall $entry.Candidate $entry.Version -NoDefault
    }
    Import-SdkmanEnv $Sdkmanrc
}

function Import-SdkmanEnv([string]$Sdkmanrc) {
    Assert-SdkmanEnvFile $Sdkmanrc

    foreach ($entry in Get-SdkmanEnvEntries $Sdkmanrc) {
        if (-not (Test-Path -LiteralPath (Get-SdkmanCandidateDir $entry.Candidate $entry.Version) -PathType Container)) {
            Write-SdkmanRed "Stop! $($entry.Candidate) $($entry.Version) is not installed."
            Write-Host ''
            Write-SdkmanYellow "Run 'sdk env install' to install it."
            Stop-SdkmanCommand
        }
        Invoke-SdkUse $entry.Candidate $entry.Version
    }
    $script:SdkmanEnv = Split-Path -Parent $Sdkmanrc
}

function New-SdkmanEnvFile([string]$Sdkmanrc) {
    if (Test-Path -LiteralPath $Sdkmanrc) {
        Write-SdkmanRed "$script:SdkmanRc already exists!"
        Stop-SdkmanCommand
    }

    $version = Get-SdkmanCurrentVersion 'java'
    if (-not $version) {
        $version = Invoke-SdkmanCurl "$script:CandidatesApi/candidates/default/java"
    }

    $content = @(
        '# Enable auto-env through the sdkman_auto_env config'
        '# Add key=value pairs of SDKs to use below'
        "java=$version"
    ) -join "`n"
    Write-SdkmanTextFile $Sdkmanrc "$content`n"

    Write-SdkmanGreen "$script:SdkmanRc created."
}

function Clear-SdkmanEnv {
    if (-not $script:SdkmanEnv) {
        Write-SdkmanRed 'No environment currently set!'
        Stop-SdkmanCommand
    }

    $sdkmanrc = [IO.Path]::Combine($script:SdkmanEnv, $script:SdkmanRc)
    if (-not (Test-Path -LiteralPath $sdkmanrc -PathType Leaf)) {
        Write-SdkmanRed "Could not find $sdkmanrc."
        Stop-SdkmanCommand
    }

    foreach ($entry in Get-SdkmanEnvEntries $sdkmanrc) {
        Restore-SdkmanDefaultVersion $entry.Candidate
    }
    $script:SdkmanEnv = ''
}

function Restore-SdkmanDefaultVersion([string]$Candidate) {
    $defaultVersion = Get-SdkmanDefaultVersion $Candidate
    if ($defaultVersion) {
        Invoke-SdkUse $Candidate $defaultVersion 6> $null
        Write-SdkmanYellow "Restored $Candidate version to $defaultVersion (default)"
    } else {
        Write-SdkmanYellow "No default version of $Candidate was found"
    }
}

# Parses candidate=version lines, ignoring comments and whitespace.
function Get-SdkmanEnvEntries([string]$Sdkmanrc) {
    $entries = foreach ($line in Get-Content -LiteralPath $Sdkmanrc) {
        $normalised = ($line -replace '#.*$', '') -replace '\s', ''
        if (-not $normalised) {
            continue
        }

        if ($normalised -cnotmatch '^[a-z]+=.+$') {
            Write-SdkmanRed 'Invalid candidate format!'
            Write-Host ''
            Write-SdkmanYellow "Expected 'candidate=version' but found '$normalised'"
            Stop-SdkmanCommand
        }

        $index = $normalised.IndexOf('=')
        [pscustomobject]@{
            Candidate = $normalised.Substring(0, $index)
            Version   = $normalised.Substring($index + 1)
        }
    }
    return @($entries)
}

# Hooked into the prompt when sdkman_auto_env=true.
function Invoke-SdkmanAutoEnv {
    $location = Get-Location
    if ($location.Provider.Name -ne 'FileSystem') {
        return
    }
    $path = $location.ProviderPath
    $exitCode = $global:LASTEXITCODE

    if ($script:SdkmanEnv -and -not ($path + '\').StartsWith($script:SdkmanEnv.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        sdk env clear
    }

    if ($script:SdkmanOldPwd -ne $path -and (Test-Path -LiteralPath ([IO.Path]::Combine($path, $script:SdkmanRc)) -PathType Leaf)) {
        sdk env
    }

    $script:SdkmanOldPwd = $path
    $global:LASTEXITCODE = $exitCode
}
