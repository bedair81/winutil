BeforeAll {
    . (Join-Path $PSScriptRoot '..\functions\private\Set-WinUtilBitLocker.ps1')
}

Describe 'Import-WinUtilBitLockerModule' {
    It 'Imports BitLocker from the system module path' {
        Mock Test-Path { $true } -ParameterFilter { $Path -like '*BitLocker.psd1' }
        Mock Import-Module { }

        { Import-WinUtilBitLockerModule } | Should -Not -Throw

        Should -Invoke Import-Module -ParameterFilter { $Name -like '*BitLocker.psd1' } -Times 1
    }
}

Describe 'Disable-WinUtilBitLocker' {
    It 'Skips when BitLocker is not active' {
        Mock Import-WinUtilBitLockerModule { }
        Mock Get-BitLockerVolume { [PSCustomObject]@{ ProtectionStatus = 'Off' } }
        Mock Disable-BitLocker { }

        Disable-WinUtilBitLocker

        Should -Invoke Disable-BitLocker -Times 0
    }

    It 'Disables BitLocker when protection is on' {
        Mock Import-WinUtilBitLockerModule { }
        Mock Get-BitLockerVolume { [PSCustomObject]@{ ProtectionStatus = 'On' } }
        Mock Disable-BitLocker { }

        Disable-WinUtilBitLocker

        Should -Invoke Disable-BitLocker -Times 1
    }

    It 'Falls back to manage-bde when the BitLocker module cannot load' {
        Mock Import-WinUtilBitLockerModule { throw 'module load failed' }
        Mock Test-WinUtilManageBdeAvailable { $true }
        Mock Invoke-WinUtilManageBde {
            if ($ArgumentList[0] -eq '-status') {
                return 'Protection On'
            }
        }

        Disable-WinUtilBitLocker

        Should -Invoke Invoke-WinUtilManageBde -ParameterFilter { $ArgumentList[0] -eq '-off' } -Times 1
    }
}

Describe 'Test-WinUtilBitLockerActive' {
    It 'Detects active protection from manage-bde output' {
        Test-WinUtilBitLockerActive -MountPoint 'C:' -ManageBdeStatus 'Protection On' | Should -Be $true
        Test-WinUtilBitLockerActive -MountPoint 'C:' -ManageBdeStatus 'Protection Off' | Should -Be $false
    }
}