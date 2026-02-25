Configuration StudentBaseline {
    param(

    [Parameter(Mandatory = $true)]
    [PSCredential]
    $DomainAdminCredential,

    [Parameter (Mandatory = $true)]
    [PSCredential]
    $DsrmCredential,

    [Parameter(Mandatory = $true)]
    [PSCredential]
    $UserCredential

    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDSC
    Import-DscResource -ModuleName NetworkingDsc
    Import-DscResource -ModuleName ActiveDirectoryDsc


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
            DependsOn      = '[Computer]ComputerName'
        }
        if ($Node.InternalNetwork.DefaultGateway) {
            DefaultGatewayAddress Internal_SetGateway {
                InterfaceAlias = $Node.InternalNetwork.InterfaceAlias
                Address        = $Node.InternalNetwork.DefaultGateway
                AddressFamily  = 'IPv4'
                DependsOn      = '[IPAddress]Internal_SetIP'
            }
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

        DnsConnectionSuffix DisableNatDnsRegistration {
            InterfaceAlias                 = $Node.InternalNetwork.InterfaceAlias
            RegisterThisConnectionsAddress = $false
            DependsOn                      = '[DnsServerAddress]Internal_SetDNS'
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

        # =========================
        # PROMOTION TO DOMAIN CONTROLLER
        # =========================

        ADDomain CreateForest {
            DomainName = $Node.DomainName
            DomainNetBiosName = $Node.DomainNetBiosName
            Credential = $DomainAdminCredential
            SafeModeAdministratorPassword =  $DsrmCredential
            ForestMode = $Node.ForestMode
            DomainMode = $Node.DomainMode
            DependsOn = @(
                '[WindowsFeature]ADDSRole',
                '[WindowsFeature]Feature_DNS',
                '[PendingReboot]RebootCheck'
            )
        }

        # =========================
        # ROOT DOMAIN OU's
        # =========================

        foreach ($OU in $Node.OrganizationalUnits) {
            ADOrganizationalUnit "OU_$OU" {
                Name                            = $OU
                Path                            = "DC=barmbuzz,DC=corp"
                Ensure                          = 'Present'
                ProtectedFromAccidentalDeletion = $true
                Credential                      = $DomainAdminCredential
                DependsOn                       = '[ADDomain]CreateForest'
            }
        }
    }
}