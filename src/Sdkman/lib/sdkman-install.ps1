#
#   PowerShell port of SDKMAN! - sdkman-install.sh
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#

function Invoke-SdkInstall([string]$Candidate, [string]$Version, [string]$Folder, [switch]$NoDefault) {
    Assert-SdkmanCandidatePresent $Candidate
    $resolved = Resolve-SdkmanVersion $Candidate $Version $Folder
    $Version = $resolved.Version
    $versionDir = Get-SdkmanCandidateDir $Candidate $Version

    if (Test-Path -LiteralPath $versionDir) {
        Write-Host ''
        Write-SdkmanYellow "$Candidate $Version is already installed."
        return
    }

    if ($resolved.Valid -eq 'valid') {
        $current = Get-SdkmanCurrentVersion $Candidate
        Install-SdkmanCandidateVersion $Candidate $Version

        $use = ''
        if ($NoDefault) {
            $use = 'n'
        } elseif (-not (Test-SdkmanConfig 'sdkman_auto_answer') -and -not $script:AutoAnswerUpgrade -and $current) {
            $use = Read-SdkmanConfirm "Do you want $Candidate $Version to be set as default? (Y/n): "
        }

        if (-not $use -or $use -eq 'y') {
            Write-Host ''
            Write-SdkmanGreen "Setting $Candidate $Version as default."
            Set-SdkmanDefaultLink $Candidate $Version
            Add-SdkmanCandidateToPath $Candidate
            if (-not $current) {
                Set-SdkmanCandidateHome $Candidate (Get-SdkmanCandidateDir $Candidate 'current')
            }
        }
    } elseif ($resolved.Valid -eq 'invalid' -and $Folder) {
        Install-SdkmanLocalVersion $Candidate $Version $Folder
    } else {
        Write-Host ''
        Write-SdkmanRed "Stop! $Version is not a valid $Candidate version."
        Stop-SdkmanCommand
    }
}

function Install-SdkmanCandidateVersion([string]$Candidate, [string]$Version) {
    $archive = Get-SdkmanArchive $Candidate $Version
    Write-SdkmanGreen "Installing: $Candidate $Version"

    New-SdkmanDirectory (Get-SdkmanCandidateDir $Candidate)

    $out = [IO.Path]::Combine($script:SdkmanDir, 'tmp', 'out')
    Remove-SdkmanItem $out
    New-SdkmanDirectory $out
    Expand-SdkmanArchive $archive.Path $archive.Type $out

    # Archives normally hold a single top level folder which becomes the version folder
    $children = @(Get-ChildItem -LiteralPath $out -Force)
    $source = $out
    if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
        $source = $children[0].FullName
    }
    Move-Item -LiteralPath $source -Destination (Get-SdkmanCandidateDir $Candidate $Version) -Force
    Remove-SdkmanItem $out

    Write-SdkmanGreen 'Done installing!'
    Write-Host ''
}

function Install-SdkmanLocalVersion([string]$Candidate, [string]$Version, [string]$Folder) {
    $versionLengthMax = 15

    # Validate max length of version
    Write-SdkmanDebug "Validating that actual version length ($($Version.Length)) does not exceed max ($versionLengthMax)"
    if ($Version.Length -gt $versionLengthMax) {
        Write-SdkmanRed "Invalid version! $Version with length $($Version.Length) exceeds max of ${versionLengthMax}!"
        Stop-SdkmanCommand
    }

    New-SdkmanDirectory (Get-SdkmanCandidateDir $Candidate)

    # handle relative paths
    $Folder = Get-SdkmanFullPath $Folder

    if (Test-Path -LiteralPath $Folder -PathType Container) {
        Write-SdkmanGreen "Linking $Candidate $Version to $Folder"
        New-SdkmanLink (Get-SdkmanCandidateDir $Candidate $Version) $Folder
        Write-SdkmanGreen 'Done installing!'
    } else {
        Write-SdkmanRed "Invalid path! Refusing to link $Candidate $Version to $Folder."
        Stop-SdkmanCommand
    }

    Write-Host ''
}

# Equivalent of __sdkman_download. The bash post-installation hooks only rename the
# archive on Windows, so the archive type is detected here instead of sourcing them.
function Get-SdkmanArchive([string]$Candidate, [string]$Version) {
    $tmpDir = [IO.Path]::Combine($script:SdkmanDir, 'tmp')
    $metadataDir = [IO.Path]::Combine($script:SdkmanDir, 'var', 'metadata')
    New-SdkmanDirectory $tmpDir
    New-SdkmanDirectory $metadataDir

    $downloadUrl = "$script:BrokerApi/download/$Candidate/$Version/$script:Platform"
    $baseName = "$Candidate-$Version"
    $binaryInput = [IO.Path]::Combine($tmpDir, "$baseName.bin")
    $headersFile = [IO.Path]::Combine($metadataDir, "$baseName.headers")

    Write-Host ''
    Write-SdkmanNoColour "Downloading: $Candidate $Version"
    Write-Host ''
    Write-SdkmanNoColour 'In progress...'
    Write-Host ''

    $headers = @{}
    try {
        Invoke-SdkmanDownloadFile $downloadUrl $binaryInput $headers
    } catch {
        Remove-SdkmanItem $binaryInput
        Write-SdkmanRed "Stop! Download of $Candidate $Version failed: $($_.Exception.Message)"
        if ($_.Exception.Message -like 'HTTP 404*') {
            Write-Host ''
            Write-SdkmanYellow "The SDKMAN broker ($script:BrokerApi) has no binary for $Candidate $Version on $script:Platform."
            Write-SdkmanYellow 'Please try another version:'
            Write-Host ''
            Write-SdkmanYellow "  $ sdk list $Candidate"
        }
        Stop-SdkmanCommand
    }

    $headerLines = foreach ($key in ($headers.Keys | Sort-Object)) { "${key}: $($headers[$key])" }
    Write-SdkmanTextFile $headersFile ((@($headerLines) -join "`n") + "`n")
    Write-SdkmanDebug "Downloaded binary to: $binaryInput (HTTP headers written to: $headersFile)"

    $type = Get-SdkmanArchiveType $binaryInput $headers['X-Sdkman-ArchiveType']
    Write-SdkmanDebug "Detected archive type: $type"
    if (-not $type) {
        Remove-SdkmanItem $binaryInput
        Write-Host ''
        Write-SdkmanRed 'Stop! The downloaded file is not a supported archive and has been removed! Please try installing again.'
        Stop-SdkmanCommand
    }

    $extension = 'tar'
    if ($type -eq 'zip') {
        $extension = 'zip'
    }
    $archive = [IO.Path]::Combine($tmpDir, "$baseName.$extension")
    Move-Item -LiteralPath $binaryInput -Destination $archive -Force

    Test-SdkmanArchive $archive $type
    Confirm-SdkmanChecksum $archive $headersFile
    Write-Host ''

    return [pscustomobject]@{ Path = $archive; Type = $type }
}

function Get-SdkmanArchiveType([string]$File, [string]$HeaderType) {
    $stream = [IO.File]::OpenRead($File)
    try {
        $magic = New-Object byte[] 262
        $count = $stream.Read($magic, 0, $magic.Length)
    } finally {
        $stream.Dispose()
    }

    if ($count -ge 4 -and $magic[0] -eq 0x50 -and $magic[1] -eq 0x4B) { return 'zip' }
    if ($count -ge 2 -and $magic[0] -eq 0x1F -and $magic[1] -eq 0x8B) { return 'tar' }    # gzip
    if ($count -ge 3 -and $magic[0] -eq 0x42 -and $magic[1] -eq 0x5A -and $magic[2] -eq 0x68) { return 'tar' }    # bzip2
    if ($count -ge 6 -and $magic[0] -eq 0xFD -and $magic[1] -eq 0x37 -and $magic[2] -eq 0x7A) { return 'tar' }    # xz
    if ($count -ge 262 -and [Text.Encoding]::ASCII.GetString($magic, 257, 5) -eq 'ustar') { return 'tar' }
    if ($HeaderType -match '^(zip|tar.*|tgz)$') {
        return $(if ($HeaderType -eq 'zip') { 'zip' } else { 'tar' })
    }
    return ''
}

function Get-SdkmanTar {
    $tar = [IO.Path]::Combine($env:SystemRoot, 'System32', 'tar.exe')
    if (Test-Path -LiteralPath $tar -PathType Leaf) {
        return $tar
    }
    return 'tar'
}

# Equivalent of __sdkman_validate_zip
function Test-SdkmanArchive([string]$Archive, [string]$Type) {
    $ok = $true
    if ($Type -eq 'zip') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        try {
            $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
            try {
                $ok = $zip.Entries.Count -gt 0
            } finally {
                $zip.Dispose()
            }
        } catch {
            $ok = $false
        }
    } else {
        & (Get-SdkmanTar) -tf $Archive | Out-Null
        $ok = $LASTEXITCODE -eq 0
    }

    if (-not $ok) {
        Remove-SdkmanItem $Archive
        Write-Host ''
        Write-SdkmanRed 'Stop! The archive was corrupt and has been removed! Please try installing again.'
        Stop-SdkmanCommand
    }
}

function Expand-SdkmanArchive([string]$Archive, [string]$Type, [string]$Destination) {
    if ($Type -eq 'zip') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination)
    } else {
        & (Get-SdkmanTar) -xf $Archive -C $Destination
        if ($LASTEXITCODE -ne 0) {
            Write-SdkmanRed "Stop! Could not extract $Archive."
            Stop-SdkmanCommand
        }
    }
}

function Get-SdkmanFileHash([string]$File, [string]$Algorithm) {
    $hasher = [Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    $stream = [IO.File]::OpenRead($File)
    try {
        return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '')
    } finally {
        $stream.Dispose()
        $hasher.Dispose()
    }
}

# Equivalent of __sdkman_checksum_zip
function Confirm-SdkmanChecksum([string]$Archive, [string]$HeadersFile) {
    if (-not (Test-Path -LiteralPath $HeadersFile -PathType Leaf)) {
        Write-Host ''
        Write-SdkmanYellow "Metadata file not found at '$HeadersFile', skipping checksum..."
        return
    }

    if (-not (Test-SdkmanConfig 'sdkman_checksum_enable')) {
        Write-Host ''
        Write-SdkmanYellow 'Checksums are disabled, skipping verification...'
        return
    }

    $supported = @{ SHA1 = 'SHA1'; SHA256 = 'SHA256'; SHA384 = 'SHA384'; SHA512 = 'SHA512'; MD5 = 'MD5' }
    foreach ($line in Get-Content -LiteralPath $HeadersFile) {
        if ($line -notmatch '^X-Sdkman-Checksum-(.*?):(.*)$') {
            continue
        }
        $algorithm = $Matches[1].ToUpperInvariant()
        $checksum = $Matches[2] -replace '[^A-Za-z0-9]', ''
        if (-not $algorithm -or -not $checksum) {
            continue
        }

        $hashAlgorithm = $supported[$algorithm.Replace('-', '')]
        if (-not $hashAlgorithm) {
            Write-SdkmanNoColour 'Not able to perform checksum verification at this time.'
            continue
        }

        Write-SdkmanNoColour "Verifying artifact: $Archive (${algorithm}:$checksum)"
        if ((Get-SdkmanFileHash $Archive $hashAlgorithm) -ne $checksum) {
            Remove-SdkmanItem $Archive
            Write-Host ''
            Write-SdkmanRed 'Stop! An invalid checksum was detected and the archive removed! Please try re-installing.'
            Stop-SdkmanCommand
        }
    }
}
