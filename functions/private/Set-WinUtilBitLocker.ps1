function Test-WinUtilManageBdeAvailable {
    return Test-Path (Join-Path $env:Windir 'System32\manage-bde.exe')
}

function Invoke-WinUtilManageBde {
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    $manageBde = Join-Path $env:Windir 'System32\manage-bde.exe'
    & $manageBde @ArgumentList
}

function Import-WinUtilBitLockerModule {
    $modulePath = Join-Path $env:Windir 'System32\WindowsPowerShell\v1.0\Modules\BitLocker\BitLocker.psd1'

    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -ErrorAction Stop
        return
    }

    Import-Module BitLocker -Force -SkipEditionCheck -ErrorAction Stop
}

function Get-WinUtilBitLockerMountPoint {
    return $env:SystemDrive
}

function Test-WinUtilBitLockerActive {
    param(
        [Parameter(Mandatory)]
        [string]$MountPoint,

        [string]$ManageBdeStatus
    )

    if ($ManageBdeStatus) {
        return $ManageBdeStatus -match 'Protection On|Fully Encrypted|Encryption in Progress'
    }

    $volume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    return $volume.ProtectionStatus -eq 'On'
}

function Disable-WinUtilBitLocker {
    $mountPoint = Get-WinUtilBitLockerMountPoint

    try {
        Import-WinUtilBitLockerModule | Out-Null

        if (-not (Test-WinUtilBitLockerActive -MountPoint $mountPoint)) {
            Write-Host "BitLocker is not active on $mountPoint, skipping."
            return
        }

        Write-Host "Disabling BitLocker on $mountPoint..."
        Disable-BitLocker -MountPoint $mountPoint -ErrorAction Stop
        Write-Host "BitLocker disabled on $mountPoint."
        return
    } catch {
        Write-Warning "BitLocker module unavailable ($($_.Exception.Message)). Trying manage-bde..."
    }

    if (-not (Test-WinUtilManageBdeAvailable)) {
        throw "BitLocker tools are not available on this system."
    }

    $status = Invoke-WinUtilManageBde -ArgumentList @('-status', $mountPoint) 2>&1 | Out-String
    if (-not (Test-WinUtilBitLockerActive -MountPoint $mountPoint -ManageBdeStatus $status)) {
        Write-Host "BitLocker does not appear active on $mountPoint, skipping."
        return
    }

    Write-Host "Disabling BitLocker on $mountPoint via manage-bde..."
    Invoke-WinUtilManageBde -ArgumentList @('-off', $mountPoint) | Out-Null
    Write-Host "BitLocker decryption started on $mountPoint. This may take a while to complete."
}

function Enable-WinUtilBitLocker {
    $mountPoint = Get-WinUtilBitLockerMountPoint

    try {
        Import-WinUtilBitLockerModule | Out-Null

        if (Test-WinUtilBitLockerActive -MountPoint $mountPoint) {
            Write-Host "BitLocker is already active on $mountPoint, skipping."
            return
        }

        Write-Host "Enabling BitLocker on $mountPoint..."
        Enable-BitLocker -MountPoint $mountPoint -TpmProtector -ErrorAction Stop
        Write-Host "BitLocker enabled on $mountPoint."
    } catch {
        Write-Warning "Unable to enable BitLocker on ${mountPoint}: $($_.Exception.Message)"
    }
}