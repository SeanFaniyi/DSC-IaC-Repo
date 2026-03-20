<#
========================================================================================
COM5411 Enterprise Operating Systems – BarmBuzz
Run_BuildMain.ps1  (STUDENT REPO – Canonical Orchestrator)

YOU RUN ONE COMMAND:
    .\Run_BuildMain.ps1

YOU EDIT ONLY TWO FILES:
    1) DSC\Configurations\StudentConfig.ps1
    2) DSC\Data\AllNodes.psd1

EVERYTHING ELSE IS TUTOR-PROVIDED OR EVIDENCE OUTPUT.

This orchestrator uses repo-rooted relative paths via $PSScriptRoot, runs in PowerShell 7
as Administrator, stages evidence automatically, and calls OneShot prereqs early.
========================================================================================
#>

[CmdletBinding()]
param(
    [switch]$Pause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# WHY StrictMode + Stop-On-Error?
# - StrictMode catches beginner mistakes like using unset variables.
# - Stop-On-Error prevents confusing cascades of failures.
#   In industry, pipelines should fail fast with clear signals, not limp onward.

# Repo root is where this script lives.
$RootPath = $PSScriptRoot

# INDUSTRY PRACTICE: Always use repo-relative paths
# - $PSScriptRoot ensures this script runs correctly regardless of the current directory.
# - Students must NOT hardcode absolute paths; portability and repeatability matter.

# Paths
$StudentConfigScript = Join-Path $RootPath "DSC\Configurations\StudentConfig.ps1"  # Your configuration (what to build)
$StudentDataFile     = Join-Path $RootPath "DSC\Data\AllNodes.psd1"                 # Your data (values for the build)
$OutputsRoot         = Join-Path $RootPath "DSC\Outputs"                             # Compiled MOFs (tracked in Git)
$EvidenceRoot        = Join-Path $RootPath "Evidence"                                 # Logs & transcripts (tracked in Git)
$ConfigName          = "StudentBaseline"                                              # REQUIRED configuration name

# OneShots (direct paths) and helper wrapper
$PrereqLcmScript     = Join-Path $RootPath "Scripts\Prereqs\BarmBuzz_OneShot_LCM.ps1"      # Configures LCM, pins DSC modules
$PrereqNetworkScript = Join-Path $RootPath "Scripts\Prereqs\BarmBuzz_OneShot_Network.ps1"  # Sets NICs Private, enables WinRM, installs RSAT
$OneShotsHelperPath  = Join-Path $RootPath "Scripts\Helpers\Invoke-BarmBuzz-OneShots.ps1"  # Thin wrapper to run both in order

# Flag files for idempotency
$LcmFlagFile     = Join-Path $EvidenceRoot "prereq_lcm_complete.flag"     # Idempotency: run-once marker
$NetworkFlagFile = Join-Path $EvidenceRoot "prereq_network_complete.flag" # Idempotency: run-once marker

function New-FolderIfMissing {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

# WHY create folders up-front?
# - Deterministic structure keeps evidence and outputs consistent across builds.
# - Git-tracked evidence supports academic integrity and professional audit trails.

function Assert-Admin {
    $principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "You must run PowerShell as Administrator."
    }
}

# WHY Admin?
# - DSC application, WinRM configuration, and later AD-related tasks require elevation.
# - Industry pipelines document prerequisites; this script enforces them early.

function Assert-AllNodesData {
    param([Parameter(Mandatory)]$ConfigData)
    if (-not ($ConfigData -is [hashtable])) { throw "AllNodes.psd1 must return a hashtable." }
    if (-not $ConfigData.ContainsKey("AllNodes")) { throw "AllNodes.psd1 must contain the key 'AllNodes'." }
    if (-not ($ConfigData.AllNodes -is [System.Array])) { throw "AllNodes must be an array." }
    $local = $ConfigData.AllNodes | Where-Object { $_.NodeName -eq "localhost" } | Select-Object -First 1
    if (-not $local) { throw "AllNodes must include NodeName = 'localhost' for this lab VM build." }
}

# CONTRACT: ConfigurationData must target 'localhost' initially
# - Start local, prove the pipeline, then expand to remote nodes later.

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "        COM5411 BarmBuzz Build Runner      " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "[*] Repo root: $RootPath" -ForegroundColor Gray
Write-Host "[*] PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host "[*] You edit ONLY: DSC\\Configurations\\StudentConfig.ps1 and DSC\\Data\\AllNodes.psd1" -ForegroundColor Gray

# Evidence folders
New-FolderIfMissing -Path $OutputsRoot
New-FolderIfMissing -Path $EvidenceRoot
New-FolderIfMissing -Path (Join-Path $EvidenceRoot "Transcripts")
New-FolderIfMissing -Path (Join-Path $EvidenceRoot "DSC")
New-FolderIfMissing -Path (Join-Path $EvidenceRoot "Network")
New-FolderIfMissing -Path (Join-Path $EvidenceRoot "AI_LOG")
New-FolderIfMissing -Path (Join-Path $EvidenceRoot "Git\Reflog")

# EVIDENCE POLICY
# - These folders are tracked in Git to prove your work.
# - Transcripts and logs are essential in both academia and industry for traceability.

# Start transcript
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$TranscriptPath = Join-Path $EvidenceRoot ("Transcripts\{0}_Run_BuildMain.txt" -f $RunStamp)
Start-Transcript -Path $TranscriptPath -Force | Out-Null
Write-Host "[+] Transcript started: Evidence\\Transcripts\\$(Split-Path -Leaf $TranscriptPath)" -ForegroundColor Green

# Start-Transcript captures all console activity into Evidence\Transcripts.
# - Read it to understand exactly what ran and when.
# - If something fails, the transcript is your first diagnostic artefact.

try {
    Assert-Admin
    Write-Host "[+] Admin privileges confirmed." -ForegroundColor Green

    # Required inputs present
    if (-not (Test-Path $StudentConfigScript)) { throw "Missing: DSC\\Configurations\\StudentConfig.ps1" }
    if (-not (Test-Path $StudentDataFile))     { throw "Missing: DSC\\Data\\AllNodes.psd1" }
    if (-not (Test-Path $PrereqLcmScript))     { throw "Missing: Scripts\\Prereqs\\BarmBuzz_OneShot_LCM.ps1" }
    if (-not (Test-Path $PrereqNetworkScript)) { throw "Missing: Scripts\\Prereqs\\BarmBuzz_OneShot_Network.ps1" }

    Write-Host "`n[Phase 1] Prerequisites..." -ForegroundColor Yellow

    # Phase 1 is deliberately early: fix environment before compiling/applying.
    # - LCM settings (reboot/resume, ApplyOnly) enable robust automation.
    # - Network baseline (NICs Private, WinRM) prevents WS-Man failures.
    # - RSAT installation ensures AD/GPO cmdlets exist where DSC modules expect them.

    # If helper exists, use it; else call scripts directly
    if (Test-Path $OneShotsHelperPath) {
        . $OneShotsHelperPath
        if (Get-Command Invoke-BarmBuzz-OneShots -ErrorAction SilentlyContinue) {
            Invoke-BarmBuzz-OneShots -RootPath $RootPath -LcmFlagFile $LcmFlagFile -NetworkFlagFile $NetworkFlagFile
        } else {
            Write-Host "[*] Helper not loaded; falling back to direct OneShots." -ForegroundColor Gray
        }
    }

    # Fallback direct calls with idempotent flags

    if (-not (Test-Path $LcmFlagFile)) {
        & $PrereqLcmScript
        New-Item -Path $LcmFlagFile -ItemType File -Force | Out-Null
        Write-Host "[+] LCM configured and flagged." -ForegroundColor Green
    } else {
        Write-Host "[*] LCM already configured (skipping)." -ForegroundColor Gray
    }

    if (-not (Test-Path $NetworkFlagFile)) {
        & $PrereqNetworkScript
        New-Item -Path $NetworkFlagFile -ItemType File -Force | Out-Null
        Write-Host "[+] Network configured and flagged." -ForegroundColor Green
    } else {
        Write-Host "[*] Network already configured (skipping)." -ForegroundColor Gray
    }

    Write-Host "[+] Phase 1 complete." -ForegroundColor Green

    # ═══════════════════════════════════════════════════════════════════════════
    # CREDENTIALS — HARDCODED FOR LAB TEACHING ONLY
    # ═══════════════════════════════════════════════════════════════════════════
    #
    # ╔══════════════════════════════════════════════════════════════════════╗
    # ║  WARNING: THIS IS PROFESSIONALLY IRRESPONSIBLE                     ║
    # ║                                                                    ║
    # ║  We are hardcoding passwords in a script that is committed to Git. ║
    # ║  In any real environment, this would be a sackable offence.        ║
    # ║                                                                    ║
    # ║  We do it here ONLY because:                                       ║
    # ║    1. This is a disposable teaching lab (VMs rebuilt every week)    ║
    # ║    2. The passwords are already published in the project README    ║
    # ║    3. Removing the interactive prompts lets students focus on DSC   ║
    # ║       rather than typing passwords three times per build cycle     ║
    # ║    4. The repo is private and never leaves the lab network         ║
    # ║                                                                    ║
    # ║  IN PRODUCTION YOU WOULD:                                          ║
    # ║    • Prompt at runtime (Read-Host -AsSecureString)                 ║
    # ║    • Pull from Azure KeyVault / AWS Secrets Manager / HashiCorp    ║
    # ║    • Use certificate-encrypted MOF files (CertificateFile in data) ║
    # ║    • NEVER store credentials in source control. Ever.              ║
    # ║                                                                    ║
    # ║  If you put passwords in a repo in industry, you WILL be fired.    ║
    # ║  GitHub scans for leaked credentials automatically.                ║
    # ║  The Uber engineer incident (2021) cost $100K+ and a career.       ║
    # ╚══════════════════════════════════════════════════════════════════════╝
    #
    # THREE CREDENTIALS:
    # 1. DomainAdminCredential — local Administrator → becomes Domain Admin after promotion
    # 2. DsrmCredential — Directory Services Restore Mode (DC emergency recovery)
    # 3. UserCredential — default password for end-user accounts (ADUser resources)
    #
    # Lab passwords (from Documentation\README.md):
    #   Administrator = superw1n_user
    #   End-users     = notlob2k26
    #
    # ═══════════════════════════════════════════════════════════════════════════

    # --- LAB-ONLY HARDCODED CREDENTIALS (current) ---
    $AdminPlainText = 'superw1n_user'
    $UserPlainText  = 'notlob2k26'

    $DomainAdminCredential = New-Object System.Management.Automation.PSCredential(
        'Administrator',
        (ConvertTo-SecureString $AdminPlainText -AsPlainText -Force)
    )
    $DsrmCredential = New-Object System.Management.Automation.PSCredential(
        'Administrator',
        (ConvertTo-SecureString $AdminPlainText -AsPlainText -Force)
    )
    $UserCredential = New-Object System.Management.Automation.PSCredential(
        'LabUser',
        (ConvertTo-SecureString $UserPlainText -AsPlainText -Force)
    )
    Write-Host "[+] Credentials loaded (hardcoded lab mode *** see warning in comments above ***)." -ForegroundColor Yellow

    # --- PRODUCTION ALTERNATIVE (uncomment to replace hardcoded block above) ---
    # Write-Host "`n[Credential] Domain Administrator Password Required..." -ForegroundColor Yellow
    # $AdminPassword = Read-Host -Prompt "Enter local Administrator password" -AsSecureString
    # $DomainAdminCredential = New-Object System.Management.Automation.PSCredential(
    #     "Administrator", $AdminPassword
    # )
    # Write-Host "[+] Domain Admin credential captured (not logged)." -ForegroundColor Green
    #
    # Write-Host "`n[Credential] DSRM Password Required..." -ForegroundColor Yellow
    # $DsrmPassword = Read-Host -Prompt "Enter DSRM password" -AsSecureString
    # $DsrmCredential = New-Object System.Management.Automation.PSCredential(
    #     "Administrator", $DsrmPassword
    # )
    # Write-Host "[+] DSRM credential captured (not logged)." -ForegroundColor Green
    #
    # Write-Host "`n[Credential] End-User Default Password Required..." -ForegroundColor Yellow
    # $UserPassword = Read-Host -Prompt "Enter end-user default password" -AsSecureString
    # $UserCredential = New-Object System.Management.Automation.PSCredential(
    #     "LabUser", $UserPassword
    # )
    # Write-Host "[+] User credential captured (not logged)." -ForegroundColor Green

    Write-Host "`n[Phase 2] Compile + Apply DSC..." -ForegroundColor Yellow

    # SEPARATION OF CONCERNS
    # - Data (AllNodes.psd1) describes the environment.
    # - Configuration (StudentConfig.ps1) implements resources using that data.
    # - Credentials flow through the orchestrator, not config files.

    $ConfigData = Import-PowerShellDataFile -Path $StudentDataFile
    Assert-AllNodesData -ConfigData $ConfigData

    $CompileOut = Join-Path $OutputsRoot $ConfigName
    New-FolderIfMissing -Path $CompileOut
    Write-Host "[*] Compiling -> DSC\\Outputs\\$ConfigName" -ForegroundColor Gray

    # ═══════════════════════════════════════════════════════════════════════════
    # WHY PS5.1 FOR COMPILATION?
    # ═══════════════════════════════════════════════════════════════════════════
    #
    # GroupPolicyDsc uses CLASS-BASED DSC resources (DSCClassResources/).
    # Class-based resources only load in Windows PowerShell 5.1 — PS7 cannot
    # parse them and throws "The term 'GroupPolicy' is not recognized".
    #
    # So: this orchestrator runs in PS7 (for modern language features, better
    # error handling, transcript support), but shells out to powershell.exe
    # (PS5.1) purely for the MOF compilation step.
    #
    # Start-DscConfiguration (the APPLY step) works fine from PS7 because it
    # delegates to the WMI/CIM DSC engine which is always PS5.1 under the hood.
    #
    # The temp script is written to disk, executed by PS5.1, then deleted.
    # Passwords appear in the temp file briefly — acceptable for a lab VM,
    # unacceptable in production (use certificate-encrypted MOFs instead).
    # ═══════════════════════════════════════════════════════════════════════════

    $TempCompileScript = Join-Path $env:TEMP "BarmBuzz_Compile_$RunStamp.ps1"
    @"
# Auto-generated compile script — executed by Windows PowerShell 5.1
# This file is deleted immediately after compilation.
`$env:PSModulePath = "`$PSHOME\Modules;C:\Program Files\WindowsPowerShell\Modules"

. '$StudentConfigScript'
`$ConfigData = Import-PowerShellDataFile -Path '$StudentDataFile'

`$adminCred = New-Object PSCredential('Administrator',
    (ConvertTo-SecureString '$AdminPlainText' -AsPlainText -Force))
`$dsrmCred  = New-Object PSCredential('Administrator',
    (ConvertTo-SecureString '$AdminPlainText' -AsPlainText -Force))
`$userCred  = New-Object PSCredential('LabUser',
    (ConvertTo-SecureString '$UserPlainText' -AsPlainText -Force))

StudentBaseline ``
    -ConfigurationData `$ConfigData ``
    -DomainAdminCredential `$adminCred ``
    -DsrmCredential `$dsrmCred ``
    -UserCredential `$userCred ``
    -OutputPath '$CompileOut'
"@ | Set-Content -Path $TempCompileScript -Encoding UTF8

    Write-Host "[*] Compiling via Windows PowerShell 5.1 (GroupPolicyDsc requires it)..." -ForegroundColor Gray
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TempCompileScript

    if ($LASTEXITCODE -ne 0) {
        Remove-Item $TempCompileScript -Force -ErrorAction SilentlyContinue
        throw "MOF compilation failed in PS5.1 (exit code $LASTEXITCODE). Check StudentConfig.ps1 and AllNodes.psd1."
    }
    Remove-Item $TempCompileScript -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Compilation complete." -ForegroundColor Green

    # RESULT: MOF files in DSC\Outputs\StudentBaseline (e.g., localhost.mof, BB-WIN11-01.mof)
    # Inspect MOFs to understand the resources and properties generated.

    Get-ChildItem -Path $CompileOut -Recurse |
        Select-Object FullName, Length, LastWriteTime |
        Out-File (Join-Path $EvidenceRoot ("DSC\{0}_compiled_files.txt" -f $RunStamp)) -Encoding UTF8

    Write-Host "[*] Applying configuration (waits until complete)..." -ForegroundColor Gray
    Start-DscConfiguration -Path $CompileOut -Wait -Force -Verbose 4>&1 |
        Tee-Object -FilePath (Join-Path $EvidenceRoot ("DSC\{0}_apply_verbose.txt" -f $RunStamp))
    Write-Host "[+] Apply complete." -ForegroundColor Green

    # NOTE: '4>&1' redirects verbose stream to success stream so Tee-Object captures it.
    # Read Evidence\DSC\*_apply_verbose.txt to learn what DSC did step-by-step.

    ipconfig /all | Out-File (Join-Path $EvidenceRoot ("Network\{0}_ipconfig.txt" -f $RunStamp)) -Encoding UTF8
    w32tm /query /status 2>&1 | Out-File (Join-Path $EvidenceRoot ("Network\{0}_w32tm_status.txt" -f $RunStamp)) -Encoding UTF8

    # NETWORK/TIME EVIDENCE: Most lab issues are due to networking or clock skew.
    # Keep these snapshots for troubleshooting and marking support.

    Write-Host "`n[Phase 3] Validation..." -ForegroundColor Yellow
    Write-Host "[*] Pester validation will be added later." -ForegroundColor Gray

    # Once validation tests are provided, run them and tee outputs to Evidence\Pester.

    Write-Host "`n[+] BUILD SUCCESS" -ForegroundColor Green
    Write-Host "[*] Next steps (commit outputs + evidence):" -ForegroundColor Gray
    Write-Host "    git add DSC\Outputs Evidence" -ForegroundColor Gray
    Write-Host "    git commit -m \"Build $RunStamp\"" -ForegroundColor Gray

    # GIT DISCIPLINE: In professional settings, evidence and build artefacts are committed.
    # This protects you against accusations and supports reproducibility.
}
catch {
    Write-Host "`n[-] BUILD FAILED" -ForegroundColor Red
    Write-Host ("Message: {0}" -f $_.Exception.Message) -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    if ($Pause) { Read-Host -Prompt "Press Enter to exit" | Out-Null }
}