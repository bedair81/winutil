function Stop-WinUtilWidgetProcesses {
    $patterns = @('*Widget*', '*WebExperience*')

    foreach ($pattern in $patterns) {
        $processes = @(Get-Process -Name $pattern -ErrorAction SilentlyContinue)
        foreach ($process in $processes) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                Write-WinUtilAppxLog "Stopped $($process.ProcessName) (PID $($process.Id))"
            } catch {
                Write-WinUtilAppxLog "Could not stop $($process.ProcessName): $($_.Exception.Message)"
            }
        }
    }
}

function Remove-WinUtilWidgets {
    Write-WinUtilAppxLog 'Starting widget removal'

    Stop-WinUtilWidgetProcesses

    Invoke-WinUtilAppxRemovals -Names @(
        'Microsoft.WidgetsPlatformRuntime'
        'MicrosoftWindows.Client.WebExperience'
    ) -TweakName 'Widgets'

    Invoke-WinUtilExplorerUpdate -action 'restart'
    Write-WinUtilAppxLog 'Widget removal finished'
}