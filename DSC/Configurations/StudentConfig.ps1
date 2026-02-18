Configuration StudentBaseline {
    param()

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDSC
    Import-DscResource -Module NetworkingDsc
    #Import-DscResource -ModuleName ActivedirectoryDSC

    Node $AllNodes.NodeName {
        
        # --- Identity ---

        Computer ComputerName {
            Name = $Node.ComputerName           
        }


        # --- Time ---

        TimeZone TimeZone {
            IsSingleInstance = 'Yes'
            TimeZone = $Node.TimeZone
        }

        if ($Node.EnsureW32TimeService) {
            Service WindowsTimeService {
                Name = 'W32Time'
                State = 'Running'
                StartupType = 'Automatic'
                DependsOn = '[TimeZone]TimeZone'
            }
        }
       
        # --- [ Network ] --- 
    # {
        # Install-Module NetworkingDsc -Repository PSGallery -Force
        # Will need to install module on local machine.


        # Static IPS
         #DHCP disaled to prevent conflicts with static IP configuration

        IPAddress SetIP {
            InterfaceAlias = $Node.Network.InterfaceAlias
            IPAddress      = $Node.Network.IPAddress
            AddressFamily  = 'IPv4'
    

        }

        # Default Gateway
        DefaultGatewayAddress SetGateway {
            InterfaceAlias = $Node.Network.InterfaceAlias
            Address        = $Node.Network.DefaultGateway
            AddressFamily  = 'IPv4'
        }

        # Set Network Category to Private for pre-promotion configuration
        NetConnectionProfile NetworkProfile {
             InterfaceAlias = $Node.Network.InterfaceAlias
             NetworkCategory = $Node.Network.NetworkCategory
        }

        DnsServerAddress SetDNS {
            InterfaceAlias = $Node.Network.InterfaceAlias
            AddressFamily  = 'IPv4'
            Address = $Node.Network.DNSServers
        }
    # }
        # --- Firewalls ---
        FirewallProfile SetPrivateFirewall {
            Name    = 'Private'
            Enabled = 'True'
        }

        FirewallProfile SetPublicFirewall {
            Name    = 'Public'
            Enabled = 'True'
        }

        FirewallProfile SetDomainFirewall {
            Name    = 'Domain'
            Enabled = 'True'
        }
        

        # --- Services ---
        # ADDS Role seperately defined to ensure it is installed before dependent features
        if ($Node.InstallADDSRole) {
            WindowsFeature ADDSRole {
                Name   = 'AD-Domain-Services'
                Ensure = 'Present'
            }
        }

        foreach ($feature in $Node.WindowsFeatures) {
            WindowsFeature "Feature_$feature" {
                Name   = $feature
                Ensure = 'Present'
            }
        }
        if ($Node.WinRMService) {
            Service WinRMService {
                Name        = 'WinRM'
                State       = 'Running'
                StartupType = 'Automatic'
            }
        }

        # --- Reboot Checks ---
        PendingReboot RebootCheck {
            Name = 'PostBaselineRebootChecks'
        }
    }
}
