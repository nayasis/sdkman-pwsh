#
#   PowerShell port of SDKMAN! - sdkman-{list,use,current,default,uninstall,home,flush,version,config}.sh
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#

function Invoke-SdkList([string]$Candidate) {
    if (-not $Candidate) {
        if (-not $script:Available) {
            Write-SdkmanRed 'This command is not available while offline.'
        } else {
            Write-SdkmanPaged (Invoke-SdkmanCurl "$script:CandidatesApi/candidates/list")
        }
        return
    }

    $versions = @(Get-SdkmanInstalledVersions $Candidate)
    $current = Get-SdkmanCurrentVersion $Candidate

    if (-not $script:Available) {
        Write-SdkmanOfflineList $Candidate $versions $current
    } else {
        $installed = [Uri]::EscapeDataString(($versions -join ','))
        $url = "$script:CandidatesApi/candidates/$Candidate/$script:Platform/versions/list?current=$([Uri]::EscapeDataString($current))&installed=$installed"
        Write-SdkmanPaged (Invoke-SdkmanCurl $url)
    }
}

function Write-SdkmanOfflineList([string]$Candidate, [string[]]$Versions, [string]$Current) {
    Write-SdkmanNoColour '--------------------------------------------------------------------------------'
    Write-SdkmanYellow "Offline: only showing installed $Candidate versions"
    Write-SdkmanNoColour '--------------------------------------------------------------------------------'

    foreach ($version in ($Versions | Sort-Object -Descending)) {
        if ($version -eq $Current) {
            Write-SdkmanNoColour " > $version"
        } else {
            Write-SdkmanNoColour " * $version"
        }
    }

    if ($Versions.Count -eq 0) {
        Write-SdkmanYellow '   None installed!'
    }

    Write-SdkmanNoColour '--------------------------------------------------------------------------------'
    Write-SdkmanNoColour '* - installed                                                                   '
    Write-SdkmanNoColour '> - currently in use                                                            '
    Write-SdkmanNoColour '--------------------------------------------------------------------------------'
}

function Invoke-SdkUse([string]$Candidate, [string]$Version) {
    Assert-SdkmanCandidatePresent $Candidate
    Assert-SdkmanVersionPresent $Version

    $versionDir = Get-SdkmanCandidateDir $Candidate $Version
    if (-not (Test-Path -LiteralPath $versionDir -PathType Container)) {
        Write-SdkmanNotInstalled $Candidate $Version
        Stop-SdkmanCommand
    }

    # Just update the *_HOME and PATH for this shell.
    Set-SdkmanCandidateHome $Candidate $versionDir
    Set-SdkmanCandidatePath $Candidate $Version

    if (-not (Test-Path -LiteralPath (Get-SdkmanCandidateDir $Candidate 'current'))) {
        Write-SdkmanGreen "Setting $Candidate version $Version as default."
        Set-SdkmanDefaultLink $Candidate $Version
    }

    Write-Host ''
    Write-SdkmanGreen "Using $Candidate version $Version in this shell."
}

# Equivalent of __sdkman_determine_current_version: the version found on PATH.
function Get-SdkmanCurrentVersion([string]$Candidate) {
    $pattern = '^' + [regex]::Escape((Get-SdkmanCandidateDir $Candidate)) + '\\([^\\]+)'
    foreach ($entry in Get-SdkmanPathEntries) {
        if ($entry.Replace('/', '\') -match $pattern) {
            $version = $Matches[1]
            if ($version -eq 'current') {
                $version = Get-SdkmanDefaultVersion $Candidate
            }
            return $version
        }
    }
    return ''
}

function Invoke-SdkCurrent([string]$Candidate) {
    Write-Host ''
    if ($Candidate) {
        $current = Get-SdkmanCurrentVersion $Candidate
        if ($current) {
            Write-SdkmanNoColour "Using $Candidate version $current"
        } else {
            Write-SdkmanRed "Not using any version of $Candidate"
        }
        return
    }

    $installedCount = 0
    foreach ($name in $script:Candidates) {
        $current = Get-SdkmanCurrentVersion $name
        if ($current) {
            if ($installedCount -eq 0) {
                Write-SdkmanNoColour 'Using:'
                Write-Host ''
            }
            Write-SdkmanNoColour "${name}: $current"
            $installedCount++
        }
    }

    if ($installedCount -eq 0) {
        Write-SdkmanNoColour 'No candidates are in use'
    }
}

function Invoke-SdkDefault([string]$Candidate, [string]$Version) {
    Assert-SdkmanCandidatePresent $Candidate
    $Version = (Resolve-SdkmanVersion $Candidate $Version '').Version

    if (-not (Test-Path -LiteralPath (Get-SdkmanCandidateDir $Candidate $Version) -PathType Container)) {
        Write-SdkmanNotInstalled $Candidate $Version
        Stop-SdkmanCommand
    }

    Set-SdkmanDefaultLink $Candidate $Version

    Write-Host ''
    Write-SdkmanGreen "Default $Candidate version set to $Version"
}

function Invoke-SdkUninstall([string]$Candidate, [string]$Version) {
    Assert-SdkmanCandidatePresent $Candidate
    Assert-SdkmanVersionPresent $Version

    $current = Get-SdkmanCandidateDir $Candidate 'current'
    if ((Test-SdkmanLink $current) -and $Version -eq (Get-SdkmanDefaultVersion $Candidate)) {
        Write-Host ''
        Write-SdkmanGreen "Deselecting $Candidate $Version..."
        Remove-SdkmanItem $current
    }

    Write-Host ''

    $versionDir = Get-SdkmanCandidateDir $Candidate $Version
    if (Test-Path -LiteralPath $versionDir -PathType Container) {
        Write-SdkmanGreen "Uninstalling $Candidate $Version..."
        Remove-SdkmanItem $versionDir
    } else {
        Write-SdkmanRed "$Candidate $Version is not installed."
    }
}

function Invoke-SdkHome([string]$Candidate, [string]$Version) {
    Assert-SdkmanCandidatePresent $Candidate
    Assert-SdkmanVersionPresent $Version

    $versionDir = Get-SdkmanCandidateDir $Candidate $Version
    if (-not (Test-Path -LiteralPath $versionDir -PathType Container)) {
        Write-SdkmanNotInstalled $Candidate $Version
        Stop-SdkmanCommand
    }

    # Written to the pipeline so it can be captured: $javaHome = sdk home java 21.0.5-tem
    Write-Output $versionDir
}

function Invoke-SdkFlush([string]$Qualifier) {
    switch ($Qualifier) {
        'version' {
            $file = [IO.Path]::Combine($script:SdkmanDir, 'var', 'version')
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                Remove-SdkmanItem $file
                Write-SdkmanGreen 'Version file has been flushed.'
            }
        }
        { $_ -in 'temp', 'tmp' } {
            Clear-SdkmanFolder 'tmp'
        }
        'metadata' {
            Clear-SdkmanFolder 'var\metadata'
        }
        default {
            Clear-SdkmanFolder 'tmp'
            Clear-SdkmanFolder 'var\metadata'
        }
    }
}

function Clear-SdkmanFolder([string]$Folder) {
    $dir = [IO.Path]::Combine($script:SdkmanDir, $Folder)
    $count = 0
    $size = 0
    if (Test-Path -LiteralPath $dir -PathType Container) {
        $count = @(Get-ChildItem -LiteralPath $dir -Force).Count
        # Measure-Object yields no Sum property for an empty folder under strict mode
        foreach ($file in Get-ChildItem -LiteralPath $dir -Recurse -File -Force) {
            $size += $file.Length
        }
        Remove-SdkmanItem $dir
    }
    New-SdkmanDirectory $dir

    Write-SdkmanGreen "$count archive(s) flushed, freeing $(Format-SdkmanSize $size)."
}

function Format-SdkmanSize([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1}G' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1}M' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N1}K' -f ($Bytes / 1KB) }
    return "${Bytes}B"
}

function Invoke-SdkVersion {
    Write-Host ''
    Write-SdkmanYellow "SDKMAN! for PowerShell $script:SdkmanVersion"
}

function Invoke-SdkConfig {
    $editor = $env:EDITOR
    if (-not $editor) {
        $editor = 'notepad'
    }

    # EDITOR may carry arguments, e.g. "code --wait"
    $arguments = @()
    if (-not (Get-Command $editor -ErrorAction SilentlyContinue)) {
        $parts = @($editor -split '\s+' | Where-Object { $_ })
        $editor = $parts[0]
        $arguments = @($parts | Select-Object -Skip 1)
    }

    if (-not (Get-Command $editor -ErrorAction SilentlyContinue)) {
        Write-SdkmanRed 'No default editor configured.'
        Write-SdkmanYellow 'Please set the default editor with the EDITOR environment variable.'
        Stop-SdkmanCommand
    }

    & $editor @arguments ([IO.Path]::Combine($script:SdkmanDir, 'etc', 'config'))
}

function Invoke-SdkHelp {
    Write-SdkmanNoColour ''
    Write-SdkmanNoColour 'Usage: sdk <command> [candidate] [version]'
    Write-SdkmanNoColour '       sdk offline <enable|disable>'
    Write-SdkmanNoColour ''
    Write-SdkmanNoColour '   commands:'
    Write-SdkmanNoColour '       install   or i    <candidate> [version] [local-path]'
    Write-SdkmanNoColour '       uninstall or rm   <candidate> <version>'
    Write-SdkmanNoColour '       list      or ls   [candidate]'
    Write-SdkmanNoColour '       use       or u    <candidate> <version>'
    Write-SdkmanNoColour '       config'
    Write-SdkmanNoColour '       default   or d    <candidate> [version]'
    Write-SdkmanNoColour '       home      or h    <candidate> <version>'
    Write-SdkmanNoColour '       env       or e    [init|install|clear]'
    Write-SdkmanNoColour '       current   or c    [candidate]'
    Write-SdkmanNoColour '       upgrade   or ug   [candidate]'
    Write-SdkmanNoColour '       version   or v'
    Write-SdkmanNoColour '       help'
    Write-SdkmanNoColour '       offline           [enable|disable]'
    Write-SdkmanNoColour '       update'
    Write-SdkmanNoColour '       flush             [tmp|metadata|version]'
    Write-SdkmanNoColour ''
    Write-SdkmanNoColour '   candidate  :  the SDK to install: groovy, scala, grails, gradle, kotlin, etc.'
    Write-SdkmanNoColour '                 use list command for comprehensive list of candidates'
    Write-SdkmanNoColour '                 eg: $ sdk list'
    Write-SdkmanNoColour '   version    :  where optional, defaults to latest stable if not provided'
    Write-SdkmanNoColour '                 eg: $ sdk install groovy'
    Write-SdkmanNoColour '   local-path :  optional path to an existing local installation'
    Write-SdkmanNoColour '                 eg: $ sdk install groovy 2.4.13-local C:\tools\groovy-2.4.13'
    Write-SdkmanNoColour ''
}
