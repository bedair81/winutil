BeforeAll {
    $global:sync = [Hashtable]::Synchronized(@{
        form = [PSCustomObject]@{
            Dispatcher = [PSCustomObject]@{
                Invoke = {
                    param($action)
                    & $action
                }
            }
        }
        runspace = $null
    })

    function global:Invoke-WPFUIThread {
        param($ScriptBlock)
        & $ScriptBlock
    }

    function global:Invoke-WPFRunspace {
        param($ScriptBlock)
        & $ScriptBlock
    }

    . (Join-Path $PSScriptRoot '..\functions\private\Invoke-WinUtilExplorerUpdate.ps1')
}

Describe 'Invoke-WinUtilExplorerUpdate' {
    It 'Restarts Explorer on the UI thread when restart is requested' {
        Mock Restart-WinUtilExplorerShell { }
        Mock Invoke-WPFUIThread { param($ScriptBlock) & $ScriptBlock }

        Invoke-WinUtilExplorerUpdate -action 'restart'

        Should -Invoke Invoke-WPFUIThread -Times 1
        Should -Invoke Restart-WinUtilExplorerShell -Times 1
    }

    It 'Refreshes taskbar settings without restarting Explorer' {
        Mock Invoke-WinUtilExplorerBroadcast { }
        Mock Restart-WinUtilExplorerShell { }

        Invoke-WinUtilExplorerUpdate -action 'taskbar'

        Should -Invoke Invoke-WinUtilExplorerBroadcast -ParameterFilter { $Setting -eq 'TraySettings' } -Times 1
        Should -Invoke Invoke-WinUtilExplorerBroadcast -ParameterFilter { $Setting -eq 'WindowsExplorer' } -Times 1
        Should -Invoke Invoke-WinUtilExplorerBroadcast -ParameterFilter { $Setting -eq 'Policy' } -Times 1
        Should -Invoke Restart-WinUtilExplorerShell -Times 0
    }
}