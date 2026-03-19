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

    # =========================
    # IDENTITY PLAIN
    # =========================

    # --- OU's ---

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

    # --- User Creation ---
    foreach ($user in $Node.Users) {
        ADUser "DER_User_$($user.UserName)" {
            UserName   = $user.UserName
            GivenName  = $user.GivenName
            Surname    = $user.Surname
            Ensure     = 'Present'
            Password   = $UserCredential
            DomainName = $Node.DomainName
            Path       = "OU=$($user.OU),OU=DER_Users,DC=derby,DC=barmbuzz,DC=corp"
            Credential = $ChildDomainCredential
            DependsOn  = @(
                '[ADOrganizationalUnit]OU_DER_Staff',
                '[ADOrganizationalUnit]OU_DER_Admins',
                '[ADDomain]CreateChildDomain',
                '[ADDomainDefaultPasswordPolicy]RelaxDefaultPolicy'

            )
        }
    }

    # --- Business Role Groups 
    foreach ($group in $Node.BusinessRoleGroups) {
        ADGroup "DER_ROLE_$($group.Name)" {
            GroupName        = $group.Name
            GroupScope       = 'Global'
            Category         = 'Security'
            Path             = "OU=DER_BusinessRoles,OU=DER_Groups,DC=derby,DC=barmbuzz,DC=corp"
            Ensure           = 'Present'
            MembersToInclude = $group.Members
            Credential       = $ChildDomainCredential
            DependsOn        = @(
                '[ADOrganizationalUnit]OU_DER_BusinessRoles',
                '[ADUser]DER_User_jeff.driver',
                '[ADUser]DER_User_sarah.operative',
                '[ADUser]DER_User_admin.derby',
                '[ADUser]DER_User_jim.manager'

                # ADD NEW USERS HERE ^^^
            )
        }
    }

    # --- Permission Groups
    foreach ($group in $Node.PermissionGroups) {
        ADGroup "DER_PERM_GROUP_$($group.Name)" {
            GroupName        = $group.Name
            GroupScope       = 'DomainLocal'
            Category         = 'Security'
            Path             = "OU=DER_PermissionGroups,OU=DER_Groups,DC=derby,DC=barmbuzz,DC=corp"
            Ensure           = 'Present'
            MembersToInclude = $group.Members
            Credential       = $ChildDomainCredential
            DependsOn        = @(
                '[ADOrganizationalUnit]OU_DER_PermissionGroups',
                '[ADGroup]DER_ROLE_G_DER_Bus_Drivers',
                '[ADGroup]DER_ROLE_G_DER_Operatives',
                '[ADGroup]DER_ROLE_G_DER_Managers',
                '[ADGroup]DER_ROLE_G_DER_Admins'
            )

            # ADD NEW GROUPS HERE ^^^
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
        MinPasswordAge              = 0
        Credential                  = $ChildDomainCredential
        DependsOn                   = '[ADDomain]CreateChildDomain'
    }

    ADFineGrainedPasswordPolicy StrongerAdminPasswordPolicy{
        Name                        = 'DER_Stronger_Admin_Password_Policy'
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
            'G_DER_Admins'
            )
        Credential                  = $ChildDomainCredential
        DependsOn                   = @(
            '[ADDomain]CreateChildDomain',
            '[ADGroup]DER_ROLE_G_DER_Admins',
            '[ADUser]DER_User_admin.derby'


            # ADD ADMINS HERE^
        )
    }
    # GPO Idle Time - Derby
    Script GPO_DER_IdleTimeout {
        GetScript = {
            $gpo = Get-GPO -Name 'DER_IdleTimedout' -ErrorAction SilentlyContinue
            return @{ Result = if ($gpo) { 'Present' } else { 'Absent' } }
        }
        TestScript = {
            $gpo = Get-GPO -Name 'DER_IdleTimedout' -ErrorAction SilentlyContinue
            return ($null -ne $gpo)
        }
        SetScript = {
            New-GPO -Name 'DER_IdleTimedout'

            Set-GPRegistryValue -Name 'DER_IdleTimedout' `
                -Key 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop' `
                -ValueName 'ScreenSaveTimeOut' `
                -Type String -Value '300'

            Set-GPRegistryValue -Name 'DER_IdleTimedout' `
                -Key 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop' `
                -ValueName 'ScreenSaveActive' `
                -Type String -Value '1'

            New-GPLink -Name 'DER_IdleTimedout' `
                -Target 'OU=DER_Staff,OU=DER_Users,DC=derby,DC=barmbuzz,DC=corp' `
                -Domain 'derby.barmbuzz.corp' `
                -LinkEnabled Yes
                
        }
        DependsOn = '[ADDomain]CreateChildDomain'
        PsDscRunAsCredential = $ChildDomainCredential
    }




    # =========================
    # RBAC — SHARED FOLDERS
    # =========================

    Script DER_Routes_Folder {
        GetScript = {
            return @{ Result = if (Test-Path 'C:\Shares\Routes') { 'Present' } else { 'Absent' } }
        }
        TestScript = {
            return (Test-Path 'C:\Shares\Routes')
        }
        SetScript = {
            # Create folder
            New-Item -Path 'C:\Shares\Routes' -ItemType Directory -Force

            # Create share
            New-SmbShare -Name 'Routes' -Path 'C:\Shares\Routes' -FullAccess 'Everyone'

            # Strip inherited permissions and apply group-based NTFS ACLs
            $acl = Get-Acl 'C:\Shares\Routes'
            $acl.SetAccessRuleProtection($true, $false)

            $read   = New-Object System.Security.AccessControl.FileSystemAccessRule(
                'DERBY\PG_DER_Read_Routes', 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $modify = New-Object System.Security.AccessControl.FileSystemAccessRule(
                'DERBY\PG_DER_Modify_Routes', 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')

            $acl.AddAccessRule($read)
            $acl.AddAccessRule($modify)
            Set-Acl 'C:\Shares\Routes' $acl
        }
        DependsOn = @(
            '[ADGroup]DER_PERM_GROUP_PG_DER_Read_Routes',
            '[ADGroup]DER_PERM_GROUP_PG_DER_Modify_Routes'
        )
        PsDscRunAsCredential = $ChildDomainCredential
    }

    Script DER_Recipes_Folder {
        GetScript = {
            return @{ Result = if (Test-Path 'C:\Shares\Recipes') { 'Present' } else { 'Absent' } }
        }
        TestScript = {
            return (Test-Path 'C:\Shares\Recipes')
        }
        SetScript = {
            New-Item -Path 'C:\Shares\Recipes' -ItemType Directory -Force

            New-SmbShare -Name 'Recipes' -Path 'C:\Shares\Recipes' -FullAccess 'Everyone'

            $acl = Get-Acl 'C:\Shares\Recipes'
            $acl.SetAccessRuleProtection($true, $false)

            $read  = New-Object System.Security.AccessControl.FileSystemAccessRule(
                'DERBY\PG_DER_Recipe_Access', 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')

            $acl.AddAccessRule($read)
            Set-Acl 'C:\Shares\Recipes' $acl
        }
        DependsOn = @(
            '[ADGroup]DER_PERM_GROUP_PG_DER_Recipe_Access'
        )
        PsDscRunAsCredential = $ChildDomainCredential
    }


    }
}

        