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

    $ChildDomainCredential = New-Object System.Management.Automation.PSCredential(
        "Administrator@derby.barmbuzz.corp",
        $DomainAdminCredential.Password
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDSC
    Import-DscResource -ModuleName NetworkingDsc
    Import-DscResource -ModuleName ActiveDirectoryDsc


    Node $AllNodes.Where({ $_.Role -eq 'RootDC' }).NodeName {

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
        
        # Redundant but for future nodes. 
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
        # Redundant but for future nodes. 
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
                DependsOn = '[Computer]ComputerName'            
            }
        }

        foreach ($feature in $Node.WindowsFeatures) {
            WindowsFeature "Feature_$feature" {
                Name   = $feature
                Ensure = 'Present'
                DependsOn = '[WindowsFeature]ADDSRole'
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
        # IDENTITY PLAIN
        # =========================

        # --- OU's ---

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
                DependsOn  = @(
                '[ADOrganizationalUnit]OU_BOL_Users', 
                '[ADDomain]CreateForest',
                '[ADDomainDefaultPasswordPolicy]RelaxDefaultPolicy'
                )
            }
        }

        # --- Admin Groups ---
            
        foreach ($group in $Node.AdminGroups) {
            ADGroup "Group_$($group.Name)" {
            GroupName        = $group.Name
            GroupScope       = 'Global'
            Category         = 'Security'
            Path             = "OU=BOL_Admin_Groups,DC=barmbuzz,DC=corp"
            Ensure           = 'Present'
            MembersToInclude = $group.Members
            Credential       = $DomainAdminCredential
            DependsOn = @(
                '[ADOrganizationalUnit]OU_BOL_Admin_Groups',
                '[ADUser]User_admin.enterprise',
                '[ADUser]User_admin.schema',
                '[ADUser]User_admin.domain'
            )      
            }
        }

        # Relax the global password policy scope. 
        # FGPP will be implemented for admins.

        # --- Password Policy ---

        ADDomainDefaultPasswordPolicy RelaxDefaultPolicy {
            DomainName                  = $Node.DomainName
            ComplexityEnabled           = $false
            MinPasswordLength           = 6
            PasswordHistoryCount        = 0
            Credential                  = $DomainAdminCredential
            DependsOn                   = '[ADDomain]CreateForest'
        }

        ADFineGrainedPasswordPolicy StrongerAdminPasswordPolicy{
            Name                        = 'BOL_Stronger_Admin_Password_Policy'
            Precedence                  = 1 # High priority over other FGP Policies
            ComplexityEnabled           = $true # Ensure it has special character/numbers etc
            MinPasswordLength           = 12 
            PasswordHistoryCount        = 24
            MinPasswordAge              = '00:01:00'    # Can change password after 1 day
            MaxPasswordAge              = '90.00:00:00' # Expires in 90 days
            LockoutThreshold            = 5    # Num of Attempts
            LockoutDuration             = '00:30:00'
            LockoutObservationWindow    = '00:30:00'
            Subjects                    = @(
                'G_Enterprise_Admins',
                'G_Schema_Admins',
                'G_Domain_Admins'
            )
            Credential                  = $DomainAdminCredential
            DependsOn                   = '[ADGroup]Group_G_Enterprise_Admins'
        }

        
        # GPO Idle Time
        Script GPO_IdleTimeout {
            GetScript = {
                $gpo = Get-GPO -Name 'BOL_IdleTimedout' -ErrorAction SilentlyContinue
                return @{ Result = if ($gpo) { 'Present' } else { 'Absent' } }
                # Set result to true if found.
            }
            TestScript = {
                $gpo = Get-GPO -Name 'BOL_IdleTimedout' -ErrorAction SilentlyContinue
                return ($null -ne $gpo)
            }
            SetScript = {
                # Creates the actual GPO here
                New-GPO -Name 'BOL_IdleTimedout'

                # Set screen saver timeout to 5 minutes (300 seconds)
                Set-GPRegistryValue -Name 'BOL_IdleTimedout' `
                    -Key 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop' `
                    -ValueName 'ScreenSaveTimeOut' `
                    -Type String -Value '300'

                # Force the screen saver to be enabled
                Set-GPRegistryValue -Name 'BOL_IdleTimedout' `
                    -Key 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop' `
                    -ValueName 'ScreenSaveActive' `
                    -Type String -Value '1'

                # Link it to your users OU
                New-GPLink -Name 'BOL_IdleTimedout' `
                    -Target 'OU=BOL_Users,DC=barmbuzz,DC=corp' `
                    -LinkEnabled Yes
            }
            DependsOn = '[ADDomain]CreateForest'
            PsDscRunAsCredential = $DomainAdminCredential
        }
    }
    Node $AllNodes.Where({ $_.Role -eq 'ChildDC' }).NodeName {

    # --- Identity ---
    Computer ComputerName {
        Name = $Node.ComputerName
    }

    # --- Time ---
    TimeZone TimeZone {
        IsSingleInstance = 'Yes'
        TimeZone         = $Node.TimeZone
    }

    if ($Node.EnsureW32TimeService) {
        Service WindowsTimeService {
            Name        = 'W32Time'
            State       = 'Running'
            StartupType = 'Automatic'
            DependsOn   = '[TimeZone]TimeZone'
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

    DnsServerAddress Internal_SetDNS {
        InterfaceAlias = $Node.InternalNetwork.InterfaceAlias
        AddressFamily  = 'IPv4'
        Address        = $Node.InternalNetwork.DNSServers
        DependsOn      = '[IPAddress]Internal_SetIP'
    }

    # =========================
    # NETWORK — EXTERNAL NIC
    # =========================

    DnsConnectionSuffix DisableNatDnsRegistration {
        InterfaceAlias                 = $Node.ExternalNetwork.InterfaceAlias
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
            Name      = 'AD-Domain-Services'
            Ensure    = 'Present'
            DependsOn = '[Computer]ComputerName'
        }
    }

    foreach ($feature in $Node.WindowsFeatures) {
        WindowsFeature "Feature_$feature" {
            Name      = $feature
            Ensure    = 'Present'
            DependsOn = '[WindowsFeature]ADDSRole'
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
        Name      = 'PostBaselineRebootChecks'
        DependsOn = '[WindowsFeature]ADDSRole'
    }

    # =========================
    # PROMOTION TO CHILD DOMAIN CONTROLLER
    # =========================
    
    ADDomain CreateChildDomain {
        DomainName                    = $Node.ChildDomainName
        ParentDomainName              = $Node.ParentDomainName
        Credential = $ChildDomainCredential
        SafeModeAdministratorPassword = $DsrmCredential
        ForestMode                    = $Node.ForestMode
        DomainMode                    = $Node.DomainMode

        DependsOn = @(
            '[WindowsFeature]ADDSRole',
            '[WindowsFeature]Feature_DNS',
            '[PendingReboot]RebootCheck'
        )
    }

        foreach ($ou in $Node.OrganizationalUnits) {
        ADOrganizationalUnit "OU_$($ou.Name)" {
            Name                            = $ou.Name
            Path                            = $ou.Path
            Ensure                          = 'Present'
            ProtectedFromAccidentalDeletion = $true
            Credential                      = $ChildDomainCredential
            DomainController                = $Node.DomainController
            DependsOn                       = '[ADDomain]CreateChildDomain'
        }
    }

    }
}