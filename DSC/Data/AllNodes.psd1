@{
    AllNodes = @(
        @{
            NodeName   = 'localhost'
            Role       = 'RootDC'

            # --- Identity ---
            ComputerName = 'BB-DC01'
            DomainName   = 'barmbuzz.corp'

            # --- AD Settings ---
            DomainNetbiosName = 'BARMBUZZ'
            ForestMode = 'WinThreshold'
            DomainMode = 'WinThreshold'
            

            # --- Time ---
            TimeZone = 'GMT Standard Time'
            EnsureW32TimeService = $true

            # --- Network ---
            InternalNetwork = @{
                InterfaceAlias = 'Ethernet 2'
                IPAddress      = '192.168.10.10/24'
                DefaultGateway = '192.168.10.1'
                DNSServers     = @('127.0.0.1')
                NetworkCategory = 'Private'
            }

            ExternalNetwork = @{
                InterfaceAlias = 'Ethernet' 
                NetworkCategory = 'Private'
            }
            
            # --- Services ---
            InstallADDSRole = $true
            WinRMService = $true
            WindowsFeatures = @(
                'DNS',
                'RSAT-AD-Tools'
            )
        }
    )
}