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

    $removedAny = $false

    foreach ($package in $appxPackages) {
        try {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            $removedAny = $true
            if ($sync.AppxPackageCache) {
                $sync.AppxPackageCache = @($sync.AppxPackageCache | Where-Object PackageFullName -ne $package.PackageFullName)
            }
        } catch {
            Write-Warning "Failed to remove Appx package '$($package.PackageFullName)': $($_.Exception.Message)"
        }
    }

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