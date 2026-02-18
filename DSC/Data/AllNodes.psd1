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

            # --- Features ---
            InstallADDSRole     = $true
            InstallRSATADDSRole = $true
            InstallDNSRole      = $true 

            # --- Network ---
            Network = @{
                InterfaceAlias = 'Ethernet'
                IPAddress      = '192.168.10.10'  
                PrefixLength   = 24
                DefaultGateway = '192.168.10.10'
                DNSServer      = '127.0.0.1'
                NetworkCategory = 'Private'       
            }

            
            # --- Services ---
            EnsureWinRM = $true
        }
    )
}