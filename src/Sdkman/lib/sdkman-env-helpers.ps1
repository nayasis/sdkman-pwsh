#
#   PowerShell port of SDKMAN! - sdkman-env-helpers.sh
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#

function Assert-SdkmanCandidatePresent([string]$Candidate) {
    if (-not $Candidate) {
        Write-Host ''
        Write-SdkmanRed 'No candidate provided.'
        Invoke-SdkHelp
        Stop-SdkmanCommand
    }
}

function Assert-SdkmanVersionPresent([string]$Version) {
    if (-not $Version) {
        Write-Host ''
        Write-SdkmanRed 'No candidate version provided.'
        Invoke-SdkHelp
        Stop-SdkmanCommand
    }
}

function Write-SdkmanNotInstalled([string]$Candidate, [string]$Version) {
    Write-Host ''
    Write-SdkmanRed 'Stop! Candidate version is not installed.'
    Write-Host ''
    Write-SdkmanYellow 'Tip: Run the following to install this version'
    Write-Host ''
    Write-SdkmanYellow "$ sdk install $Candidate $Version"
}

# Equivalent of __sdkman_determine_version: returns @{ Version; Valid } or stops the command.
function Resolve-SdkmanVersion([string]$Candidate, [string]$Version, [string]$Folder) {
    $versionDir = ''
    if ($Version) {
        $versionDir = Get-SdkmanCandidateDir $Candidate $Version
    }

    if (-not $script:Available) {
        if ($Version -and (Test-Path -LiteralPath $versionDir -PathType Container)) {
            return [pscustomobject]@{ Version = $Version; Valid = '' }
        }

        if (-not $Version) {
            $default = Get-SdkmanDefaultVersion $Candidate
            if ($default) {
                return [pscustomobject]@{ Version = $default; Valid = '' }
            }
            Write-SdkmanRed 'This command is not available while offline.'
            Stop-SdkmanCommand
        }

        Write-SdkmanRed "Stop! $Candidate $Version is not available while offline."
        Stop-SdkmanCommand
    }

    if (-not $Version) {
        $Version = Invoke-SdkmanCurl "$script:CandidatesApi/candidates/default/$Candidate"
        $versionDir = Get-SdkmanCandidateDir $Candidate $Version
    }

    $validationUrl = "$script:CandidatesApi/candidates/validate/$Candidate/$Version/$script:Platform"
    $valid = Invoke-SdkmanCurl $validationUrl
    Write-SdkmanDebug "Validate $Candidate $Version for ${script:Platform}: $valid"
    Write-SdkmanDebug "Validation URL: $validationUrl"

    if ($Version -and ($valid -eq 'valid' -or ($valid -eq 'invalid' -and $Folder))) {
        return [pscustomobject]@{ Version = $Version; Valid = $valid }
    }

    if ($Version -and $valid -eq 'invalid' -and (Test-Path -LiteralPath $versionDir -PathType Container)) {
        return [pscustomobject]@{ Version = $Version; Valid = $valid }
    }

    Write-Host ''
    Write-SdkmanRed "Stop! $Candidate $Version is not available. Possible causes:"
    Write-SdkmanRed " * $Version is an invalid version"
    Write-SdkmanRed " * $Candidate binaries are incompatible with your platform"
    Write-SdkmanRed " * $Candidate has not been released yet"
    Write-Host ''
    Write-SdkmanYellow 'Tip: see all available versions for your platform:'
    Write-Host ''
    Write-SdkmanYellow "  $ sdk list $Candidate"
    Stop-SdkmanCommand
}
