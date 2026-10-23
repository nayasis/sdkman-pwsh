#
#   End-to-end smoke test for the PowerShell port of SDKMAN!
#   Uses a throwaway SDKMAN_DIR and the real SDKMAN API (installs Apache Ant, ~10 MB).
#
#   powershell -NoProfile -File tests\Test-Sdkman.ps1
#   pwsh       -NoProfile -File tests\Test-Sdkman.ps1
#
param(
    [string]$SdkmanDir = (Join-Path ([IO.Path]::GetTempPath()) "sdkman-test-$PID")
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:failures = 0

function Assert([bool]$Condition, [string]$Message) {
    if ($Condition) {
        Write-Host "  [PASS] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        $script:failures++
    }
}

function Step([string]$Name) {
    Write-Host ''
    Write-Host "=== $Name ===" -ForegroundColor Cyan
}

function Test-Link([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return ($null -ne $item -and [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint))
}

function Get-LinkTarget([string]$Path) {
    # Windows PowerShell returns string[], PowerShell 7 returns string
    return [string](@((Get-Item -LiteralPath $Path -Force).Target) | Select-Object -First 1)
}

Write-Host "PowerShell $($PSVersionTable.PSVersion) / SDKMAN_DIR=$SdkmanDir"
$originalPath = $env:PATH
$work = Join-Path ([IO.Path]::GetTempPath()) "sdkman-work-$PID"

try {
    Step 'install.ps1'
    & (Join-Path $root 'install.ps1') -SdkmanDir $SdkmanDir -NoProfile 6> $null
    Assert (Test-Path (Join-Path $SdkmanDir 'pwsh\Sdkman\Sdkman.psd1')) 'module copied'
    Assert ([bool]([IO.File]::ReadAllText((Join-Path $SdkmanDir 'var\candidates')) -match '\bant\b')) 'candidates cache populated'
    Add-Content -LiteralPath (Join-Path $SdkmanDir 'etc\config') -Value 'sdkman_auto_answer=true'

    $env:SDKMAN_DIR = $SdkmanDir
    Import-Module (Join-Path $SdkmanDir 'pwsh\Sdkman\Sdkman.psd1') -Force
    $candidates = Join-Path $SdkmanDir 'candidates'

    Step 'version / help / invalid input'
    sdk version
    Assert ($LASTEXITCODE -eq 0) 'sdk version'
    sdk bogus 6> $null
    Assert ($LASTEXITCODE -eq 1) 'invalid command fails'
    sdk install notacandidate 6> $null
    Assert ($LASTEXITCODE -eq 1) 'invalid candidate fails'
    sdk install ant 0.0.0-nope 6> $null
    Assert ($LASTEXITCODE -eq 1) 'invalid version fails'

    Step 'list'
    $list = @(sdk list)
    Assert (($list -match 'Apache Ant').Count -gt 0) 'sdk list shows candidates'
    $antList = @(sdk list ant)
    Assert (($antList -match '1\.10\.14').Count -gt 0) 'sdk list ant shows versions'

    Step 'install ant 1.10.14'
    sdk install ant 1.10.14
    Assert ($LASTEXITCODE -eq 0) 'install exit code'
    Assert (Test-Path (Join-Path $candidates 'ant\1.10.14\bin\ant.bat')) 'ant.bat extracted'
    Assert (Test-Link (Join-Path $candidates 'ant\current')) 'current is a junction'
    Assert ($env:PATH -like "*$candidates\ant\current\bin*") 'current\bin on PATH'
    Assert ($env:ANT_HOME -eq (Join-Path $candidates 'ant\current')) 'ANT_HOME set'
    Assert ((Get-Content (Join-Path $SdkmanDir 'var\metadata\ant-1.10.14.headers') -Raw) -match 'X-Sdkman-ArchiveType') 'headers metadata written'
    Assert ((Get-Command ant -ErrorAction SilentlyContinue).Source -like "$candidates*") 'ant resolves from candidates'

    sdk install ant 1.10.14 6> $null
    Assert ($LASTEXITCODE -eq 0) 'reinstall reports already installed'

    Step 'current'
    $out = sdk current ant 6>&1 | Out-String
    Assert ($out -match 'Using ant version 1\.10\.14') 'sdk current ant'

    Step 'install ant 1.10.13 (auto answer => default)'
    sdk install ant 1.10.13
    Assert ((Get-LinkTarget (Join-Path $candidates 'ant\current')) -like '*1.10.13*') 'current -> 1.10.13'
    $out = sdk current 6>&1 | Out-String
    Assert ($out -match 'ant: 1\.10\.13') 'sdk current (all)'

    Step 'use'
    sdk use ant 1.10.14
    Assert ($env:PATH -like "*$candidates\ant\1.10.14\bin*") 'PATH switched to 1.10.14'
    Assert ($env:PATH -notlike "*$candidates\ant\current\bin*") 'current entry replaced'
    Assert ($env:ANT_HOME -eq (Join-Path $candidates 'ant\1.10.14')) 'ANT_HOME switched'
    Assert ((Get-LinkTarget (Join-Path $candidates 'ant\current')) -like '*1.10.13*') 'use keeps default'
    sdk use ant 9.9.9 6> $null
    Assert ($LASTEXITCODE -eq 1) 'use of missing version fails'

    Step 'home / default'
    $antHome = sdk home ant 1.10.14
    Assert ($antHome -eq (Join-Path $candidates 'ant\1.10.14')) 'sdk home returns path'
    sdk default ant 1.10.14
    Assert ((Get-LinkTarget (Join-Path $candidates 'ant\current')) -like '*1.10.14*') 'default -> 1.10.14'

    Step 'local install / uninstall keeps target'
    $local = Join-Path $work 'my-ant'
    Copy-Item -LiteralPath (Join-Path $candidates 'ant\1.10.13') -Destination $local -Recurse
    sdk install ant 1-local $local
    Assert (Test-Link (Join-Path $candidates 'ant\1-local')) 'local version is a junction'
    sdk default ant 1-local
    sdk uninstall ant 1-local
    Assert (-not (Test-Path (Join-Path $candidates 'ant\1-local'))) 'local link removed'
    Assert (-not (Test-Path (Join-Path $candidates 'ant\current'))) 'current deselected'
    Assert (Test-Path (Join-Path $local 'bin\ant.bat')) 'local target folder untouched'

    Step 'uninstall'
    sdk default ant 1.10.14
    sdk uninstall ant 1.10.13
    Assert (-not (Test-Path (Join-Path $candidates 'ant\1.10.13'))) '1.10.13 removed'
    Assert (Test-Path (Join-Path $candidates 'ant\1.10.14\bin')) '1.10.14 untouched'

    Step 'env'
    $project = Join-Path $work 'project'
    New-Item -ItemType Directory -Path $project -Force | Out-Null
    Push-Location $project
    try {
        sdk env 6> $null
        Assert ($LASTEXITCODE -eq 1) 'env without .sdkmanrc fails'
        sdk env init
        Assert (Test-Path '.sdkmanrc') 'env init creates .sdkmanrc'
        Set-Content -LiteralPath '.sdkmanrc' -Value "# comment`nant = 1.10.14  # trailing`n"
        sdk use ant 1.10.14 6> $null
        sdk env
        Assert ($LASTEXITCODE -eq 0) 'sdk env'
        sdk env clear
        Assert ($LASTEXITCODE -eq 0) 'sdk env clear'
        Set-Content -LiteralPath '.sdkmanrc' -Value 'Bad Line'
        sdk env 6> $null
        Assert ($LASTEXITCODE -eq 1) 'invalid .sdkmanrc fails'
    } finally {
        Pop-Location
    }

    Step 'offline'
    sdk offline enable
    $out = sdk list ant 6>&1 | Out-String
    Assert ($out -match 'Offline: only showing installed ant versions' -and $out -match '1\.10\.14') 'offline list'
    sdk install ant 1.10.12 6> $null
    Assert ($LASTEXITCODE -eq 1) 'offline install of new version fails'
    sdk offline disable

    Step 'upgrade / update / flush'
    sdk upgrade ant 6> $null
    Assert ($LASTEXITCODE -eq 0) 'sdk upgrade ant'
    sdk update
    Assert ($LASTEXITCODE -eq 0) 'sdk update'
    sdk flush
    Assert (@(Get-ChildItem (Join-Path $SdkmanDir 'tmp')).Count -eq 0) 'tmp flushed'

    Step 'checksum'
    $module = Get-Module Sdkman
    $file = Join-Path $SdkmanDir 'tmp\checksum.zip'
    $headers = Join-Path $SdkmanDir 'tmp\checksum.headers'
    [IO.File]::WriteAllText($file, 'sdkman')
    $sha256 = '6E0A4D6A5B1E8DB0E7F4B3E3C4DE2B1F6C4A1F4A4C8C0BD9A1F8F7C9E1F3B4D5'
    $actual = & $module { param($f) Get-SdkmanFileHash $f 'SHA256' } $file
    [IO.File]::WriteAllText($headers, "X-Sdkman-Checksum-SHA-256: $($actual.ToLower())`n")
    & $module { param($f, $h) Confirm-SdkmanChecksum $f $h } $file $headers 6> $null
    Assert (Test-Path $file) 'valid checksum keeps archive'
    [IO.File]::WriteAllText($headers, "X-Sdkman-Checksum-SHA-256: $sha256`n")
    $stopped = $false
    try { & $module { param($f, $h) Confirm-SdkmanChecksum $f $h } $file $headers 6> $null } catch { $stopped = $true }
    Assert ($stopped -and -not (Test-Path $file)) 'invalid checksum removes archive'

    Step 'completion'
    $complete = { param($line) @((TabExpansion2 -inputScript $line -cursorColumn $line.Length).CompletionMatches | ForEach-Object { $_.CompletionText }) }
    Assert ((& $complete 'sdk ins') -contains 'install') 'complete command'
    Assert ((& $complete 'sdk install gr') -contains 'gradle') 'complete candidate'
    Assert ((& $complete 'sdk use ant ') -contains '1.10.14') 'complete installed version'
    Assert ((& $complete 'sdk env ') -contains 'install') 'complete env subcommand'
} finally {
    Remove-Module Sdkman -ErrorAction SilentlyContinue
    $env:PATH = $originalPath
    foreach ($dir in $SdkmanDir, $work) {
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Recurse -Directory -Force |
                Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
                ForEach-Object { [IO.Directory]::Delete($_.FullName) }
            Remove-Item -LiteralPath $dir -Recurse -Force
        }
    }
}

Write-Host ''
if ($script:failures -gt 0) {
    Write-Host "$script:failures assertion(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'All assertions passed' -ForegroundColor Green
