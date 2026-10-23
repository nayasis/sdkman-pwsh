#
#   PowerShell port of SDKMAN! - curl helpers from sdkman-utils.sh
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#

$script:HttpClients = @{}

function Get-SdkmanHttpClient {
    $insecure = Test-SdkmanConfig 'sdkman_insecure_ssl'
    if (-not $script:HttpClients.ContainsKey($insecure)) {
        Add-Type -AssemblyName System.Net.Http
        if ($PSVersionTable.PSEdition -ne 'Core') {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        }

        # Redirects are followed manually so that X-Sdkman-* headers of every hop can be collected,
        # the same way `curl --location --dump-header` does.
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $false
        if ($insecure) {
            $handler.ServerCertificateCustomValidationCallback = [System.Net.Http.HttpClientHandler]::DangerousAcceptAnyServerCertificateValidator
        }

        $client = New-Object System.Net.Http.HttpClient -ArgumentList $handler
        $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
        $client.DefaultRequestHeaders.UserAgent.ParseAdd("sdkman-powershell/$script:SdkmanVersion")
        $script:HttpClients[$insecure] = $client
    }
    return $script:HttpClients[$insecure]
}

# Requests without an explicit time limit give up after this long, and downloads abort
# when no data arrives for this long, instead of hanging forever on a stalled server.
$script:DefaultTimeoutSeconds = 60

# Waits for a .NET task and returns its result, or throws when it is not done by the deadline.
function Wait-SdkmanTask([Threading.Tasks.Task]$Task, [DateTime]$Deadline) {
    $remaining = $Deadline - [DateTime]::UtcNow
    if ($remaining -lt [TimeSpan]::Zero) {
        $remaining = [TimeSpan]::Zero
    }
    if ([Threading.Tasks.Task]::WaitAny([Threading.Tasks.Task[]]@($Task), $remaining) -lt 0) {
        throw 'Timed out waiting for the server'
    }
    return $Task.GetAwaiter().GetResult()
}

function Send-SdkmanRequest([string]$Url, [DateTime]$Deadline, [hashtable]$CollectHeaders = $null) {
    $client = Get-SdkmanHttpClient
    $uri = New-Object System.Uri $Url

    for ($hop = 0; $hop -lt 20; $hop++) {
        $request = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Get, $uri)
        $cts = New-Object System.Threading.CancellationTokenSource
        try {
            $response = Wait-SdkmanTask ($client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cts.Token)) $Deadline
        } catch {
            $cts.Cancel()
            throw
        } finally {
            $cts.Dispose()
        }

        if ($null -ne $CollectHeaders) {
            foreach ($header in $response.Headers) {
                if ($header.Key -like 'X-Sdkman*') {
                    $CollectHeaders[$header.Key] = ($header.Value -join ',')
                }
            }
        }

        $status = [int]$response.StatusCode
        if ($status -ge 300 -and $status -lt 400 -and $null -ne $response.Headers.Location) {
            $location = $response.Headers.Location
            if (-not $location.IsAbsoluteUri) {
                $location = New-Object System.Uri ($uri, $location)
            }
            Write-SdkmanDebug "Redirect ($status): $location"
            $uri = $location
            $response.Dispose()
            continue
        }
        return $response
    }
    throw "Too many redirects: $Url"
}

# Equivalent of __sdkman_secure_curl / __sdkman_secure_curl_with_timeouts:
# returns the response body, or an empty string when the request fails.
# Error responses count as failures unless -AnyStatus is given (used to spot proxy pages).
function Invoke-SdkmanCurl([string]$Url, [switch]$WithTimeouts, [switch]$AnyStatus) {
    $timeout = $script:DefaultTimeoutSeconds
    if ($WithTimeouts) {
        $timeout = [int]$script:Config['sdkman_curl_max_time']
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($timeout)

    try {
        $response = Send-SdkmanRequest $Url $deadline
        try {
            if (-not $AnyStatus -and -not $response.IsSuccessStatusCode) {
                throw "HTTP $([int]$response.StatusCode) $($response.ReasonPhrase)"
            }
            $body = Wait-SdkmanTask ($response.Content.ReadAsStringAsync()) $deadline
            return $body.TrimEnd("`r", "`n")
        } finally {
            $response.Dispose()
        }
    } catch {
        Write-SdkmanDebug "Request failed: $Url ($($_.Exception.Message))"
        return ''
    }
}

# Equivalent of __sdkman_secure_curl_download: streams the body to a file with a progress bar.
function Invoke-SdkmanDownloadFile([string]$Url, [string]$OutFile, [hashtable]$Headers) {
    $retries = 0
    [int]::TryParse([string]$script:Config['sdkman_curl_retry'], [ref]$retries) | Out-Null

    for ($attempt = 0; ; $attempt++) {
        try {
            Receive-SdkmanFile $Url $OutFile $Headers
            return
        } catch {
            if ($attempt -ge $retries) {
                throw
            }
            Write-SdkmanYellow "Download failed ($($_.Exception.Message)), retrying..."
        }
    }
}

function Receive-SdkmanFile([string]$Url, [string]$OutFile, [hashtable]$Headers) {
    $response = Send-SdkmanRequest $Url ([DateTime]::UtcNow.AddSeconds($script:DefaultTimeoutSeconds)) $Headers
    try {
        if (-not $response.IsSuccessStatusCode) {
            throw "HTTP $([int]$response.StatusCode) $($response.ReasonPhrase)"
        }

        $total = $response.Content.Headers.ContentLength
        $activity = "Downloading $(Split-Path -Leaf $OutFile)"
        $in = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $out = [IO.File]::Create($OutFile)
        try {
            $buffer = New-Object byte[] 262144
            $done = [long]0
            $watch = [Diagnostics.Stopwatch]::StartNew()
            while ($true) {
                # Disposing the response in the finally blocks aborts a read that timed out
                $read = Wait-SdkmanTask ($in.ReadAsync($buffer, 0, $buffer.Length)) ([DateTime]::UtcNow.AddSeconds($script:DefaultTimeoutSeconds))
                if ($read -le 0) {
                    break
                }
                $out.Write($buffer, 0, $read)
                $done += $read
                if ($watch.ElapsedMilliseconds -ge 250) {
                    $watch.Restart()
                    if ($total -gt 0) {
                        $status = '{0:N1} MB / {1:N1} MB' -f ($done / 1MB), ($total / 1MB)
                        Write-Progress -Activity $activity -Status $status -PercentComplete ([int](100 * $done / $total))
                    } else {
                        Write-Progress -Activity $activity -Status ('{0:N1} MB' -f ($done / 1MB))
                    }
                }
            }
        } finally {
            $out.Dispose()
            $in.Dispose()
            Write-Progress -Activity $activity -Completed
        }
    } finally {
        $response.Dispose()
    }
}
