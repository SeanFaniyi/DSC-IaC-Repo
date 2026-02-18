@{
    AllNodes = @(
        @{
            NodeName   = 'localhost'
            Role       = 'DC'
            DomainName = 'barmbuzz.corp'

            ComputerName = 'DC-01'
            TimeZone = 'GMT Standard Time'

            EnsureW32TimeService = $True
            InstallADDSRole = $True
            InstallRSATADDSRole = $True

        }
    )
}
