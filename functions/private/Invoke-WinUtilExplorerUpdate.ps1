function Invoke-WinUtilExplorerBroadcast {
    param(
        [string]$Setting = 'ImmersiveColorSet'
    )

    if (-not ([System.Management.Automation.PSTypeName]'Win32').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
"@
    }

    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1A
    $SMTO_ABORTIFHUNG = 0x2

    [Win32]::SendMessageTimeout(
        $HWND_BROADCAST,
        $WM_SETTINGCHANGE,
        [IntPtr]::Zero,
        $Setting,
        $SMTO_ABORTIFHUNG,
        1000,
        [ref]([IntPtr]::Zero)
    ) | Out-Null
}

function Restart-WinUtilExplorerShell {
    Write-Host 'Restarting Explorer shell to apply changes...'

    if (Get-Process -Name explorer -ErrorAction SilentlyContinue) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

        $waited = 0
        while ((Get-Process -Name explorer -ErrorAction SilentlyContinue) -and $waited -lt 20) {
            Start-Sleep -Milliseconds 250
            $waited++
        }
    }

    Start-Sleep -Milliseconds 500

    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath "$env:WINDIR\explorer.exe"
    }
}

function Invoke-WinUtilExplorerUpdate {
    <#
    .SYNOPSIS
        Refreshes or restarts the Windows Explorer shell.
    #>
    param (
        [string]$action = "refresh"
    )

    if ($action -eq "refresh") {
        Invoke-WPFRunspace -ScriptBlock {
            Invoke-WinUtilExplorerBroadcast -Setting 'ImmersiveColorSet'
        }
        return
    }

    if ($action -eq "taskbar") {
        Write-Host 'Refreshing taskbar settings without restarting Explorer...'
        foreach ($setting in @('TraySettings', 'WindowsExplorer', 'Policy')) {
            Invoke-WinUtilExplorerBroadcast -Setting $setting
        }
        return
    }

    if ($action -eq "restart") {
        if ($PARAM_NOUI) {
            Restart-WinUtilExplorerShell
        } else {
            Invoke-WPFUIThread -ScriptBlock { Restart-WinUtilExplorerShell }
        }
    }
}