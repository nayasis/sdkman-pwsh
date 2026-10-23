#
#   PowerShell port of SDKMAN! - sdkman-availability.sh, sdkman-cache.sh, sdkman-offline.sh
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#

function Update-SdkmanServiceAvailability([string]$Command, [string]$Qualifier) {
    $status = ''
    if (-not ($script:OfflineMode -or ($Command -eq 'offline' -and $Qualifier -eq 'enable'))) {
        $status = Invoke-SdkmanCurl "$script:CandidatesApi/healthcheck" -WithTimeouts -AnyStatus
    }

    if (-not $status) {
        $script:Available = $false
        if ($Command -ne 'offline' -and -not $script:OfflineMode) {
            Write-SdkmanRed '==== INTERNET NOT REACHABLE! ==================================================='
            Write-SdkmanRed ''
            Write-SdkmanRed ' Some functionality is disabled or only partially available.'
            Write-SdkmanRed ' If this persists, please enable the offline mode:'
            Write-SdkmanRed ''
            Write-SdkmanRed '   $ sdk offline'
            Write-SdkmanRed ''
            Write-SdkmanRed '================================================================================'
            Write-Host ''
        }
    } elseif ($status -match 'html') {
        $script:Available = $false
        Write-SdkmanRed '==== PROXY DETECTED! ==========================================================='
        Write-SdkmanRed 'Please ensure you have open internet access to continue.'
        Write-SdkmanRed '================================================================================'
        Write-Host ''
    } else {
        $script:Available = $true
    }
}

function Test-SdkmanCandidatesCache {
    if ((Test-Path -LiteralPath $script:CandidatesCache -PathType Leaf) -and -not $script:CandidatesCsv) {
        Write-SdkmanRed 'WARNING: Cache is corrupt. SDKMAN cannot be used until updated.'
        Write-Host ''
        Write-SdkmanNoColour '  $ sdk update'
        Write-Host ''
        return $false
    }
    Write-SdkmanDebug "Using existing cache: $script:CandidatesCsv"
    return $true
}

function Invoke-SdkOffline([string]$Mode) {
    if (-not $Mode -or $Mode -eq 'enable') {
        $script:OfflineMode = $true
        Write-SdkmanGreen 'Offline mode enabled.'
    }

    if ($Mode -eq 'disable') {
        $script:OfflineMode = $false
        Write-SdkmanGreen 'Online mode re-enabled!'
    }
}
