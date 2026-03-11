@{
    AllNodes = @(
        @{
            NodeName   = 'localhost'
            Role       = 'RootDC'

            # --- Identity ---
            ComputerName = 'BB-BOL-DC01'
            DomainName   = 'barmbuzz.corp'

            # --- AD Settings ---
            DomainNetBiosName = 'BARMBUZZ'
            ForestMode = 'WinThreshold'
            DomainMode = 'WinThreshold'
            

            # --- Time ---
            TimeZone = 'GMT Standard Time'
            EnsureW32TimeService = $true

            # --- Network ---
            InternalNetwork = @{
                InterfaceAlias = 'Ethernet 2'
                IPAddress      = '192.168.10.10/24'
                DefaultGateway = $null
                DNSServers     = @('127.0.0.1')
                NetworkCategory = 'Private'
            }

            ExternalNetwork = @{
                InterfaceAlias = 'Ethernet' 
                NetworkCategory = 'Private'
                DisableDNSRegistrationOnNAT = $true

            }
            
            # --- Services ---
            InstallADDSRole = $true
            WinRMService = $true
            WindowsFeatures = @(
                'DNS',
                'RSAT-AD-Tools',
                'RSAT-ADDS'
            )

            # --- Security ---
            PSDscAllowPlainTextPassword = $true           
            AllowDomainUser = $true

            # --- OU's ---
            OrganizationalUnits = @(
                'BOL_Servers',
                'BOL_Workstations',
                'BOL_Users',
                'BOL_Admin_Groups'
            )

            # --- Users ---
            Users = @(
                @{
                    UserName = 'admin.enterprise'
                    GivenName = 'Enterprise'
                    Surname = 'Admin'
                    OU = 'BOL_Users'
                }
                @{
                    UserName = 'admin.schema'
                    GivenName = 'Schema'
                    Surname = 'Admin'
                    OU = 'BOL_Users'
                },
                @{
                    UserName = 'admin.domain'
                    GivenName = 'Domain'
                    Surname = 'Admin'
                    OU = 'BOL_Users'
                },
                @{
                    UserName = 'john.test'
                    GivenName = 'John'
                    Surname = 'Test'
                    OU = 'BOL_Users'
                },
                @{
                    UserName = 'amber.test'
                    GivenName = 'Amber'
                    Surname = 'Test'
                    OU = 'BOL_Users'
                }
            )
                        # --- Admin Groups---
            AdminGroups = @(
                @{
                    Name = 'G_Enterprise_Admins'
                    Members = @('admin.enterprise')
                },
                @{
                    Name = 'G_Schema_Admins'
                    Members = @('admin.schema')
                },
                @{
                    Name = 'G_Domain_Admins'
                    Members = @('admin.domain')
                },                
                @{
                    Name = 'G_No_Privileges'
                    Members = @('john.test','amber.test')
                }
            )

        },
        @{
            NodeName   = 'BB-DER-DC01'
            Role       = 'ChildDC'
            
            # --- Identity ---
            ComputerName      = 'BB-DER-DC01'
            DomainName        = 'derby.barmbuzz.corp'
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
            AllowDomainUser             = $true
        }
    )
}