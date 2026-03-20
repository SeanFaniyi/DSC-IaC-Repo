Describe "Derby AD Structure" {
    It "OU DER_Admins exists" {
        $ou = Get-ADOrganizationalUnit -Filter {Name -eq 'DER_Admins'} -Server 'derby.barmbuzz.corp'
        $ou | Should Not BeNullOrEmpty
    }
    It "G_DER_Admins group exists" {
        $group = Get-ADGroup -Identity 'G_DER_Admins' -Server 'derby.barmbuzz.corp'
        $group | Should Not BeNullOrEmpty
    }
    It "DER_Stronger_Admin_Password_Policy exists" {
        $fgpp = Get-ADFineGrainedPasswordPolicy -Identity 'DER_Stronger_Admin_Password_Policy' -Server 'derby.barmbuzz.corp'
        $fgpp | Should Not BeNullOrEmpty
    }
    It "Routes share exists" {
        Test-Path 'C:\Shares\Routes' | Should Be $true
    }
}