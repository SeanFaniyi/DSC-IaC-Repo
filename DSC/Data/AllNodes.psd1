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
                'RSAT-AD-Tools'
            )

            # --- Security ---
            PSDscAllowPlainTextPassword = $true           
            AllowDomainUser = $true

        }
    )
}