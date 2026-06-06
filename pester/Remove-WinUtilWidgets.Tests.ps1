BeforeAll {
    $global:sync = [Hashtable]::Synchronized(@{})
    . (Join-Path $PSScriptRoot '..\functions\private\Remove-WinUtilAPPX.ps1')
    . (Join-Path $PSScriptRoot '..\functions\private\Invoke-WinUtilExplorerUpdate.ps1')
    . (Join-Path $PSScriptRoot '..\functions\private\Remove-WinUtilWidgets.ps1')
}

Describe 'Stop-WinUtilWidgetProcesses' {
    It 'Continues when a widget process cannot be stopped' {
        Mock Get-Process { [PSCustomObject]@{ Id = 1234; ProcessName = 'WidgetService' } }
        Mock Stop-Process { throw 'Access is denied.' }
        Mock Write-WinUtilAppxLog { }

        { Stop-WinUtilWidgetProcesses } | Should -Not -Throw

        Should -Invoke Write-WinUtilAppxLog -ParameterFilter { $Message -like '*Could not stop WidgetService*' } -Times 1
    }
}

Describe 'Remove-WinUtilWidgets' {
    It 'Stops processes, removes widget packages, and restarts Explorer' {
        Mock Stop-WinUtilWidgetProcesses { }
        Mock Invoke-WinUtilAppxRemovals { }
        Mock Invoke-WinUtilExplorerUpdate { }
        Mock Write-WinUtilAppxLog { }

        Remove-WinUtilWidgets

        Should -Invoke Invoke-WinUtilAppxRemovals -ParameterFilter {
            $Names -contains 'Microsoft.WidgetsPlatformRuntime' -and
            $Names -contains 'MicrosoftWindows.Client.WebExperience'
        } -Times 1
        Should -Invoke Invoke-WinUtilExplorerUpdate -ParameterFilter { $action -eq 'restart' } -Times 1
    }
}