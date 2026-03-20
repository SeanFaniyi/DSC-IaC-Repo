BarmBuzz — COM5411 Enterprise Operating Systems
GitHub Repository: https://github.com/SeanFaniyi/DSC-IaC-Repo.git

1. Design Overview
BarmBuzz is designed as a two-domain Active Directory forest:
    • Forest root: barmbuzz.corp on BB-BOL-DC01 — 192.168.10.10 
    • Child domain: derby.barmbuzz.corp on BB-DER-DC01 — 192.168.10.20 
    • OS: Windows Server 2022 Datacenter (both DCs), Ubuntu 24.04 LTS (client) 

DSC v3 is used as the primary control plain. All infrastructure including OU’s, users and password policies are written as code and applied through the orchestrator script: Run_BuildMain.ps1.

2. Architectural Scope and Boundaries
Derby is implemented as seperate child domain rather than an OU to provide a true Kerberos and administrative boundary between sites. Derby can enforce its own password policies, manage its own identity objects including staff, and operate semi-autonomously without requiring elevated Bolton permissions. This mirrors the brief's requirement for a "semi-autonomous regional division." 
Derby OUs: DER_Users, DER_Staff, DER_Admins, DER_Groups, DER_BusinessRoles, DER_PermissionGroups, DER_Nottingham.
Role Based Access Control (RBAC) ensures that authorization happens at a role level, rather than permissions being granted individually. For example, role group ‘G_DER_Bus_Drivers’ have local domain permissions ‘PG_DER_Read_Routes’ attached enabling staff with that role to access a file share directory. 

3. Automation Strategy
DSC was chosen over imperative scripting or clickops because it is declarative and idempotent meaning it can be re-ran indefinitely and only change what has drifted from the configured design. BarmBuzz is built in DSC layers: 
    1. Network (IP, DNS, firewall profiles) 
    2. DC promotion (forest root or child domain) 
    3. OU structure → Password policies → Users and groups → GPOs → RBAC shares 
Configuration data (node names, IPs, users, groups) lives in AllNodes.psd1. Logic lives in StudentConfig.ps1. 

4. Repository Structure
DSC-IaC-Repo/
├── Run_BuildMain.ps1             			 # Single entry point
├── README.md                     			 # This document
├── DSC/
│   ├── Configurations/StudentConfig.ps1  	 # Student DSC logic
│   ├── Data/AllNodes.psd1                		 # Student config data
│   └── Outputs/StudentBaseline/         		  # Compiled MOFs (generated)
├── Tests/Pester/                			  # Pester validation tests
├── Evidence/
│   ├── Transcripts/         			  # Build run transcripts
│   ├── HealthChecks/       			   # dcdiag + gpresult outputs
│   ├── Screenshots/              			 # RBAC, ADUC, GPO evidence
│   ├── Git/                       			# GitLog, Stats, RepoLink, reflog
└── Documentation/README.docx     		# Turnitin copy
					

5. Execution Order
This set up requires a minimum of 2 VMs for each domain controller, each requires two NICs — one internal isolated (for domain traffic) and one external (NAT). The following must be installed before running the build:
    • Git (to clone the repository) 
    • VirtIO guest tools (QoL) 
    • PowerShell 7 — all commands must be run as Administrator 
    • Required RSAT modules:
Step 1:	Clone the repository. Install modules
 	git clone https://github.com/SeanFaniyi/DSC-IaC-Repo.git
	Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-ADDS, 
	GPMC-IncludeManagementTools
	cd C:\DSC-IaC-Repo
Step 2: Create Bolton DC first
	Comment or delete all blocks inside All_Nodes that are not the intended configuration. Only 	one ‘localhost’ block should remain.
	.\Run_BuildMain.ps1
	The PC will restart during this process. Re-run the orchestrator until there are no more 	restarts.

Step 3: Verify the health of the DC
	dcdiag /v > Evidence\HealthChecks\dcdiag_bolton.txt
	gpresult /H Evidence\HealthChecks\gpresult_bolton.html /F

Step 4: Create the Derby DC second.
	Repeat steps 2 and 3 for the alternative VM.

6. Idempotence and Re-run Behaviour
Running the orchestrator again after already configuring itself will make the DSC evaluate each resource, checking for drifts in configuration and it will make no changes should it match the desired state. 
Known constraints: Derby cannot be built before Bolton. AD objects depend on DC promotion. The FGPP depends on G_DER_Admins existing before the password settings are applied.

7. Validation and Testing Model
A figure showing the methods of validation used:
Claim	Evidence
DC healthy	dcdiag_bolton.txt, dcdiag_derby.txt
GPOs applied	gpresult_bolton.html, gpresult_derby.html
OU / users / groups	Screenshots in Evidence\Screenshots\
RBAC enforced	Share ACL screenshots
FGPP on admin group	Get-ADFineGrainedPasswordPolicySubject output
Pester results	Evidence\Pester\


8. Security Considerations
GPO: BOL_IdleTimedout / DER_IdleTimedout
    • Risk: Unattended authenticated sessions expose credentials to unauthorised access. 
    • Control: 5-minute screen saver timeout forces session lock. 
    • Scope: BOL_Users OU (Bolton) and DER_Staff OU (Derby) only.

Fine-Grained Password Policy (FGPP)
    • Risk: Weak admin credentials are a common attack vector. 
    • Control: BOL/DER_Stronger_Admin_Password_Policy enforces 12-character minimum and 5-attempt lockout to G_BOL/DER_Admins  
    • Scope: Standard staff use the relaxed default domain policy, appropriate for a training environment. 
      
Credentials are passed as PSCredential objects at runtime by the orchestrator — never hardcoded in student files. PSDscAllowPlainTextPassword = $true is set for demonstration purposes only and is generally considered not secure. “The Azure Automation DSC service allows you to centrally manage credentials to be compiled in configurations and stored securely (Microsoft, 2023)”.

9. Ubuntu Integration – Client
sudo apt install realmd sssd sssd-tools adcli libnss-sss libpam-sss samba-common-bin -y
sudo adcli join derby.barmbuzz.corp --user=Administrator --domain-controller=192.168.10.20
Unfortuately, I was unable to get this to fully connect due to LDAP conflicts, however, Kerberos had successfully authenticated both admin.derby and jeff.driver on the linux device, evidenced in the screenshots. 

10. Reflections
Honest self-grade: The pipeline is reproducible, the two-domain topology is correctly built, RBAC and FGPP are evidenced, and GPOs are correctly scoped. Ubuntu has been attempted, but it couldn’t fully connect to the DCs. Adding more users to the site requires multiple fields to be adjusted, and this may have been optimised. Therefore, I would place this around 60%.

References
    • Francis, D. (2021). Mastering Active Directory. Packt Publishing Ltd.
    • Ihouele Caurcy (2025). Mastering Organizational Units (OUs) in Windows Server: Structure, Strategy & Best Practices. [online] Medium. Available at: https://medium.com/@ihouelecaurcy/mastering-organizational-units-ous-in-windows-server-structure-strategy-best-practices-94bd74f4a22c.
    • Microsoft (2023) Securing DSC credentials. Available at: https://docs.microsoft.com/en-us/powershell/dsc/configurations/configDataCredentials
    • Montérémal, J. (2024). FGPP: definition and implementation of a refined password policy. [online] Appvizer. Available at: https://www.appvizer.co.uk/magazine/it/computer-security/fgpp .
      

AI Declaration
ChatGPT was used for the following purposes:
	- Syntax debugging assistance
	 - README Report structure
 	- Naming conventions
Microsoft’s ‘Ask Learn’ AI assistant used whilst navigating powershell documentation.