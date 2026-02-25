@{
    AllNodes = @(
        @{
            NodeName   = 'localhost'
            Role       = 'RootDC'

            # --- Identity ---
            ComputerName = 'BB-DC01'
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
                'Servers',
                'Workstations',
                'Users',
                'Groups'
            )

            # --- Users ---
            Users = @(
                @{
                    UserName = 'admin.enterprise'
                    GivenName = 'Enterprise'
                    Surname = 'Admin'
                }
                @{
                    UserName = 'admin.schema'
                    GivenName = 'Schema'
                    Surname = 'Admin'
                    OU = 'Users'
                }
                @{
                    UserName = 'admin.schema'
                    GivenName = 'Schema'
                    Surname = 'Admin'
                    OU = 'Users'
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
                }
            )

        }
    )
}