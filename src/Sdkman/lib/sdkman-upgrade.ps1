#
#   PowerShell port of SDKMAN! - sdkman-upgrade.sh, sdkman-update.sh
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#

function Invoke-SdkUpgrade([string]$Candidate) {
    $all = -not $Candidate
    $candidates = @($Candidate)
    if ($all) {
        $candidates = $script:Candidates
    }

    $installedCount = 0
    $upgradable = New-Object System.Collections.Generic.List[string]
    Write-Host ''

    foreach ($name in $candidates) {
        $localVersions = @(Get-SdkmanInstalledVersions $name)
        if ($localVersions.Count -eq 0) {
            if (-not $all) {
                Write-SdkmanRed "Not using any version of $name"
            }
            continue
        }

        $remoteDefault = Invoke-SdkmanCurl "$script:CandidatesApi/candidates/default/$name"
        if (-not $remoteDefault) {
            Write-Host ''
            Write-SdkmanRed "Stop! Could not get remote version of $name"
            Stop-SdkmanCommand
        }

        if (-not (Test-Path -LiteralPath (Get-SdkmanCandidateDir $name $remoteDefault) -PathType Container)) {
            if ($upgradable.Count -eq 0) {
                Write-SdkmanNoColour 'Available defaults:'
            }
            Write-SdkmanYellow "$name (local: $($localVersions -join ', '); default: $remoteDefault)"
            $upgradable.Add($name)
        }
        $installedCount++
    }

    if ($all) {
        if ($installedCount -eq 0) {
            Write-SdkmanNoColour 'No candidates are in use'
        } elseif ($upgradable.Count -eq 0) {
            Write-SdkmanNoColour 'All candidates are up-to-date'
        }
    } elseif ($installedCount -gt 0 -and $upgradable.Count -eq 0) {
        Write-SdkmanNoColour "$Candidate is up-to-date"
    }

    if ($upgradable.Count -gt 0) {
        Write-Host ''

        $upgradeAll = ''
        if (-not (Test-SdkmanConfig 'sdkman_auto_answer')) {
            $upgradeAll = Read-SdkmanConfirm 'Use prescribed default version(s)? (Y/n): '
        }

        if (-not $upgradeAll -or $upgradeAll -eq 'y') {
            $script:AutoAnswerUpgrade = $true
            try {
                foreach ($name in $upgradable) {
                    Invoke-SdkInstall $name
                }
            } finally {
                $script:AutoAnswerUpgrade = $false
            }
        }
    }
}

function Invoke-SdkUpdate {
    $candidatesUri = "$script:CandidatesApi/candidates/all"
    Write-SdkmanDebug "Using candidates endpoint: $candidatesUri"

    $freshCsv = Invoke-SdkmanCurl $candidatesUri -WithTimeouts
    Write-SdkmanDebug "Local candidates: $script:CandidatesCsv"
    Write-SdkmanDebug "Fetched candidates: $freshCsv"

    if (-not $freshCsv -or $freshCsv -match 'html') {
        return
    }

    $fresh = @($freshCsv.Trim() -split ',' | Where-Object { $_ })
    $added = @($fresh | Where-Object { $script:Candidates -notcontains $_ })
    $removed = @($script:Candidates | Where-Object { $fresh -notcontains $_ })

    if ($added.Count -gt 0 -or $removed.Count -gt 0) {
        if ($added.Count -gt 0) {
            Write-SdkmanGreen "`nAdding new candidates(s): $($added -join ' ')"
        }
        if ($removed.Count -gt 0) {
            Write-SdkmanGreen "`nRemoving obsolete candidates(s): $($removed -join ' ')"
        }
        New-SdkmanDirectory (Split-Path -Parent $script:CandidatesCache)
        Write-SdkmanTextFile $script:CandidatesCache "$($freshCsv.Trim())`n"
        Import-SdkmanCandidates
        Write-SdkmanYellow "`nPlease open a new terminal now..."
    } else {
        (Get-Item -LiteralPath $script:CandidatesCache).LastWriteTime = Get-Date
        Write-SdkmanGreen "`nNo new candidates found at this time."
    }
}
