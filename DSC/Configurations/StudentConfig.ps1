<#
STUDENT TASK:
- Define Configuration StudentBaseline
- Use ConfigurationData (AllNodes.psd1)
- DO NOT hardcode passwords here.
#>

Configuration StudentBaseline {
    param()

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDSC
    #Import-DscResource -ModuleName ActivedirectoryDSC

    Node $AllNodes.NodeName {

        Computer ComputerName {
            Name = $Node.ComputerName           
        }

        TimeZone TimeZone {
            IsSingleInstance = 'Yes'
            TimeZone = $Node.TimeZone
        }

        Service WindowsTimeService {
            Name = 'W32Time'
            State = 'Running'
            StartupType = 'Automatic'
            DependsOn = '[TimeZone]TimeZone'
        }
C       
        WindowsFeature ADDSRole {
            Name = 'AD-Domain-Services'
            Ensure = 'Present'
        }

        WindowsFeature RSATADDSRole {
            Name = 'RSAT-AD-Tools'
            Ensure = 'Present'
            DependsOn = '[WindowsFeature]ADDSRole'
        }

    }
}
