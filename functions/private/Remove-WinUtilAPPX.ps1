function Clear-WinUtilAppxCaches {
    $sync.AppxPackageCache = $null
    $sync.AppxProvisionedCache = $null
}

function Write-WinUtilAppxLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "$(Get-Date -Format 'HH:mm:ss') [AppX] $Message"
}

function Update-WinUtilAppxProgressLabel {
    param(
        [Parameter(Mandatory)]
        [string]$Label
    )

    if ($PARAM_NOUI) {
        return
    }

    if (-not (Get-Command Set-WinUtilProgressbar -ErrorAction SilentlyContinue)) {
        return
    }

    $percent = 5
    try {
        if ($null -ne $sync.ProgressBar -and $sync.ProgressBar.Value -ge 5) {
            $percent = [int]$sync.ProgressBar.Value
        }
    } catch {
        $percent = 5
    }

    Set-WinUtilProgressbar -Label $Label -Percent $percent
}

function Get-WinUtilAppxPackages {
    if (-not $sync.AppxPackageCache) {
        $sync.AppxPackageCache = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    }
    return $sync.AppxPackageCache
}

function Get-WinUtilProvisionedPackages {
    if (-not $sync.AppxProvisionedCache) {
        $sync.AppxProvisionedCache = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    }
    return $sync.AppxProvisionedCache
}

function Stop-WinUtilAppxRelatedProcesses {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $patterns = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $null = $patterns.Add($Name)

    $shortName = $Name.Split('.')[-1]
    if ($shortName) {
        $null = $patterns.Add($shortName)
    }

    foreach ($pattern in $patterns) {
        Get-Process -Name "*$pattern*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Get-WinUtilAppxUserSids {
    param(
        [Parameter(Mandatory)]
        $Package
    )

    $sids = [System.Collections.Generic.List[string]]::new()

    if ($Package.PackageUserInformation) {
        foreach ($userInfo in $Package.PackageUserInformation) {
            if ($userInfo.UserSecurityId.Sid) {
                $sids.Add($userInfo.UserSecurityId.Sid) | Out-Null
            }
        }
    }

    if ($sids.Count -eq 0) {
        try {
            foreach ($user in Get-LocalUser | Where-Object { $_.Enabled }) {
                $sids.Add($user.SID.Value) | Out-Null
            }
        } catch {
            $sids.Add((Get-LocalUser $Env:UserName).Sid.Value) | Out-Null
        }
    }

    return @($sids | Select-Object -Unique)
}

function Set-WinUtilAppxEndOfLife {
    param(
        [Parameter(Mandatory)]
        [string]$PackageFullName,

        [Parameter(Mandatory)]
        [string[]]$UserSids
    )

    foreach ($sid in $UserSids) {
        $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\$sid\$PackageFullName"
        New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function Remove-WinUtilAppxPackageInstance {
    param(
        [Parameter(Mandatory)]
        $Package
    )

    $packageFullName = $Package.PackageFullName

    try {
        Remove-AppxPackage -Package $packageFullName -AllUsers -ErrorAction Stop
        return $true
    } catch {
        Write-WinUtilAppxLog "AllUsers removal failed for $packageFullName ($($_.Exception.Message)). Trying fallbacks..."
    }

    $userSids = Get-WinUtilAppxUserSids -Package $Package
    Set-WinUtilAppxEndOfLife -PackageFullName $packageFullName -UserSids $userSids

    try {
        Remove-AppxPackage -Package $packageFullName -AllUsers -ErrorAction Stop
        return $true
    } catch {
        Write-WinUtilAppxLog "Retry after EndOfLife failed for $packageFullName ($($_.Exception.Message)). Trying per-user removal..."
    }

    $removedAny = $false
    if ($Package.PackageUserInformation) {
        foreach ($userInfo in $Package.PackageUserInformation) {
            $userId = if ($userInfo.UserSecurityId.Sid) { $userInfo.UserSecurityId.Sid } else { $userInfo.UserSecurityId.FullName }
            if (-not $userId) {
                continue
            }

            try {
                Remove-AppxPackage -Package $packageFullName -User $userId -ErrorAction Stop
                $removedAny = $true
            } catch {
                Write-Warning "Failed to remove Appx package '$packageFullName' for user '$userId': $($_.Exception.Message)"
            }
        }
    }

    return $removedAny
}

function Remove-WinUtilAPPX {
    <#

    .SYNOPSIS
        Removes all APPX packages that match the given name

    .PARAMETER Name
        The name of the APPX package to remove

    .EXAMPLE
        Remove-WinUtilAPPX -Name "Microsoft.Microsoft3DViewer"

    #>
    param (
        $Name
    )

    $appxPackages = @(Get-WinUtilAppxPackages | Where-Object Name -like $Name)
    $provisionedPackages = @(Get-WinUtilProvisionedPackages | Where-Object DisplayName -like $Name)

    if ($appxPackages.Count -eq 0 -and $provisionedPackages.Count -eq 0) {
        Write-WinUtilAppxLog "Skip $Name - no Appx packages found."
        return $false
    }

    Write-WinUtilAppxLog "Removing $Name ($($appxPackages.Count) installed, $($provisionedPackages.Count) provisioned)"
    Stop-WinUtilAppxRelatedProcesses -Name $Name

    $removedAny = $false

    foreach ($package in $provisionedPackages) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop
            $removedAny = $true
            if ($sync.AppxProvisionedCache) {
                $sync.AppxProvisionedCache = @($sync.AppxProvisionedCache | Where-Object PackageName -ne $package.PackageName)
            }
        } catch {
            Write-Warning "Failed to remove provisioned Appx package '$($package.PackageName)': $($_.Exception.Message)"
        }
    }

    foreach ($package in $appxPackages) {
        if (Remove-WinUtilAppxPackageInstance -Package $package) {
            $removedAny = $true
            if ($sync.AppxPackageCache) {
                $sync.AppxPackageCache = @($sync.AppxPackageCache | Where-Object PackageFullName -ne $package.PackageFullName)
            }
        } else {
            Write-Warning "Failed to remove Appx package '$($package.PackageFullName)' after all fallback attempts."
        }
    }

    return $removedAny
}

function Invoke-WinUtilAppxRemovals {
    param(
        [Parameter(Mandatory)]
        [string[]]$Names,

        [string]$TweakName
    )

    if ($Names.Count -eq 0) {
        return
    }

    $label = if ($TweakName) { $TweakName } else { 'AppX removals' }
    $total = $Names.Count
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-WinUtilAppxLog "Starting $label ($total packages)"
    Update-WinUtilAppxProgressLabel "$label : Scanning installed packages (may take 1-2 min)..."

    Write-WinUtilAppxLog "Scanning installed packages (Get-AppxPackage -AllUsers)..."
    Get-WinUtilAppxPackages | Out-Null
    Write-WinUtilAppxLog "Installed package scan finished in $($stopwatch.Elapsed.ToString('mm\:ss'))"

    Update-WinUtilAppxProgressLabel "$label : Scanning provisioned packages..."
    Write-WinUtilAppxLog "Scanning provisioned packages (Get-AppxProvisionedPackage -Online)..."
    Get-WinUtilProvisionedPackages | Out-Null
    Write-WinUtilAppxLog "Provisioned package scan finished in $($stopwatch.Elapsed.ToString('mm\:ss'))"

    $index = 0
    foreach ($appxName in $Names) {
        $index++
        Update-WinUtilAppxProgressLabel "$label : $index/$total - $appxName"
        Write-WinUtilAppxLog "[$index/$total] Processing $appxName..."
        $itemWatch = [System.Diagnostics.Stopwatch]::StartNew()
        Remove-WinUtilAPPX -Name $appxName | Out-Null
        Write-WinUtilAppxLog "[$index/$total] Finished $appxName in $($itemWatch.Elapsed.ToString('mm\:ss'))"
    }

    Write-WinUtilAppxLog "Completed $label in $($stopwatch.Elapsed.ToString('mm\:ss'))"
    Update-WinUtilAppxProgressLabel "$label : App removals finished"
}