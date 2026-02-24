Configuration StudentBaseline {
    param()

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDSC
    Import-DscResource -Module NetworkingDsc
    Import-DscResource -ModuleName ActivedirectoryDSC


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

        # =========================
        # NETWORK — INTERNAL NIC
        # =========================

        IPAddress Internal_SetIP {
            InterfaceAlias = $Node.InternalNetwork.InterfaceAlias
            IPAddress      = $Node.InternalNetwork.IPAddress
            AddressFamily  = 'IPv4'
        }

        DefaultGatewayAddress Internal_SetGateway {
            InterfaceAlias = $Node.InternalNetwork.InterfaceAlias
            Address        = $Node.InternalNetwork.DefaultGateway
            AddressFamily  = 'IPv4'
            DependsOn      = '[IPAddress]Internal_SetIP'
        }

        NetConnectionProfile Internal_NetworkProfile {
            InterfaceAlias  = $Node.InternalNetwork.InterfaceAlias
            NetworkCategory = $Node.InternalNetwork.NetworkCategory
            DependsOn       = '[IPAddress]Internal_SetIP'
        }

        DnsServerAddress Internal_SetDNS {
            InterfaceAlias = $Node.InternalNetwork.InterfaceAlias
            AddressFamily  = 'IPv4'
            Address        = $Node.InternalNetwork.DNSServers
            DependsOn      = '[IPAddress]Internal_SetIP'
        }

        # =========================
        # NETWORK — EXTERNAL NIC
        # =========================

        NetConnectionProfile External_NetworkProfile {
            InterfaceAlias  = $Node.ExternalNetwork.InterfaceAlias
            NetworkCategory = $Node.ExternalNetwork.NetworkCategory
        }

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