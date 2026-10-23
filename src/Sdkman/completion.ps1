#
#   PowerShell port of SDKMAN! - contrib/completion/bash/sdk
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#

$script:RemoteVersionsCache = @{}

function New-SdkmanCompletionResults([string[]]$Values, [string]$WordToComplete) {
    foreach ($value in $Values) {
        if ($value -and $value -like "$WordToComplete*") {
            New-Object System.Management.Automation.CompletionResult ($value, $value, 'ParameterValue', $value)
        }
    }
}

function Get-SdkmanCompletionCommand([hashtable]$BoundParameters) {
    $command = [string]$BoundParameters['Command']
    if ($script:CommandAliases.Contains($command)) {
        $command = $script:CommandAliases[$command]
    }
    return $command
}

function Get-SdkmanRemoteVersions([string]$Candidate) {
    if (-not $script:RemoteVersionsCache.ContainsKey($Candidate)) {
        $csv = Invoke-SdkmanCurl "$script:CandidatesApi/candidates/$Candidate/$script:Platform/versions/all" -WithTimeouts
        $script:RemoteVersionsCache[$Candidate] = @($csv -split ',' | Where-Object { $_ } | Sort-Object -Descending)
    }
    return $script:RemoteVersionsCache[$Candidate]
}

Register-ArgumentCompleter -CommandName sdk -ParameterName Command -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    New-SdkmanCompletionResults @($script:Commands.Keys) $wordToComplete
}

Register-ArgumentCompleter -CommandName sdk -ParameterName Qualifier -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    Import-SdkmanCandidates
    $values = switch (Get-SdkmanCompletionCommand $fakeBoundParameters) {
        'env' { 'init', 'install', 'clear' }
        'offline' { 'enable', 'disable' }
        'flush' { 'tmp', 'metadata', 'version' }
        { $script:CandidateCommands -contains $_ } { $script:Candidates }
    }
    New-SdkmanCompletionResults @($values) $wordToComplete
}

Register-ArgumentCompleter -CommandName sdk -ParameterName Version -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $candidate = [string]$fakeBoundParameters['Qualifier']
    if (-not $candidate) {
        return
    }
    $values = switch (Get-SdkmanCompletionCommand $fakeBoundParameters) {
        'install' { Get-SdkmanRemoteVersions $candidate }
        { @('uninstall', 'use', 'default', 'home') -contains $_ } { Get-SdkmanInstalledVersions $candidate }
    }
    New-SdkmanCompletionResults @($values) $wordToComplete
}
