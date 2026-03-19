@{
    AllNodes = @(
        @{  

            
            NodeName   = 'localhost'
            Role       = 'ChildDC'
            
            # --- Identity ---
            ComputerName      = 'BB-DER-DC01'
            DomainName        = 'derby.barmbuzz.corp'
            DomainController  = 'BB-DER-DC01.derby.barmbuzz.corp'
            ChildDomainName   = 'derby'
            DomainNetBiosName = 'DERBY'
            ParentDomainName  = 'barmbuzz.corp'
            ForestMode        = 'WinThreshold'
            DomainMode        = 'WinThreshold'

            # --- Time ---
            TimeZone             = 'GMT Standard Time'
            EnsureW32TimeService = $true

            # --- Network ---
            InternalNetwork = @{
                InterfaceAlias  = 'Ethernet 2'
                IPAddress       = '192.168.10.20/24'
                DefaultGateway  = $null
                DNSServers      = @('192.168.10.10')
                NetworkCategory = 'Private'
            }
            ExternalNetwork = @{
                InterfaceAlias  = 'Ethernet'
                NetworkCategory = 'Private'
                DisableDNSRegistrationOnNAT = $true
            }

            # --- Services ---
            InstallADDSRole = $true
            WinRMService    = $true
            WindowsFeatures = @(
                'DNS',
                'RSAT-AD-Tools',
                'RSAT-ADDS'
            )

            # --- Security ---
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser        = $true
       
       
            # --- OU's ---
            OrganizationalUnits = @(
                @{ Name = 'DER_Users';            Path = 'DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_Staff';            Path = 'OU=DER_Users,DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_Admins';           Path = 'OU=DER_Users,DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_Computers';        Path = 'DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_Workstations';     Path = 'OU=DER_Computers,DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_Servers';          Path = 'OU=DER_Computers,DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_Groups';           Path = 'DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_BusinessRoles';    Path = 'OU=DER_Groups,DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_PermissionGroups'; Path = 'OU=DER_Groups,DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_AdminTiers';       Path = 'OU=DER_Groups,DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_Nottingham';       Path = 'DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_NottinghamUsers';  Path = 'OU=DER_Nottingham,DC=derby,DC=barmbuzz,DC=corp' }
                @{ Name = 'DER_NottinghamComputers';   Path = 'OU=DER_Nottingham,DC=derby,DC=barmbuzz,DC=corp' }
            )
            
                        # --- Users ---
            Users = @(
                # Staff users 
                @{
                    UserName  = 'jeff.driver'
                    GivenName = 'Jeff'
                    Surname   = 'Staff'
                    OU        = 'DER_Staff'
                },
                @{
                    UserName  = 'sarah.operative'
                    GivenName = 'Sarah'
                    Surname   = 'Operative'
                    OU        = 'DER_Staff'
                },
                # Admin
                @{
                    UserName  = 'admin.derby'
                    GivenName = 'Derby'
                    Surname   = 'Admin'
                    OU        = 'DER_Admins'
                },
                @{
                    UserName  = 'jim.manager'
                    GivenName = 'Jim'
                    Surname   = 'Manager'
                    OU        = 'DER_Staff'
                }
            )

            BusinessRoleGroups = @(
                @{
                    Name    = 'G_DER_Bus_Drivers'
                    Members = @('jeff.driver')
                },
                @{
                    Name    = 'G_DER_Operatives'
                    Members = @('sarah.operative')
                },
                @{
                    Name    = 'G_DER_Managers'
                    Members = @('admin.derby','jim.manager')
                },
                @{
                    Name    = 'G_DER_Admins'
                    Members = @('admin.derby')
                }
            )
            
            PermissionGroups = @(
                @{
                    Name    = 'PG_DER_Read_Routes'
                    Members = @('G_DER_Bus_Drivers', 'G_DER_Operatives', 'G_DER_Managers')
                },
                @{
                    Name    = 'PG_DER_Modify_Routes'
                    Members = @('G_DER_Operatives', 'G_DER_Managers','G_DER_Admins')
                },
                @{
                    Name    = 'PG_DER_Printer_Use'
                    Members = @('G_DER_Bus_Drivers', 'G_DER_Operatives', 'G_DER_Managers')
                },
                @{
                    Name    = 'PG_DER_Recipe_Access'
                    Members = @('G_DER_Managers')
                }
            )
        }
    )
}