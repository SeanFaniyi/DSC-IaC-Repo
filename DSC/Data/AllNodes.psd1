@{
    AllNodes = @(
        @{
            NodeName   = 'localhost'
            Role       = 'RootDC'

            # --- Identity ---
            ComputerName = 'BB-DC01'
            DomainName   = 'barmbuzz.corp'

            # --- Time ---
            TimeZone = 'GMT Standard Time'
            EnsureW32TimeService = $true

            # --- Network ---
            Network = @{
                InterfaceAlias = 'Ethernet'
                IPAddress      = '192.168.10.10/24'  
                DefaultGateway = '192.168.10.10'
                DNSServers      = @('127.0.0.1')
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