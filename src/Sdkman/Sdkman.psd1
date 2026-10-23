@{
    RootModule        = 'Sdkman.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '5b0f3c3e-4a51-4d8e-9a0c-2f6b8f0d7e21'
    Author            = 'SDKMAN PowerShell port'
    Description       = 'PowerShell port of SDKMAN! (https://sdkman.io), the Software Development Kit Manager.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('sdk', 'Invoke-SdkmanAutoEnv')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            ProjectUri = 'https://sdkman.io'
            LicenseUri = 'http://www.apache.org/licenses/LICENSE-2.0'
        }
    }
}
