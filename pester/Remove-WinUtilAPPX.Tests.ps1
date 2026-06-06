BeforeAll {
    $global:sync = [Hashtable]::Synchronized(@{})
    . (Join-Path $PSScriptRoot '..\functions\private\Remove-WinUtilAPPX.ps1')
}

Describe 'Remove-WinUtilAPPX' {
    It 'Skips removal when no packages are found' {
        Mock Get-AppxPackage { @() }
        Mock Get-AppxProvisionedPackage { @() }
        Mock Remove-AppxPackage { }
        Mock Remove-AppxProvisionedPackage { }

        Remove-WinUtilAPPX -Name 'Contoso.App'

        Should -Invoke Remove-AppxPackage -Times 0
        Should -Invoke Remove-AppxProvisionedPackage -Times 0
    }

    It 'Uses cached installed packages across calls' {
        Mock Get-AppxPackage { [PSCustomObject]@{ Name = 'Contoso.App'; PackageFullName = 'Contoso.App_1.0' } }
        Mock Get-AppxProvisionedPackage { @() }
        Mock Remove-AppxPackage { }
        Mock Remove-AppxProvisionedPackage { }

        Remove-WinUtilAPPX -Name 'Contoso.App'
        Remove-WinUtilAPPX -Name 'Missing.App'

        Should -Invoke Get-AppxPackage -Times 1
    }

    It 'Uses cached provisioned packages across calls' {
        Mock Get-AppxPackage { @() }
        Mock Get-AppxProvisionedPackage { [PSCustomObject]@{ DisplayName = 'Contoso.App'; PackageName = 'Contoso.App_1.0' } }
        Mock Remove-AppxProvisionedPackage { }

        Remove-WinUtilAPPX -Name 'Contoso.App'
        Remove-WinUtilAPPX -Name 'Contoso.App'

        Should -Invoke Get-AppxProvisionedPackage -Times 1
    }

    It 'Removes package from caches after successful removal' {
        $global:sync.AppxPackageCache = @([PSCustomObject]@{ Name = 'Contoso.App'; PackageFullName = 'Contoso.App_1.0' })
        $global:sync.AppxProvisionedCache = @(
            [PSCustomObject]@{ DisplayName = 'Contoso.App'; PackageName = 'Contoso.App_1.0' },
            [PSCustomObject]@{ DisplayName = 'Other.App'; PackageName = 'Other.App_1.0' }
        )
        Mock Remove-AppxPackage { }
        Mock Remove-AppxProvisionedPackage { }

        Remove-WinUtilAPPX -Name 'Contoso.App'

        $global:sync.AppxPackageCache.Count | Should -Be 0
        $global:sync.AppxProvisionedCache.Count | Should -Be 1
        $global:sync.AppxProvisionedCache[0].DisplayName | Should -Be 'Other.App'
    }

    It 'Writes warning when package removal fails after fallbacks' {
        $global:sync.AppxPackageCache = @([PSCustomObject]@{ Name = 'Contoso.App'; PackageFullName = 'Contoso.App_1.0' })
        Mock Remove-AppxPackage { throw 'Access is denied.' }
        Mock Get-LocalUser { [PSCustomObject]@{ SID = [PSCustomObject]@{ Value = 'S-1-5-21-1' }; Enabled = $true } }
        Mock Write-Warning { } -ParameterFilter { $Message -like '*after all fallback attempts*' }

        Remove-WinUtilAPPX -Name 'Contoso.App'

        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*after all fallback attempts*' }
    }

    It 'Retries removal with EndOfLife when AllUsers removal is denied' {
        $package = [PSCustomObject]@{
            Name                   = 'Microsoft.Windows.DevHome'
            PackageFullName        = 'Microsoft.Windows.DevHome_1.0_x64__8wekyb3d8bbwe'
            PackageUserInformation = @(
                [PSCustomObject]@{
                    UserSecurityId = [PSCustomObject]@{
                        Sid      = 'S-1-5-21-1000'
                        FullName = 'TEST\user'
                    }
                }
            )
        }
        $global:sync.AppxPackageCache = @($package)

        $callCount = 0
        Mock Remove-AppxPackage {
            $script:callCount++
            if ($script:callCount -le 2) {
                throw 'Access is denied.'
            }
        }
        Mock New-Item { }

        Remove-WinUtilAPPX -Name 'Microsoft.Windows.DevHome'

        Should -Invoke Remove-AppxPackage -Times 3
        Should -Invoke New-Item -ParameterFilter { $Path -like '*EndOfLife*S-1-5-21-1000*' } -Times 1
    }
}

Describe 'Invoke-WinUtilAppxRemovals' {
    It 'Loads package lists once for a batch of removals' {
        Mock Get-AppxPackage { @() }
        Mock Get-AppxProvisionedPackage { @() }
        Mock Remove-AppxPackage { }
        Mock Remove-AppxProvisionedPackage { }

        Invoke-WinUtilAppxRemovals -Names @('Contoso.App', 'Other.App', 'Third.App')

        Should -Invoke Get-AppxPackage -Times 1
        Should -Invoke Get-AppxProvisionedPackage -Times 1
    }

    It 'Writes progress logs for scan and per-package steps' {
        Mock Get-AppxPackage { @() }
        Mock Get-AppxProvisionedPackage { @() }

        $logs = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $logs.Add($Object) }

        Invoke-WinUtilAppxRemovals -Names @('Contoso.App', 'Other.App') -TweakName 'DeBloat Test'

        $logText = $logs -join "`n"
        $logText | Should -Match 'Scanning installed packages'
        $logText | Should -Match 'Processing Contoso\.App'
        $logText | Should -Match 'Completed DeBloat Test'
    }
}