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

        if ($Node.Role -ne 'RootDC') {
            NetConnectionProfile Internal_NetworkProfile {
                InterfaceAlias  = $Node.InternalNetwork.InterfaceAlias
                NetworkCategory = $Node.InternalNetwork.NetworkCategory
                DependsOn       = '[IPAddress]Internal_SetIP'
            }
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
        if ($Node.Role -ne 'RootDC') {
            NetConnectionProfile External_NetworkProfile {
                InterfaceAlias  = $Node.ExternalNetwork.InterfaceAlias
                NetworkCategory = $Node.ExternalNetwork.NetworkCategory
            }
        }

        DnsConnectionSuffix DisableNatDnsRegistration {
            InterfaceAlias                 = $Node.InternalNetwork.InterfaceAlias
            RegisterThisConnectionsAddress = $false
            ConnectionSpecificSuffix       = $Node.DomainName
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

        # --- User Creation ---
        foreach ($user in $Node.Users) {
            ADUser "User_$($user.UserName)" {
                UserName   = $user.UserName
                GivenName  = $user.GivenName
                Surname    = $user.Surname
                Ensure     = 'Present'
                Password   = $UserCredential
                DomainName = $Node.DomainName
                Path       = "OU=$($user.OU),DC=barmbuzz,DC=corp"
                Credential = $DomainAdminCredential
                DependsOn  = '[ADOrganizationalUnit]OU_Users'
            }
        }


        # --- Admin Groups ---

        foreach ($group in $Node.AdminGroups) {
            ADGroup "Group_$($group.Name)" {
            GroupName        = $group.Name
            GroupScope       = 'Global'
            Category         = 'Security'
            Path             = "OU=Groups,DC=barmbuzz,DC=corp"
            Ensure           = 'Present'
            MembersToInclude = $group.Members
            Credential       = $DomainAdminCredential
            DependsOn = @(
                '[ADOrganizationalUnit]OU_Groups',
                '[ADUser]User_admin.enterprise',
                '[ADUser]User_admin.schema',
                '[ADUser]User_admin.domain'
            )           

            }
        }
    }
}