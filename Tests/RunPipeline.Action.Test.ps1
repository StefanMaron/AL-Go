Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "RunPipeline Action Tests" {
    BeforeAll {
        $actionName = "RunPipeline"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    # ConvertFrom-Json returns a plain string, not a one-element array, when the source JSON array has
    # exactly one entry. installAppsJson/installTestAppsJson can legitimately contain just one app (e.g. a
    # single cross-project dependency), so the script must wrap the result in @(...) - otherwise a single
    # app whose publisher name contains a comma gets handed to Run-AlPipeline as a bare string, which then
    # re-splits it on commas and reports the app as two nonexistent files.
    It 'installAppsJson with a single entry stays an array after parsing' {
        $scriptContent = Get-Content -Path $scriptPath -Raw
        $scriptContent | Should -Match ([regex]::Escape('$install.Apps = @((Get-Content -Path $installAppsJson -Raw | ConvertFrom-Json) | Where-Object { $_ })'))

        $tempJson = Join-Path $TestDrive 'DownloadedApps.json'
        $appPath = 'C:\deps\Stoneridge Software, LLC_Longhorn Midstream BC Extension_25.2.2147483647.2.app'
        ConvertTo-Json @($appPath) -Compress | Out-File -Encoding UTF8 -FilePath $tempJson

        $install = @((Get-Content -Path $tempJson -Raw | ConvertFrom-Json) | Where-Object { $_ })
        $install.Count | Should -Be 1
        $install[0] | Should -Be $appPath
    }

    It 'installTestAppsJson with a single entry stays an array after parsing' {
        $scriptContent = Get-Content -Path $scriptPath -Raw
        $scriptContent | Should -Match ([regex]::Escape('$install.TestApps = @((Get-Content -Path $installTestAppsJson -Raw | ConvertFrom-Json) | Where-Object { $_ })'))
    }

    # On Windows PowerShell 5.1 ConvertFrom-Json emits a JSON array as a single object, so wrapping it
    # directly in @(...) turns '[]' into a one-element array holding an empty array. That element is falsy
    # (the parameter dump still prints '- None') but counts as 1; Run-AlPipeline's installOnlyReferencedApps
    # branch then appends it to installTestApps, the list turns truthy, and the install loop hands
    # CopyAppFilesToFolder an empty Path. Enumerating through Where-Object keeps an empty list empty on
    # both PowerShell editions.
    It 'installAppsJson with an empty or null list parses to an empty array' {
        $tempJson = Join-Path $TestDrive 'DownloadedApps.json'
        foreach ($content in @('[]', 'null', '[null]')) {
            Set-Content -Path $tempJson -Value $content -Encoding UTF8
            $install = @((Get-Content -Path $tempJson -Raw | ConvertFrom-Json) | Where-Object { $_ })
            $install.Count | Should -Be 0 -Because "file content '$content' must not produce phantom install entries"
        }
    }

    # Call action

}
