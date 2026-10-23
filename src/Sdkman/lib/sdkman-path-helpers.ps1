#
#   PowerShell port of SDKMAN! - sdkman-path-helpers.sh
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Symlinks are replaced by directory junctions, which do not require
#   administrator rights or developer mode on Windows.
#

function Get-SdkmanCandidateDir([string]$Candidate, [string]$Version) {
    $dir = [IO.Path]::Combine($script:CandidatesDir, $Candidate)
    if ($Version) {
        # Versions become folder names; reject anything that could escape the candidate folder,
        # e.g. `sdk uninstall java ..` or `java=..\..\evil` in a .sdkmanrc.
        if ($Version -eq '.' -or $Version -eq '..' -or $Version.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            throw "Invalid version: $Version"
        }
        $dir = [IO.Path]::Combine($dir, $Version)
    }
    return $dir
}

function Get-SdkmanItem([string]$Path) {
    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Test-SdkmanLink([string]$Path) {
    $item = Get-SdkmanItem $Path
    return ($null -ne $item -and [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint))
}

# Equivalent of `readlink`
function Get-SdkmanLinkTarget([string]$Path) {
    $item = Get-SdkmanItem $Path
    if ($null -eq $item -or -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        return ''
    }
    # Windows PowerShell returns string[], PowerShell 7 returns string
    return [string](@($item.Target) | Select-Object -First 1)
}

# Removes a file or directory. Links are removed without touching their target,
# which `Remove-Item -Recurse` does not guarantee on Windows PowerShell.
function Remove-SdkmanItem([string]$Path) {
    $item = Get-SdkmanItem $Path
    if ($null -eq $item) {
        return
    }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if ($item.PSIsContainer) {
            [IO.Directory]::Delete($item.FullName)
        } else {
            [IO.File]::Delete($item.FullName)
        }
    } else {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
}

function New-SdkmanLink([string]$Path, [string]$Target) {
    try {
        New-Item -ItemType Junction -Path $Path -Value $Target -ErrorAction Stop | Out-Null
    } catch {
        # Junctions cannot point to network shares; fall back to a symbolic link
        # (requires developer mode or an elevated shell).
        New-Item -ItemType SymbolicLink -Path $Path -Value $Target -ErrorAction Stop | Out-Null
    }
}

function Get-SdkmanCandidateBinDir([string]$CandidateDir) {
    $bin = [IO.Path]::Combine($CandidateDir, 'bin')
    if (Test-Path -LiteralPath $bin -PathType Container) {
        return $bin
    }
    return $CandidateDir
}

function Get-SdkmanPathEntries {
    return @($env:PATH -split ';')
}

function Test-SdkmanPathContains([string]$Dir) {
    $prefix = $Dir.TrimEnd('\') + '\'
    foreach ($entry in Get-SdkmanPathEntries) {
        $normal = $entry.Replace('/', '\').TrimEnd('\') + '\'
        if ($normal.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Add-SdkmanCandidateToPath([string]$Candidate) {
    if (-not (Test-SdkmanPathContains (Get-SdkmanCandidateDir $Candidate))) {
        $bin = Get-SdkmanCandidateBinDir (Get-SdkmanCandidateDir $Candidate 'current')
        $env:PATH = "$bin;$env:PATH"
    }
}

function Add-SdkmanCandidateDirToPath([string]$CandidateDir) {
    if (-not (Test-SdkmanPathContains $CandidateDir)) {
        $env:PATH = "$(Get-SdkmanCandidateBinDir $CandidateDir);$env:PATH"
    }
}

# Points every PATH entry of the candidate at the given version (or prepends it when absent).
function Set-SdkmanCandidatePath([string]$Candidate, [string]$Version) {
    $pattern = '^' + [regex]::Escape((Get-SdkmanCandidateDir $Candidate)) + '\\[^\\]+'
    $found = $false
    $entries = foreach ($entry in Get-SdkmanPathEntries) {
        $normal = $entry.Replace('/', '\')
        if ($normal -match $pattern) {
            $found = $true
            (Get-SdkmanCandidateDir $Candidate $Version) + $normal.Substring($Matches[0].Length)
        } else {
            $entry
        }
    }
    if (-not $found) {
        $entries = @(Get-SdkmanCandidateBinDir (Get-SdkmanCandidateDir $Candidate $Version)) + $entries
    }
    $env:PATH = $entries -join ';'
}

function Set-SdkmanCandidateHome([string]$Candidate, [string]$CandidateDir) {
    Set-Item -LiteralPath "env:$($Candidate.ToUpperInvariant())_HOME" -Value $CandidateDir
}

function Set-SdkmanDefaultLink([string]$Candidate, [string]$Version) {
    # Change the 'current' junction for the candidate, hence affecting all shells.
    $current = Get-SdkmanCandidateDir $Candidate 'current'
    Remove-SdkmanItem $current
    New-SdkmanLink $current (Get-SdkmanCandidateDir $Candidate $Version)
}

# Version the 'current' link points to, or an empty string.
function Get-SdkmanDefaultVersion([string]$Candidate) {
    $target = Get-SdkmanLinkTarget (Get-SdkmanCandidateDir $Candidate 'current')
    if ($target) {
        return Split-Path -Leaf $target.TrimEnd('\', '/')
    }
    return ''
}

function Get-SdkmanInstalledVersions([string]$Candidate) {
    $dir = Get-SdkmanCandidateDir $Candidate
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $dir -Directory -Force |
        Where-Object { $_.Name -ne 'current' } |
        ForEach-Object { $_.Name } |
        Sort-Object)
}
