function Clear-WinUtilAppxCaches {
    $sync.AppxPackageCache = $null
    $sync.AppxProvisionedCache = $null
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
        Write-Host "Skip $Name - no Appx packages found."
        return $false
    }

    Write-Host "Removing $Name"

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
        [string[]]$Names
    )

    if ($Names.Count -eq 0) {
        return
    }

    Get-WinUtilAppxPackages | Out-Null
    Get-WinUtilProvisionedPackages | Out-Null

    foreach ($appxName in $Names) {
        Remove-WinUtilAPPX -Name $appxName | Out-Null
    }
}