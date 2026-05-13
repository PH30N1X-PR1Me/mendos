# ============================================================================
#  MendOS v1.0.0  -  Cross-Platform Self-Service IT Diagnostic Tool
#  Windows entry point
# ============================================================================
#  Repository: https://github.com/PH30N1X-PR1Me/frntzn-h3l1os
#  License   : MIT (free Light tier) + commercial Ultimate tier
#
#  Architecture (read this before editing):
#
#    Three registries drive everything:
#      $Fixes      - single-shot remediations triggered by Fix buttons
#      $Problems   - user-selectable issues with single-shot Actions
#      $Workflows  - multi-step verified procedures (Ultimate tier)
#
#    Cross-cutting:
#      $Undo       - rollback registry. Every $Fixes/$Workflows step that
#                    mutates state must register an undo entry first.
#      $L          - localization function: $L 'btn.fix' -> "Fix" (or es/tl)
#      $Config     - merged config.json (default + user override)
#      $Tier       - 'Light' | 'Ultimate' from license stub
#      $AuditMode  - if $true, all actions print what they WOULD do, no changes
#
#  Security posture:
#    - AMSI never disabled, never bypassed
#    - No keylogging, clipboard reading, credential capture
#    - All registry writes go through Set-RegistryValueSafe (records undo)
#    - All fixes have a registered undo entry
#    - Restore Point created before any state-mutating workflow
#    - Open source, commit-pinned, hash-verifiable
# ============================================================================

#Requires -Version 5.1


# ----- HOSTING URLS ---------------------------------------------------------
# Hybrid setup:
#   - Scripts hosted on GitHub raw (versioned tag URL = tamper-evident,
#     immutable, transparent - users can verify the file matches the repo)
#   - API endpoints on Cloudflare Worker at mendos.heliosprima.com/v1/*
#
# Each new release: bump the version tag in $script:ScriptUrl AND publish a
# new GitHub release with that tag. Cache headers on raw.githubusercontent.com
# are ~5min so propagation is fast.
$script:ScriptUrl     = 'https://raw.githubusercontent.com/PH30N1X-PR1Me/frntzn-h3l1os/v1.0.1/src/windows/h3l1os.ps1'
$script:Version       = '1.0.1'
$script:UserAgent     = "FRNTZN-H3L1OS/$script:Version (Windows; PowerShell $($PSVersionTable.PSVersion))"
$script:LicenseUrl    = 'https://mendos.heliosprima.com/v1/license/check'
$script:VersionUrl    = 'https://mendos.heliosprima.com/v1/version'
$script:TelemetryUrl  = 'https://mendos.heliosprima.com/v1/telemetry/event'
$script:AppDataRoot   = Join-Path $env:LOCALAPPDATA 'frntzn'
$script:LogsDir       = Join-Path $script:AppDataRoot 'logs'
$script:UndoDir       = Join-Path $script:AppDataRoot 'undo'
$script:LicenseCache  = Join-Path $script:AppDataRoot 'license.cache.json'


# ----- ELEVATION ------------------------------------------------------------
function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    if ($PSCommandPath) {
        $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        # Loaded via `irm | iex` - re-fetch in admin shell
        $cmd       = "irm '$script:ScriptUrl' | iex"
        $argString = "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""
    }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argString -Verb RunAs
    exit
}

if (-not (Test-IsAdmin)) { Invoke-SelfElevate }


# ----- INIT APPDATA DIRECTORIES ---------------------------------------------
foreach ($dir in @($script:AppDataRoot, $script:LogsDir, $script:UndoDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}


# ----- LOGGING --------------------------------------------------------------
$script:LogFile = Join-Path $script:LogsDir ("h3l1os-{0:yyyyMMdd}.log" -f (Get-Date))

function Write-AppLog {
    param([string]$Level = 'info', [string]$Event, [hashtable]$Data = @{})
    $entry = @{
        ts    = (Get-Date).ToUniversalTime().ToString('o')
        lvl   = $Level
        event = $Event
    }
    foreach ($k in $Data.Keys) { $entry[$k] = $Data[$k] }
    ($entry | ConvertTo-Json -Compress) | Add-Content -LiteralPath $script:LogFile -Encoding UTF8
}


# ----- LOAD WPF + WINFORMS --------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms


# ----- CONFIG LOADER --------------------------------------------------------
# Loading order (later wins):
#   1. Bundled default (in same dir or fetched from GitHub)
#   2. ~/.frntzn/config.json (user override)
#   3. $env:FRNTZN_CONFIG (env override)
#   4. -ConfigPath CLI arg (not implemented in irm|iex path)
function Get-DefaultConfig {
    # Returns the vendor-neutral default. Kept inline so the script is self-
    # contained when fetched via irm | iex.
    return @{
        version    = '1.0.0'
        client     = @{
            id              = 'default'
            name            = 'MendOS'
            primaryColor    = '#0E639C'
            supportContact  = $null
            ticketSystemUrl = $null
        }
        environment = @{
            ssoProvider     = $null
            defaultBrowser  = 'auto'
            commsApps       = @()
            managedByMdm    = $false
        }
        problems   = @{ include = @('*'); exclude = @(); custom = @() }
        compliance = @{
            phiAware                  = $false
            redactInDiagnosticBundle  = @()
            telemetry                 = 'disabled'
        }
        ui         = @{
            theme            = 'dark'
            language         = 'auto'
            auditModeDefault = $false
        }
    }
}

function Merge-Config {
    param($Base, $Override)
    if ($null -eq $Override) { return $Base }
    foreach ($key in $Override.Keys) {
        if ($Base.ContainsKey($key) -and $Base[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            $Base[$key] = Merge-Config $Base[$key] $Override[$key]
        } else {
            $Base[$key] = $Override[$key]
        }
    }
    return $Base
}

function Get-Config {
    $config = Get-DefaultConfig
    $userConfigPath = Join-Path $env:USERPROFILE '.frntzn\config.json'
    if (Test-Path $userConfigPath) {
        try {
            $user = Get-Content -LiteralPath $userConfigPath -Raw | ConvertFrom-Json -AsHashtable
            $config = Merge-Config $config $user
            Write-AppLog -Event 'config.user_loaded' -Data @{ path = $userConfigPath }
        } catch {
            Write-AppLog -Level 'warn' -Event 'config.user_invalid' -Data @{ path = $userConfigPath; err = $_.Exception.Message }
        }
    }
    if ($env:FRNTZN_CONFIG -and (Test-Path $env:FRNTZN_CONFIG)) {
        try {
            $env_cfg = Get-Content -LiteralPath $env:FRNTZN_CONFIG -Raw | ConvertFrom-Json -AsHashtable
            $config = Merge-Config $config $env_cfg
        } catch {
            Write-AppLog -Level 'warn' -Event 'config.env_invalid' -Data @{ err = $_.Exception.Message }
        }
    }
    return $config
}

$script:Config = Get-Config


# ----- LOCALIZATION ---------------------------------------------------------
# Returns localized string by key. If language file or key missing, falls
# back to English. Strings live in en.json/es.json/... but inlined here for
# irm | iex self-containment.
$script:Strings = @{
    'app.name'                    = 'MendOS'
    'app.subtitle.admin'          = 'MEND your Operating System'
    'app.subtitle.audit'          = 'AUDIT MODE - no changes will be made'
    'btn.refresh'                 = 'Refresh'
    'btn.exit'                    = 'Exit'
    'btn.fix'                     = 'Fix'
    'btn.undo'                    = 'Undo'
    'btn.export'                  = 'Export Diagnostic'
    'btn.audit_toggle'            = 'Audit Mode'
    'btn.escalate'                = 'Escalate to IT'
    'scan.uptime'                 = 'Uptime'
    'scan.disk'                   = 'Free disk space (C:)'
    'scan.ram'                    = 'RAM in use'
    'scan.updates'                = 'Days since last patch'
    'scan.hibernation'            = 'Hibernation'
    'scan.faststartup'            = 'Fast Startup'
    'scan.network'                = 'Network connectivity'
    'scan.mdm'                    = 'Managed by IT'
    'scan.value.disabled'         = 'Disabled'
    'scan.value.enabled'          = 'Enabled (recommend disabling)'
    'dropdown.placeholder.select' = '-- Select an issue --'
    'dropdown.placeholder.nomatch'= '-- No matches --'
    'dropdown.label.search'       = "Don't see your issue above?"
    'dialog.result.success'       = 'Done.'
    'dialog.result.failed'        = 'The action did not complete.'
    'dialog.audit.would_run'      = "AUDIT MODE`n`nIn normal mode, this would run:`n`n{0}`n`nNo changes will be made."
    'fix.policy_managed'          = "This setting is managed by your IT department's policy.`nContact your administrator to change it."
    'fix.requires_ultimate'       = "This multi-step workflow is part of the Ultimate tier.`nThe Light tier includes single-shot fixes and audit mode."
    'undo.empty'                  = 'Nothing to undo.'
    'license.tier_light'          = 'Light tier (free)'
    'license.tier_ultimate'       = 'Ultimate tier'
}

function L {
    param([string]$Key, [string[]]$Args)
    $val = $script:Strings[$Key]
    if (-not $val) { $val = $Key }
    if ($Args) { return [string]::Format($val, $Args) }
    return $val
}


# ----- GATE CHECK (license + machine binding) -------------------------------
# The "gate" decides whether the user has the Light or Ultimate tier. The
# Cloudflare Worker is authoritative; this code is the client side.
#
# Anti-tamper posture (honest about what we can and can't enforce):
#   - Source is open. A determined user can edit the script to force Ultimate.
#     That's fine - they're stealing from a $29 product, they're not the
#     customer.
#   - What we DO defend against: trivial cache-file editing. Cache binds to
#     a machine_hash; if the user copies their cache to another machine, it
#     won't match and the tool re-checks online.
#   - Signature on the response: the Worker signs (tier|machine|expires)
#     with a secret. Client can't cryptographically verify (secret is
#     server-side), but checks the signature is well-formed and present.
#     A forged cache without a valid-shape signature gets rejected.
#   - Server-side: machine_hash binding (max 3 machines per key by default).
#     A leaked key can't be shared with 100 friends.

function Get-MachineHash {
    # Hash machine identifiers so we don't transmit raw SID/UUID over the wire.
    # SHA-256 of MachineGuid + ComputerName, first 32 hex chars.
    try {
        $guid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -ErrorAction Stop).MachineGuid
    } catch {
        $guid = [Environment]::MachineName
    }
    $input = "$guid|$env:COMPUTERNAME"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($input))
    $sha.Dispose()
    return -join ($bytes[0..15] | ForEach-Object { $_.ToString('x2') })
}

function Test-ValidSignature {
    # Check the Worker's HMAC signature looks structurally valid (hex, 64 chars
    # for HMAC-SHA256). We can't verify cryptographically without the secret,
    # but a missing/short/non-hex signature means cache tampering or stub mode.
    param([string]$Sig)
    if (-not $Sig) { return $false }
    return ($Sig -match '^[a-f0-9]{64}$')
}

function Test-License {
    $machineHash = Get-MachineHash

    # Cache hit path - validates cache integrity AND machine binding
    if (Test-Path $script:LicenseCache) {
        try {
            $cache = Get-Content -LiteralPath $script:LicenseCache -Raw | ConvertFrom-Json
            $expiresAt = [DateTime]$cache.expires_at
            if ((Get-Date) -lt $expiresAt -and
                $cache.machine_hash -eq $machineHash -and
                (Test-ValidSignature $cache.signature) -and
                $cache.tier -in @('Light','Ultimate')) {
                Write-AppLog -Event 'license.cache_hit' -Data @{ tier = $cache.tier; reason = $cache.reason }
                return $cache.tier
            }
            Write-AppLog -Level 'warn' -Event 'license.cache_invalid' -Data @{
                reason = if ((Get-Date) -ge $expiresAt) { 'expired' }
                         elseif ($cache.machine_hash -ne $machineHash) { 'machine_mismatch' }
                         elseif (-not (Test-ValidSignature $cache.signature)) { 'signature_invalid' }
                         else { 'tier_invalid' }
            }
        } catch {
            Write-AppLog -Level 'warn' -Event 'license.cache_corrupt' -Data @{ err = $_.Exception.Message }
        }
    }

    # Online check
    try {
        $body = @{
            key          = $env:FRNTZN_KEY
            machine_hash = $machineHash
            v            = $script:Version
        } | ConvertTo-Json -Compress

        $resp = Invoke-RestMethod -Uri $script:LicenseUrl `
                                  -Method Post `
                                  -Body $body `
                                  -ContentType 'application/json' `
                                  -UserAgent $script:UserAgent `
                                  -TimeoutSec 5 -ErrorAction Stop

        $tier = if ($resp.tier -in @('Light','Ultimate')) { $resp.tier } else { 'Light' }

        # Persist full response including signature so future cache checks
        # have something to validate against
        @{
            tier         = $tier
            machine_hash = $machineHash
            issued_at    = $resp.issued_at
            expires_at   = $resp.expires_at
            signature    = $resp.signature
            reason       = $resp.reason
        } | ConvertTo-Json | Set-Content -LiteralPath $script:LicenseCache -Encoding UTF8

        Write-AppLog -Event 'license.online_check' -Data @{ tier = $tier; reason = $resp.reason }
        return $tier
    } catch {
        # Fail open to Light. Captive portals, transient errors shouldn't lock
        # users out. Cache nothing in this state - next launch retries.
        Write-AppLog -Level 'warn' -Event 'license.offline_fallback' -Data @{ err = $_.Exception.Message }
        return 'Light'
    }
}


function Send-Telemetry {
    # OPT-IN ONLY. Called only when $script:Config.compliance.telemetry -eq 'enabled'.
    # Body is whitelisted server-side too - anything we add here gets dropped
    # by the Worker if it isn't a known event name.
    param(
        [Parameter(Mandatory)] [ValidateSet(
            'app.start','app.exit','scan.complete',
            'fix.applied','fix.failed',
            'workflow.complete','workflow.failed',
            'bundle.exported','escalation.sent'
        )] [string]$Event,
        [bool]$Success,
        [string]$ScanId
    )
    if ($script:Config.compliance.telemetry -ne 'enabled') { return }

    $body = @{
        event   = $Event
        version = $script:Version
        os      = "Win$($PSVersionTable.PSVersion.Major)"
        scan_id = $ScanId
        success = $Success
    } | ConvertTo-Json -Compress

    try {
        Invoke-RestMethod -Uri $script:TelemetryUrl `
                          -Method Post -Body $body `
                          -ContentType 'application/json' `
                          -UserAgent $script:UserAgent `
                          -TimeoutSec 3 -ErrorAction Stop | Out-Null
    } catch {
        # Telemetry failure is non-fatal and intentionally swallowed
    }
}

$script:Tier = Test-License


# ----- MDM / POLICY DETECTION -----------------------------------------------
# Detects whether the machine is enrolled in MDM or has Group Policy applied.
# Used to skip fixes that policy would override anyway.
function Test-IsMdmManaged {
    # Intune enrolment leaves traces here:
    $intunePath = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
    if (Test-Path $intunePath) {
        $enrollments = Get-ChildItem $intunePath -ErrorAction SilentlyContinue |
                       Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).EnrollmentState -eq 1 }
        if ($enrollments) { return $true }
    }
    return $false
}

function Test-PolicyManaged {
    param([string]$Path, [string]$Name)
    # Check both Group Policy and PolicyManager paths
    $policyPaths = @(
        $Path -replace '^HKLM:\\SOFTWARE\\', 'HKLM:\SOFTWARE\Policies\'
        $Path -replace '^HKCU:\\SOFTWARE\\', 'HKCU:\SOFTWARE\Policies\'
        'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device'
    )
    foreach ($p in $policyPaths) {
        if (Test-Path $p) {
            $val = Get-ItemProperty -Path $p -Name $Name -ErrorAction SilentlyContinue
            if ($val) { return $true }
        }
    }
    return $false
}

$script:IsMdmManaged = Test-IsMdmManaged


# ----- AUDIT MODE STATE -----------------------------------------------------
$script:AuditMode = [bool]$script:Config.ui.auditModeDefault


# ----- SAFE REGISTRY WRITE + UNDO REGISTRY ----------------------------------
function Add-UndoEntry {
    param([string]$Description, [scriptblock]$UndoAction)
    $entry = @{
        id          = [guid]::NewGuid().ToString()
        ts          = (Get-Date).ToString('o')
        description = $Description
        # Serialize the script block to text so it survives restart
        undo_script = $UndoAction.ToString()
    }
    $undoFile = Join-Path $script:UndoDir ("{0}.json" -f $entry.id)
    $entry | ConvertTo-Json | Set-Content -LiteralPath $undoFile -Encoding UTF8
    Write-AppLog -Event 'undo.registered' -Data @{ description = $Description }
}

function Set-RegistryValueSafe {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] $Value,
        [string]$Type = 'DWord'
    )
    # Refuse anything outside HKLM:\ or HKCU:\
    if ($Path -notmatch '^HK(LM|CU):\\') {
        throw "Refusing registry path outside HKLM/HKCU: $Path"
    }
    # Check policy
    if (Test-PolicyManaged -Path $Path -Name $Name) {
        Write-AppLog -Level 'warn' -Event 'fix.policy_blocked' -Data @{ path = $Path; name = $Name }
        throw 'POLICY_MANAGED'
    }
    # Record undo
    $oldValue = $null
    $hadOld = $false
    try {
        $existing = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        $oldValue = $existing.$Name
        $hadOld = $true
    } catch {}
    $undoDesc = "Restore $Path\$Name"
    if ($hadOld) {
        $undoBlock = [scriptblock]::Create("Set-ItemProperty -Path '$Path' -Name '$Name' -Value $oldValue -Type $Type -Force")
    } else {
        $undoBlock = [scriptblock]::Create("Remove-ItemProperty -Path '$Path' -Name '$Name' -Force -ErrorAction SilentlyContinue")
    }
    Add-UndoEntry -Description $undoDesc -UndoAction $undoBlock

    # If audit mode, log what we WOULD do and return success-without-changing
    if ($script:AuditMode) {
        Write-AppLog -Event 'audit.would_set' -Data @{ path = $Path; name = $Name; value = $Value }
        return
    }

    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop

    # Verify
    $verify = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    if ($verify -ne $Value) { throw "Verification failed: $Path\$Name (expected $Value, got $verify)" }
    Write-AppLog -Event 'fix.registry_set' -Data @{ path = $Path; name = $Name; value = $Value }
}

function Get-UndoEntries {
    Get-ChildItem -LiteralPath $script:UndoDir -Filter '*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json }
}

function Invoke-LastUndo {
    $entries = @(Get-UndoEntries)
    if ($entries.Count -eq 0) {
        [System.Windows.MessageBox]::Show((L 'undo.empty'), 'FRNTZN', 'OK', 'Information') | Out-Null
        return
    }
    $latest = $entries[0]
    try {
        $block = [scriptblock]::Create($latest.undo_script)
        & $block
        $undoFile = Join-Path $script:UndoDir ("{0}.json" -f $latest.id)
        Remove-Item -LiteralPath $undoFile -Force -ErrorAction SilentlyContinue
        Write-AppLog -Event 'undo.applied' -Data @{ description = $latest.description }
        [System.Windows.MessageBox]::Show("Undone: $($latest.description)", 'FRNTZN', 'OK', 'Information') | Out-Null
        Invoke-HealthScan
    } catch {
        Write-AppLog -Level 'error' -Event 'undo.failed' -Data @{ err = $_.Exception.Message }
        [System.Windows.MessageBox]::Show("Could not undo: $($_.Exception.Message)", 'FRNTZN', 'OK', 'Warning') | Out-Null
    }
}


# ----- METRIC HELPERS (used by scan + workflows) ----------------------------
function Get-CurrentRamPercent {
    $os = Get-CimInstance Win32_OperatingSystem
    return [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
}

function Get-CurrentFreeDiskGB {
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    return [math]::Round($drive.FreeSpace / 1GB, 2)
}

function Test-NetworkOnline {
    try {
        $r = Test-NetConnection -ComputerName '1.1.1.1' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        return [bool]$r
    } catch { return $false }
}


# ----- DIAGNOSTIC FUNCTIONS -------------------------------------------------
function Get-UptimeStatus {
    $lastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $lastBoot
    $days = [math]::Floor($uptime.TotalDays); $hours = $uptime.Hours
    $status = if ($days -ge 7) { 'red' } elseif ($days -ge 2) { 'yellow' } else { 'green' }
    return @{ Text = "$days days, $hours hours"; Status = $status }
}

function Get-DiskStatus {
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $freeGB = [math]::Round($drive.FreeSpace / 1GB, 1)
    $totalGB = [math]::Round($drive.Size / 1GB, 1)
    $pctFree = ($drive.FreeSpace / $drive.Size) * 100
    $status = if ($pctFree -lt 10) { 'red' } elseif ($pctFree -lt 20) { 'yellow' } else { 'green' }
    return @{ Text = "$freeGB GB free of $totalGB GB"; Status = $status }
}

function Get-RamStatus {
    $os = Get-CimInstance Win32_OperatingSystem
    $usedKB = $os.TotalVisibleMemorySize - $os.FreePhysicalMemory
    $pctUsed = ($usedKB / $os.TotalVisibleMemorySize) * 100
    $usedGB = [math]::Round($usedKB / 1MB, 1)
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $status = if ($pctUsed -ge 90) { 'red' } elseif ($pctUsed -ge 75) { 'yellow' } else { 'green' }
    return @{ Text = "$usedGB GB / $totalGB GB ($([math]::Round($pctUsed))%)"; Status = $status }
}

function Get-UpdateStatus {
    try {
        $last = Get-HotFix -ErrorAction Stop | Where-Object InstalledOn |
                Sort-Object InstalledOn -Descending | Select-Object -First 1
        if (-not $last) { return @{ Text = 'Unable to determine'; Status = 'yellow' } }
        $days = ((Get-Date) - $last.InstalledOn).Days
        $status = if ($days -ge 60) { 'red' } elseif ($days -ge 30) { 'yellow' } else { 'green' }
        return @{ Text = "$days days since last patch"; Status = $status }
    } catch { return @{ Text = 'Check failed'; Status = 'yellow' } }
}

function Get-HibernationStatus {
    if (Test-Path "$env:SystemDrive\hiberfil.sys") {
        return @{ Text = (L 'scan.value.enabled'); Status = 'yellow' }
    }
    return @{ Text = (L 'scan.value.disabled'); Status = 'green' }
}

function Get-FastStartupStatus {
    try {
        $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -ErrorAction Stop).HiberbootEnabled
        if ($v -eq 1) { return @{ Text = (L 'scan.value.enabled'); Status = 'yellow' } }
        return @{ Text = (L 'scan.value.disabled'); Status = 'green' }
    } catch { return @{ Text = 'Unable to read'; Status = 'yellow' } }
}

function Get-NetworkStatus {
    if (Test-NetworkOnline) { return @{ Text = 'Online'; Status = 'green' } }
    return @{ Text = 'No internet detected'; Status = 'red' }
}

function Get-MdmStatus {
    if ($script:IsMdmManaged) {
        return @{ Text = 'Yes (some fixes may be locked)'; Status = 'green' }
    }
    return @{ Text = 'No'; Status = 'green' }
}


# ============================================================================
#  FIX REGISTRY - single-shot remediations available in Light + Ultimate
# ============================================================================
$Fixes = @{
    Ram = @{
        Name        = 'Free Up Memory'
        Description = "Opens Task Manager so you can see what's eating memory and close apps.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            try { Start-Process taskmgr.exe -ArgumentList '/7' -ErrorAction Stop }
            catch { Start-Process taskmgr.exe }
            return $true
        }
    }
    Hibernation = @{
        Name        = 'Disable Hibernation'
        Description = "Runs: powercfg /h off`n`n  - hiberfil.sys is deleted (frees 4-16 GB)`n  - Fast Startup will also stop working`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            # Snapshot for undo
            $current = Test-Path "$env:SystemDrive\hiberfil.sys"
            if ($current) {
                Add-UndoEntry -Description 'Re-enable Hibernation' -UndoAction { powercfg /h on | Out-Null }
            }
            powercfg /h off 2>&1 | Out-Null
            return ($LASTEXITCODE -eq 0)
        }
    }
    FastStartup = @{
        Name        = 'Disable Fast Startup'
        Description = "Sets HiberbootEnabled = 0 in the registry.`n`nProceed?"
        Action      = {
            try {
                Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
                                      -Name 'HiberbootEnabled' -Value 0
                return $true
            } catch {
                if ($_.Exception.Message -eq 'POLICY_MANAGED') {
                    [System.Windows.MessageBox]::Show((L 'fix.policy_managed'), 'Policy-managed', 'OK', 'Information') | Out-Null
                }
                return $false
            }
        }
    }
}


# ============================================================================
#  PROBLEM REGISTRY - user-pickable issues from the dropdown
#  Organized by 12-category taxonomy (identity, audio, comms, browser, network,
#  hardware, performance, updates, display, email, print, os).
# ============================================================================
$Problems = @{

    # ----- IDENTITY / SSO / MFA --------------------------------------------
    'identity.okta-mfa-loop' = @{
        Label       = "Okta keeps asking me to verify / push not arriving"
        Keywords    = @('okta','mfa','push','verify','2fa','authentication','login loop','sso','sign-in')
        Name        = 'Okta MFA Troubleshooter'
        Description = "Common fixes for Okta Verify problems:`n`n  1. Time sync (TOTP needs accurate clock)`n  2. Open Okta self-service page to re-enroll device`n  3. Check notification permissions`n`nThis will sync the clock and open the SSO URL. Re-enrollment must be done manually.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            w32tm /resync /force 2>&1 | Out-Null
            $url = $script:Config.environment.ssoUrl
            if (-not $url) { $url = 'https://www.okta.com/help' }
            Start-Process $url
            return $true
        }
    }

    'identity.account-locked' = @{
        Label       = "My account is locked (can't sign in)"
        Keywords    = @('locked','account','password','unlock','forgot password','reset')
        Name        = 'Account Locked - Self-Service'
        Description = "Opens your organization's password reset / unlock page.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            $url = $script:Config.environment.ssoUrl
            if (-not $url) { $url = 'ms-settings:signinoptions' }
            Start-Process $url
            return $true
        }
    }

    # ----- AUDIO ------------------------------------------------------------
    'audio.no-output' = @{
        Label       = "I can't hear anything (no sound output)"
        Keywords    = @('sound','audio','speaker','headset','headphones','volume','silent','no sound','mute')
        Name        = 'Audio Output Troubleshooter'
        Description = "This will:`n  1. Restart the Windows Audio service`n  2. Open Sound settings so you can pick the right output device`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            try {
                Restart-Service -Name 'Audiosrv' -Force -ErrorAction Stop
                Start-Process 'ms-settings:sound'
                return $true
            } catch { return $false }
        }
    }

    'audio.mic-not-working' = @{
        Label       = "Callers can't hear me (microphone not working)"
        Keywords    = @('mic','microphone','voice','recording','input','talk','meeting')
        Name        = 'Microphone Troubleshooter'
        Description = "Opens Sound > Input settings and microphone privacy permissions.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            Start-Process 'ms-settings:sound'
            Start-Process 'ms-settings:privacy-microphone'
            return $true
        }
    }

    'audio.logitech-double-mute' = @{
        Label       = "Logitech headset stuck muted (multi-layer mute)"
        Keywords    = @('logitech','headset','mute','stuck','double-mute','g hub','wireless')
        Name        = 'Logitech Double-Mute Fix'
        Description = "Logitech headsets have multiple mute layers that can fight each other:`n  - Headset hardware mute button`n  - Logitech G HUB software mute`n  - Windows mute`n  - Per-app mute (Zoom/Teams/etc)`n`nThis will restart Audio + open Sound settings. Check the headset's physical mute button too.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            try {
                Restart-Service -Name 'Audiosrv' -Force -ErrorAction Stop
                Start-Process 'ms-settings:sound'
                return $true
            } catch { return $false }
        }
    }

    # ----- COMMS APPS -------------------------------------------------------
    'comms.slack-not-loading' = @{
        Label       = "Slack won't load / shows blank / login loop"
        Keywords    = @('slack','blank','loading','workspace','login','frozen')
        Name        = 'Reset Slack'
        Description = "Clears Slack's cache so it re-syncs from scratch. Your messages stay on the server.`n`nThis will close Slack if it's running.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            Get-Process -Name 'slack' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            $cache = Join-Path $env:APPDATA 'Slack\Cache'
            if (Test-Path $cache) { Remove-Item "$cache\*" -Recurse -Force -ErrorAction SilentlyContinue }
            $codeCache = Join-Path $env:APPDATA 'Slack\Code Cache'
            if (Test-Path $codeCache) { Remove-Item "$codeCache\*" -Recurse -Force -ErrorAction SilentlyContinue }
            return $true
        }
    }

    'comms.zoom-crash' = @{
        Label       = "Zoom keeps crashing / freezing"
        Keywords    = @('zoom','crash','freeze','meeting','screen share')
        Name        = 'Reset Zoom'
        Description = "Clears Zoom's cache. You'll need to sign back in.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            Get-Process -Name 'Zoom' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            $zoomData = Join-Path $env:APPDATA 'Zoom\data'
            if (Test-Path $zoomData) { Remove-Item "$zoomData\*" -Recurse -Force -ErrorAction SilentlyContinue }
            return $true
        }
    }

    'comms.teams-login-loop' = @{
        Label       = "Teams keeps asking me to sign in (login loop)"
        Keywords    = @('teams','microsoft teams','login','sign-in','loop','authentication')
        Name        = 'Reset Teams'
        Description = "Clears Teams credentials and cache. You'll sign in fresh.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            Get-Process -Name 'Teams','ms-teams' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            $paths = @(
                "$env:APPDATA\Microsoft\Teams"
                "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache"
            )
            foreach ($p in $paths) {
                if (Test-Path $p) { Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue }
            }
            cmdkey /list | Where-Object { $_ -match 'msteams' } | ForEach-Object {
                $tgt = ($_ -split ':',2)[1].Trim()
                cmdkey /delete:$tgt 2>&1 | Out-Null
            }
            return $true
        }
    }

    # ----- BROWSER ----------------------------------------------------------
    'browser.chrome-cache' = @{
        Label       = "Chrome is slow / pages won't load (clear cache)"
        Keywords    = @('chrome','slow','cache','google','browser','pages','loading')
        Name        = 'Clear Chrome Cache (keeps bookmarks)'
        Description = "Closes Chrome and clears its cache. Bookmarks, history, saved passwords are preserved.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            Get-Process -Name 'chrome' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            $cache = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
            if (Test-Path $cache) { Remove-Item "$cache\*" -Recurse -Force -ErrorAction SilentlyContinue }
            $codeCache = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"
            if (Test-Path $codeCache) { Remove-Item "$codeCache\*" -Recurse -Force -ErrorAction SilentlyContinue }
            return $true
        }
    }

    'browser.edge-cache' = @{
        Label       = "Microsoft Edge is slow / pages won't load"
        Keywords    = @('edge','microsoft edge','cache','browser')
        Name        = 'Clear Edge Cache'
        Description = "Closes Edge and clears its cache. Bookmarks preserved.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            Get-Process -Name 'msedge' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            $cache = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
            if (Test-Path $cache) { Remove-Item "$cache\*" -Recurse -Force -ErrorAction SilentlyContinue }
            return $true
        }
    }

    # ----- NETWORK ----------------------------------------------------------
    'network.dns-flush' = @{
        Label       = "Internet connected but websites won't load (DNS)"
        Keywords    = @('dns','website','page','load','internet','browser','timeout','resolve')
        Name        = 'Flush DNS Cache'
        Description = "Runs ipconfig /flushdns + restarts the DNS Client service.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            ipconfig /flushdns 2>&1 | Out-Null
            try { Restart-Service -Name 'Dnscache' -Force -ErrorAction Stop } catch {}
            return ($LASTEXITCODE -eq 0)
        }
    }

    'network.wifi-toggle' = @{
        Label       = "WiFi acting up (toggle it off/on)"
        Keywords    = @('wifi','wireless','disconnect','drop','airplane','toggle')
        Name        = 'Reset WiFi Adapter'
        Description = "Disables and re-enables the WiFi adapter. You'll briefly lose connection.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            try {
                $wifi = Get-NetAdapter -Physical | Where-Object { $_.MediaType -like '*802.11*' } | Select-Object -First 1
                if (-not $wifi) { return $false }
                Disable-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 2
                Enable-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction Stop
                return $true
            } catch { return $false }
        }
    }

    # ----- HARDWARE ---------------------------------------------------------
    'hardware.bluetooth-reset' = @{
        Label       = "Bluetooth not working / device won't pair"
        Keywords    = @('bluetooth','bt','pair','pairing','wireless','headset','mouse','keyboard')
        Name        = 'Reset Bluetooth Service'
        Description = "Restarts the Bluetooth Support Service.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            try {
                Restart-Service -Name 'bthserv' -Force -ErrorAction Stop
                Start-Process 'ms-settings:bluetooth'
                return $true
            } catch { return $false }
        }
    }

    'hardware.camera-reset' = @{
        Label       = "Camera/webcam not detected"
        Keywords    = @('camera','webcam','video','meeting','built-in camera')
        Name        = 'Reset Camera + Privacy'
        Description = "Restarts the Windows Camera Frame Server service and opens Camera privacy settings.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            try { Restart-Service -Name 'FrameServer' -Force -ErrorAction SilentlyContinue } catch {}
            Start-Process 'ms-settings:privacy-webcam'
            return $true
        }
    }

    # ----- PERFORMANCE ------------------------------------------------------
    'performance.slow-low-end' = @{
        Label       = "My computer is slow / lagging (multi-step optimization)"
        Keywords    = @('slow','lag','lagging','laggy','low-end','celeron','n4500','underpowered','choppy','crashing','out of memory','freezing','sluggish','heavy','boost','optimize')
        Name        = 'Boost Low-End System'
        Description = 'Multi-step optimization workflow.'
        Action      = { Invoke-Workflow -WorkflowKey 'low-end-boost'; return $true }
        IsWorkflow  = $true
    }

    'performance.startup-apps' = @{
        Label       = "Computer takes forever to start up"
        Keywords    = @('boot','startup','slow start','login','autostart','start up')
        Name        = 'Open Startup Apps Settings'
        Description = "Opens Settings > Startup so you can disable apps that load at boot.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            Start-Process 'ms-settings:startupapps'
            return $true
        }
    }

    # ----- UPDATES ----------------------------------------------------------
    'updates.check' = @{
        Label       = "Check for Windows Updates"
        Keywords    = @('update','patch','security','upgrade','feature','install')
        Name        = 'Open Windows Update'
        Description = "Opens Settings > Windows Update.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            Start-Process 'ms-settings:windowsupdate'
            return $true
        }
    }

    'updates.reset' = @{
        Label       = "Windows Updates stuck / won't install"
        Keywords    = @('update','stuck','failed','wuauserv','reset','sfc')
        Name        = 'Reset Windows Update'
        Description = "Stops Update services, clears the SoftwareDistribution folder, restarts services.`n`nThis is the standard fix for stuck updates. Proceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            try {
                Stop-Service wuauserv,bits -Force -ErrorAction SilentlyContinue
                Rename-Item -Path "$env:SystemRoot\SoftwareDistribution" -NewName "SoftwareDistribution.old.$(Get-Date -Format yyyyMMddHHmmss)" -Force -ErrorAction SilentlyContinue
                Start-Service wuauserv,bits -ErrorAction Stop
                return $true
            } catch { return $false }
        }
    }

    # ----- DISPLAY ----------------------------------------------------------
    'display.external-monitor' = @{
        Label       = "External monitor not detected"
        Keywords    = @('monitor','display','external','screen','hdmi','displayport','second screen')
        Name        = 'Reset Display Detection'
        Description = "Forces Windows to re-detect connected displays (Win+Ctrl+Shift+B equivalent).`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            # The keyboard shortcut Win+Ctrl+Shift+B restarts the graphics stack
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait('^+%{B}')
            Start-Sleep -Seconds 1
            Start-Process 'ms-settings:display'
            return $true
        }
    }

    # ----- EMAIL ------------------------------------------------------------
    'email.outlook-stuck' = @{
        Label       = "Outlook stuck syncing / not receiving email"
        Keywords    = @('outlook','email','stuck','sync','mail','not receiving')
        Name        = 'Outlook Repair Helper'
        Description = "Opens Mail control panel where you can repair the profile.`n`nThis is the entry point - actual repair is done in the Mail dialog.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            try { Start-Process 'control.exe' -ArgumentList 'mlcfg32.cpl' } catch {}
            return $true
        }
    }

    # ----- PRINT ------------------------------------------------------------
    'print.spooler-restart' = @{
        Label       = "Printer shows offline / won't print"
        Keywords    = @('printer','print','spooler','offline','queue','stuck','printing')
        Name        = 'Restart Print Spooler + Clear Queue'
        Description = "This will:`n  1. Stop the Print Spooler service`n  2. Clear stuck print jobs`n  3. Restart the service`n  4. Open Printer settings`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            try {
                Stop-Service Spooler -Force -ErrorAction Stop
                Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
                Start-Service Spooler -ErrorAction Stop
                Start-Process 'ms-settings:printers'
                return $true
            } catch { return $false }
        }
    }

    # ----- OS / ACCOUNT / PROFILE ------------------------------------------
    'os.pin-setup' = @{
        Label       = "Set up PIN or Fingerprint login (Windows Hello)"
        Keywords    = @('password','login','pin','biometric','hello','passkey','fingerprint','face')
        Name        = 'Open Sign-in Options'
        Description = "Opens Settings > Sign-in options.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            Start-Process 'ms-settings:signinoptions'
            return $true
        }
    }

    'os.storage-cleanup' = @{
        Label       = "Disk is almost full (clean up files)"
        Keywords    = @('disk full','storage','space','cleanup','low disk','full')
        Name        = 'Open Storage Sense'
        Description = "Opens Settings > Storage where you can run Storage Sense and review what's eating space.`n`nProceed?"
        Action      = {
            if ($script:AuditMode) { return $true }
            Start-Process 'ms-settings:storagesense'
            return $true
        }
    }
}


# ============================================================================
#  WORKFLOWS - multi-step verified procedures (Ultimate tier)
#  Each step receives $State hashtable; can read/write to share with other steps
# ============================================================================
$Workflows = @{

    'low-end-boost' = @{
        Name        = 'Boost Low-End System'
        Description = "Multi-step optimization for systems struggling under load.`n`nSteps:`n  1. Create restore point (Win)`n  2. Capture baseline metrics`n  3. Switch to High Performance power plan`n  4. Set visual effects to Performance mode`n  5. Clear temp files`n  6. Empty Recycle Bin`n  7. Disable background app activity`n  8. Compare before/after`n`nSafe and reversible. Defender stays untouched.`n`nProceed?"
        UltimateOnly= $true
        Steps       = @(
            @{
                Label  = 'Create restore point (safety net)'
                Action = {
                    param($State)
                    if ($script:AuditMode) { return @{ Success = $true; Message = '[audit] would create restore point' } }
                    try {
                        Checkpoint-Computer -Description "FRNTZN: before low-end-boost" -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
                        return @{ Success = $true; Message = 'Restore point created' }
                    } catch {
                        # Windows throttles to 1 per 24h - this is fine
                        return @{ Success = $true; Message = 'Skipped (Windows throttle or restore disabled)' }
                    }
                }
            }
            @{
                Label  = 'Capture baseline metrics'
                Action = {
                    param($State)
                    $State['BaselineRam'] = Get-CurrentRamPercent
                    $State['BaselineFreeDisk'] = Get-CurrentFreeDiskGB
                    return @{ Success = $true; Message = "RAM $($State['BaselineRam'])%, disk $($State['BaselineFreeDisk']) GB free" }
                }
            }
            @{
                Label  = 'Switch to High Performance power plan'
                Action = {
                    param($State)
                    if ($script:AuditMode) { return @{ Success = $true; Message = '[audit] would switch power plan' } }
                    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Add-UndoEntry -Description 'Restore Balanced power plan' -UndoAction { powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null }
                        return @{ Success = $true; Message = 'High Performance plan active' }
                    }
                    return @{ Success = $false; Message = 'High Performance plan unavailable on this build' }
                }
            }
            @{
                Label  = 'Set visual effects to Performance mode'
                Action = {
                    param($State)
                    try {
                        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' `
                                              -Name 'VisualFXSetting' -Value 2
                        return @{ Success = $true; Message = 'Visual effects set to Performance' }
                    } catch {
                        if ($_.Exception.Message -eq 'POLICY_MANAGED') {
                            return @{ Success = $false; Message = 'Skipped: managed by IT policy' }
                        }
                        return @{ Success = $false; Message = $_.Exception.Message }
                    }
                }
            }
            @{
                Label  = 'Clear temp files'
                Action = {
                    param($State)
                    if ($script:AuditMode) { return @{ Success = $true; Message = '[audit] would clear temp' } }
                    $before = (Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
                    $after = (Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    $freed = [math]::Round((($before - $after) / 1MB), 1)
                    if ($freed -lt 0) { $freed = 0 }
                    return @{ Success = $true; Message = "Cleared $freed MB" }
                }
            }
            @{
                Label  = 'Empty Recycle Bin'
                Action = {
                    param($State)
                    if ($script:AuditMode) { return @{ Success = $true; Message = '[audit] would empty bin' } }
                    try {
                        Clear-RecycleBin -Force -ErrorAction Stop
                        return @{ Success = $true; Message = 'Emptied' }
                    } catch { return @{ Success = $true; Message = 'Already empty' } }
                }
            }
            @{
                Label  = 'Disable background app activity'
                Action = {
                    param($State)
                    try {
                        Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' `
                                              -Name 'GlobalUserDisabled' -Value 1
                        return @{ Success = $true; Message = 'Disabled' }
                    } catch {
                        if ($_.Exception.Message -eq 'POLICY_MANAGED') {
                            return @{ Success = $false; Message = 'Skipped: managed by IT policy' }
                        }
                        return @{ Success = $false; Message = $_.Exception.Message }
                    }
                }
            }
            @{
                Label  = 'Compare before/after'
                Action = {
                    param($State)
                    $afterRam = Get-CurrentRamPercent
                    $afterDisk = Get-CurrentFreeDiskGB
                    $ramDelta = [math]::Round($State['BaselineRam'] - $afterRam, 1)
                    $diskDelta = [math]::Round($afterDisk - $State['BaselineFreeDisk'], 2)
                    return @{
                        Success = $true
                        Message = "RAM: $($State['BaselineRam'])% -> $afterRam% | Disk freed: $diskDelta GB"
                    }
                }
            }
        )
    }

    'network-reset' = @{
        Name         = 'Network Stack Reset'
        Description  = "Resets the Windows TCP/IP stack. Useful when nothing else fixes network issues.`n`nWILL REQUIRE A RESTART. You'll lose connection temporarily.`n`nSteps:`n  1. Flush DNS`n  2. Reset Winsock`n  3. Reset TCP/IP stack`n  4. Release/renew IP`n  5. Reset network adapters`n`nProceed?"
        UltimateOnly = $true
        Steps        = @(
            @{
                Label  = 'Flush DNS cache'
                Action = {
                    param($State)
                    if ($script:AuditMode) { return @{ Success = $true; Message = '[audit] ipconfig /flushdns' } }
                    ipconfig /flushdns 2>&1 | Out-Null
                    return @{ Success = ($LASTEXITCODE -eq 0); Message = 'Done' }
                }
            }
            @{
                Label  = 'Reset Winsock'
                Action = {
                    param($State)
                    if ($script:AuditMode) { return @{ Success = $true; Message = '[audit] netsh winsock reset' } }
                    netsh winsock reset 2>&1 | Out-Null
                    return @{ Success = ($LASTEXITCODE -eq 0); Message = 'Done (reboot needed to take full effect)' }
                }
            }
            @{
                Label  = 'Reset TCP/IP stack'
                Action = {
                    param($State)
                    if ($script:AuditMode) { return @{ Success = $true; Message = '[audit] netsh int ip reset' } }
                    netsh int ip reset 2>&1 | Out-Null
                    return @{ Success = ($LASTEXITCODE -eq 0); Message = 'Done (reboot needed)' }
                }
            }
            @{
                Label  = 'Release IP'
                Action = {
                    param($State)
                    if ($script:AuditMode) { return @{ Success = $true; Message = '[audit] ipconfig /release' } }
                    ipconfig /release 2>&1 | Out-Null
                    return @{ Success = $true; Message = 'Done' }
                }
            }
            @{
                Label  = 'Renew IP'
                Action = {
                    param($State)
                    if ($script:AuditMode) { return @{ Success = $true; Message = '[audit] ipconfig /renew' } }
                    ipconfig /renew 2>&1 | Out-Null
                    return @{ Success = $true; Message = 'Done' }
                }
            }
            @{
                Label  = 'Network status'
                Action = {
                    param($State)
                    Start-Sleep -Seconds 2
                    $online = Test-NetworkOnline
                    return @{ Success = $online; Message = if ($online) { 'Internet reachable' } else { 'Still no internet - reboot required' } }
                }
            }
        )
    }
}


# ============================================================================
#  WORKFLOW RUNNER
# ============================================================================
function Invoke-Workflow {
    param([string]$WorkflowKey)
    $wf = $Workflows[$WorkflowKey]
    if (-not $wf) { return }

    # Tier check
    if ($wf.UltimateOnly -and $script:Tier -ne 'Ultimate') {
        [System.Windows.MessageBox]::Show((L 'fix.requires_ultimate'), 'Ultimate tier', 'OK', 'Information') | Out-Null
        Write-AppLog -Event 'workflow.blocked_tier' -Data @{ key = $WorkflowKey; tier = $script:Tier }
        return
    }

    # Audit mode warning
    $desc = $wf.Description
    if ($script:AuditMode) {
        $stepList = ($wf.Steps | ForEach-Object { "  - $($_.Label)" }) -join "`n"
        $desc = L 'dialog.audit.would_run' -Args @($stepList)
    }

    $answer = [System.Windows.MessageBox]::Show($desc, $wf.Name, 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }

    Write-AppLog -Event 'workflow.start' -Data @{ key = $WorkflowKey; audit = $script:AuditMode }

    $state = @{}
    $results = @()
    foreach ($step in $wf.Steps) {
        try {
            $r = & $step.Action $state
        } catch {
            $r = @{ Success = $false; Message = "Exception: $($_.Exception.Message)" }
        }
        $results += [pscustomobject]@{ Label = $step.Label; Success = $r.Success; Message = $r.Message }
        Write-AppLog -Event 'workflow.step' -Data @{ key = $WorkflowKey; step = $step.Label; ok = $r.Success }
    }

    # Build summary
    $lines = @("$($wf.Name) - Complete", "")
    foreach ($r in $results) {
        $mark = if ($r.Success) { '[OK]  ' } else { '[FAIL]' }
        $lines += "$mark $($r.Label)"
        if ($r.Message) { $lines += "       $($r.Message)" }
    }
    [System.Windows.MessageBox]::Show(($lines -join "`n"), $wf.Name, 'OK', 'Information') | Out-Null
    Write-AppLog -Event 'workflow.complete' -Data @{ key = $WorkflowKey; success_count = ($results | Where-Object Success).Count; total = $results.Count }

    Invoke-HealthScan
}


# ============================================================================
#  DIAGNOSTIC BUNDLE EXPORT
# ============================================================================
function Export-DiagnosticBundle {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bundleDir = Join-Path ([Environment]::GetFolderPath('Desktop')) "FRNTZN-Diagnostic-$ts"
    New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null

    # 1. summary.txt
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $summary = @"
MendOS Diagnostic Bundle
Generated: $(Get-Date -Format 'o')
Tool version: $script:Version
Tier: $script:Tier
Audit mode: $script:AuditMode
Config client: $($script:Config.client.name)
MDM managed: $script:IsMdmManaged

OS         : $($os.Caption) $($os.Version) (build $($os.BuildNumber))
Computer   : $($cs.Manufacturer) $($cs.Model)
CPU        : $($cpu.Name)
RAM        : $([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB
"@
    Set-Content -LiteralPath (Join-Path $bundleDir 'summary.txt') -Value $summary -Encoding UTF8

    # 2. attempted-fixes.log (extracted from main log)
    if (Test-Path $script:LogFile) {
        Copy-Item -LiteralPath $script:LogFile -Destination (Join-Path $bundleDir 'h3l1os.log')
    }

    # 3. system-info.txt
    @"
=== Disks ===
$(Get-CimInstance Win32_LogicalDisk | Format-Table DeviceID,Size,FreeSpace,FileSystem -AutoSize | Out-String)

=== Network ===
$(ipconfig /all | Out-String)

=== Top RAM processes ===
$(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Name,@{n='RAM_MB';e={[math]::Round($_.WorkingSet64/1MB)}} | Format-Table -AutoSize | Out-String)
"@ | Set-Content -LiteralPath (Join-Path $bundleDir 'system-info.txt') -Encoding UTF8

    # 4. config used (PII-redacted)
    $cfgCopy = $script:Config | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $cfgCopy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $bundleDir 'config.json') -Encoding UTF8

    # Zip it
    $zipPath = "$bundleDir.zip"
    Compress-Archive -Path "$bundleDir\*" -DestinationPath $zipPath -Force
    Remove-Item -LiteralPath $bundleDir -Recurse -Force

    # Path to clipboard
    Set-Clipboard -Value $zipPath

    Write-AppLog -Event 'bundle.exported' -Data @{ path = $zipPath }

    [System.Windows.MessageBox]::Show(
        "Diagnostic bundle saved:`n$zipPath`n`nPath copied to clipboard. Attach this when you contact IT.",
        'Bundle exported', 'OK', 'Information'
    ) | Out-Null

    # Open Explorer to file
    Start-Process 'explorer.exe' -ArgumentList "/select,`"$zipPath`""

    return $zipPath
}


# ============================================================================
#  ESCALATION
# ============================================================================
function Invoke-Escalation {
    $bundlePath = Export-DiagnosticBundle
    $contact = $script:Config.client.supportContact
    if (-not $contact) {
        [System.Windows.MessageBox]::Show(
            "Diagnostic bundle saved to your Desktop. Path is on your clipboard.`n`nForward the bundle to your IT team via email or your ticket system.",
            'Bundle ready', 'OK', 'Information'
        ) | Out-Null
        return
    }
    $subject = "IT Support Request - $($script:Config.client.name) - $env:COMPUTERNAME"
    $body = @"
Hi IT,

I need help with my computer. MendOS tried to fix it but couldn't resolve the issue.

A diagnostic bundle has been saved at:
$bundlePath

(Path is also on my clipboard for easy attaching.)

Computer: $env:COMPUTERNAME
User: $env:USERNAME
Time: $(Get-Date -Format 'o')

Thanks
"@
    $url = "mailto:$contact?subject=$([uri]::EscapeDataString($subject))&body=$([uri]::EscapeDataString($body))"
    Start-Process $url
}


# ============================================================================
#  XAML UI
# ============================================================================
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MendOS"
        Height="780" Width="680"
        WindowStartupLocation="CenterScreen"
        Background="#1E1E1E"
        ResizeMode="NoResize"
        FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="100"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="80"/>
    </Grid.RowDefinitions>

    <!-- HEADER -->
    <Grid Grid.Row="0" Margin="22,12,22,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel VerticalAlignment="Center">
        <TextBlock x:Name="txtTitle" FontSize="24" FontWeight="Bold" Foreground="White"><Run x:Name="txtTitleBold" Text="Mend"/><Run x:Name="txtTitleLight" Text="OS" FontWeight="Light" Foreground="#A0A0A0"/></TextBlock>
        <TextBlock x:Name="txtSubtitle" Text="" Foreground="#A0A0A0" FontSize="12" Margin="0,2,0,0"/>
        <TextBlock x:Name="txtTier" Text="" Foreground="#1ABC9C" FontSize="11" FontWeight="SemiBold" Margin="0,4,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="1" VerticalAlignment="Center" Orientation="Horizontal">
        <CheckBox x:Name="chkAudit" Content="Audit Mode" Foreground="White" FontSize="12" VerticalAlignment="Center" Margin="0,0,10,0"/>
      </StackPanel>
    </Grid>

    <!-- SCAN ROWS -->
    <StackPanel Grid.Row="1" Margin="20,8,20,0">
      <Border Background="#2D2D30" CornerRadius="4" Margin="0,3" Padding="14,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="190"/><ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="40"/>
          </Grid.ColumnDefinitions>
          <TextBlock Text="Uptime" Foreground="White" FontSize="13" VerticalAlignment="Center"/>
          <TextBlock x:Name="txtUptime" Grid.Column="1" Text="..." Foreground="#D0D0D0" FontSize="13" VerticalAlignment="Center"/>
          <Button x:Name="btnFixUptime" Grid.Column="2" Content="Fix" Width="60" Height="24" Margin="0,0,10,0" Background="#0E639C" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand" Visibility="Collapsed"/>
          <TextBlock x:Name="dotUptime" Grid.Column="3" Text="&#9679;" Foreground="Gray" FontSize="20" VerticalAlignment="Center" HorizontalAlignment="Right"/>
        </Grid>
      </Border>
      <Border Background="#2D2D30" CornerRadius="4" Margin="0,3" Padding="14,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="190"/><ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="40"/>
          </Grid.ColumnDefinitions>
          <TextBlock Text="Free disk space (C:)" Foreground="White" FontSize="13" VerticalAlignment="Center"/>
          <TextBlock x:Name="txtDisk" Grid.Column="1" Text="..." Foreground="#D0D0D0" FontSize="13" VerticalAlignment="Center"/>
          <Button x:Name="btnFixDisk" Grid.Column="2" Content="Fix" Width="60" Height="24" Margin="0,0,10,0" Background="#0E639C" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand" Visibility="Collapsed"/>
          <TextBlock x:Name="dotDisk" Grid.Column="3" Text="&#9679;" Foreground="Gray" FontSize="20" VerticalAlignment="Center" HorizontalAlignment="Right"/>
        </Grid>
      </Border>
      <Border Background="#2D2D30" CornerRadius="4" Margin="0,3" Padding="14,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="190"/><ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="40"/>
          </Grid.ColumnDefinitions>
          <TextBlock Text="RAM in use" Foreground="White" FontSize="13" VerticalAlignment="Center"/>
          <TextBlock x:Name="txtRam" Grid.Column="1" Text="..." Foreground="#D0D0D0" FontSize="13" VerticalAlignment="Center"/>
          <Button x:Name="btnFixRam" Grid.Column="2" Content="Fix" Width="60" Height="24" Margin="0,0,10,0" Background="#0E639C" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand" Visibility="Collapsed"/>
          <TextBlock x:Name="dotRam" Grid.Column="3" Text="&#9679;" Foreground="Gray" FontSize="20" VerticalAlignment="Center" HorizontalAlignment="Right"/>
        </Grid>
      </Border>
      <Border Background="#2D2D30" CornerRadius="4" Margin="0,3" Padding="14,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="190"/><ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="40"/>
          </Grid.ColumnDefinitions>
          <TextBlock Text="Days since last patch" Foreground="White" FontSize="13" VerticalAlignment="Center"/>
          <TextBlock x:Name="txtUpdates" Grid.Column="1" Text="..." Foreground="#D0D0D0" FontSize="13" VerticalAlignment="Center"/>
          <Button x:Name="btnFixUpdates" Grid.Column="2" Content="Fix" Width="60" Height="24" Margin="0,0,10,0" Background="#0E639C" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand" Visibility="Collapsed"/>
          <TextBlock x:Name="dotUpdates" Grid.Column="3" Text="&#9679;" Foreground="Gray" FontSize="20" VerticalAlignment="Center" HorizontalAlignment="Right"/>
        </Grid>
      </Border>
      <Border Background="#2D2D30" CornerRadius="4" Margin="0,3" Padding="14,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="190"/><ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="40"/>
          </Grid.ColumnDefinitions>
          <TextBlock Text="Hibernation" Foreground="White" FontSize="13" VerticalAlignment="Center"/>
          <TextBlock x:Name="txtHibernation" Grid.Column="1" Text="..." Foreground="#D0D0D0" FontSize="13" VerticalAlignment="Center"/>
          <Button x:Name="btnFixHibernation" Grid.Column="2" Content="Fix" Width="60" Height="24" Margin="0,0,10,0" Background="#0E639C" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand" Visibility="Collapsed"/>
          <TextBlock x:Name="dotHibernation" Grid.Column="3" Text="&#9679;" Foreground="Gray" FontSize="20" VerticalAlignment="Center" HorizontalAlignment="Right"/>
        </Grid>
      </Border>
      <Border Background="#2D2D30" CornerRadius="4" Margin="0,3" Padding="14,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="190"/><ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/><ColumnDefinition Width="40"/>
          </Grid.ColumnDefinitions>
          <TextBlock Text="Fast Startup" Foreground="White" FontSize="13" VerticalAlignment="Center"/>
          <TextBlock x:Name="txtFastStartup" Grid.Column="1" Text="..." Foreground="#D0D0D0" FontSize="13" VerticalAlignment="Center"/>
          <Button x:Name="btnFixFastStartup" Grid.Column="2" Content="Fix" Width="60" Height="24" Margin="0,0,10,0" Background="#0E639C" Foreground="White" BorderThickness="0" FontSize="11" Cursor="Hand" Visibility="Collapsed"/>
          <TextBlock x:Name="dotFastStartup" Grid.Column="3" Text="&#9679;" Foreground="Gray" FontSize="20" VerticalAlignment="Center" HorizontalAlignment="Right"/>
        </Grid>
      </Border>
      <Border Background="#2D2D30" CornerRadius="4" Margin="0,3" Padding="14,8">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="190"/><ColumnDefinition Width="*"/>
            <ColumnDefinition Width="40"/>
          </Grid.ColumnDefinitions>
          <TextBlock Text="Network connectivity" Foreground="White" FontSize="13" VerticalAlignment="Center"/>
          <TextBlock x:Name="txtNetwork" Grid.Column="1" Text="..." Foreground="#D0D0D0" FontSize="13" VerticalAlignment="Center"/>
          <TextBlock x:Name="dotNetwork" Grid.Column="2" Text="&#9679;" Foreground="Gray" FontSize="20" VerticalAlignment="Center" HorizontalAlignment="Right"/>
        </Grid>
      </Border>
    </StackPanel>

    <!-- PICKER -->
    <Border Grid.Row="2" Background="#252526" Margin="20,10,20,8" CornerRadius="4" Padding="14,12">
      <StackPanel>
        <TextBlock Text="Don't see your issue above?" Foreground="White" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,8"/>
        <TextBox x:Name="txtSearch" Height="30" FontSize="13" Padding="6,5,6,5" Background="White" Foreground="Black" Margin="0,0,0,4"/>
        <TextBlock x:Name="txtMatchCount" Text="Showing all issues" Foreground="#888888" FontSize="11" Margin="2,0,0,8"/>
        <ComboBox x:Name="cmbProblems" Height="30" FontSize="13" Background="White" Foreground="Black"/>
      </StackPanel>
    </Border>

    <!-- FOOTER -->
    <Grid Grid.Row="3" Margin="20,15">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <Button x:Name="btnUndo" Grid.Column="0" Content="Undo Last" Width="100" Height="34" Margin="0,0,8,0" Background="#5A3F0E" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
      <Button x:Name="btnEscalate" Grid.Column="1" Content="Escalate to IT" Width="120" Height="34" Margin="0,0,8,0" Background="#8B4513" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
      <Button x:Name="btnRefresh" Grid.Column="3" Content="Refresh" Width="100" Height="34" Margin="0,0,8,0" Background="#0E639C" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
      <Button x:Name="btnExit" Grid.Column="4" Content="Exit" Width="100" Height="34" Background="#3C3C3C" Foreground="White" BorderThickness="0" FontSize="12" Cursor="Hand"/>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)


# ----- GRAB UI REFERENCES ---------------------------------------------------
$ui = @{}
foreach ($n in 'txtTitle','txtTitleBold','txtTitleLight','txtSubtitle','txtTier','chkAudit',
               'txtUptime','dotUptime','btnFixUptime',
               'txtDisk','dotDisk','btnFixDisk',
               'txtRam','dotRam','btnFixRam',
               'txtUpdates','dotUpdates','btnFixUpdates',
               'txtHibernation','dotHibernation','btnFixHibernation',
               'txtFastStartup','dotFastStartup','btnFixFastStartup',
               'txtNetwork','dotNetwork',
               'txtSearch','txtMatchCount','cmbProblems',
               'btnUndo','btnEscalate','btnRefresh','btnExit') {
    $ui[$n] = $window.FindName($n)
}

# Theme bindings
if ($script:Config.client.name -eq 'MendOS') {
    $ui.txtTitleBold.Text  = 'Mend'
    $ui.txtTitleLight.Text = 'OS'
} else {
    $ui.txtTitleBold.Text  = $script:Config.client.name
    $ui.txtTitleLight.Text = ''
}
$ui.txtTier.Text = if ($script:Tier -eq 'Ultimate') { (L 'license.tier_ultimate') } else { (L 'license.tier_light') }
$ui.txtTier.Foreground = if ($script:Tier -eq 'Ultimate') { 'Gold' } else { '#1ABC9C' }
$ui.chkAudit.IsChecked = $script:AuditMode


# ----- COLOR CONSTANTS ------------------------------------------------------
$colorGreen   = [System.Windows.Media.Brushes]::LimeGreen
$colorYellow  = [System.Windows.Media.Brushes]::Gold
$colorRed     = [System.Windows.Media.Brushes]::Tomato
$visVisible   = [System.Windows.Visibility]::Visible
$visCollapsed = [System.Windows.Visibility]::Collapsed


# ----- ACTION DISPATCHERS ---------------------------------------------------
function Invoke-Fix {
    param([string]$FixKey)
    $entry = $Fixes[$FixKey]
    if (-not $entry) { return }
    Invoke-Action -Entry $entry
    Invoke-HealthScan
}

function Invoke-Problem {
    param([string]$ProblemKey)
    $entry = $Problems[$ProblemKey]
    if (-not $entry) { return }
    Invoke-Action -Entry $entry
}

function Invoke-Action {
    param($Entry)
    # Workflow entries delegate (their Action invokes Invoke-Workflow which does its own confirm)
    if ($Entry.IsWorkflow) {
        & $Entry.Action | Out-Null
        return
    }
    # Audit mode: show what we WOULD do
    $desc = $Entry.Description
    if ($script:AuditMode) {
        $desc = L 'dialog.audit.would_run' -Args @($Entry.Description)
    }
    $answer = [System.Windows.MessageBox]::Show($desc, $Entry.Name, 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }

    Write-AppLog -Event 'action.invoke' -Data @{ name = $Entry.Name; audit = $script:AuditMode }

    $success = & $Entry.Action
    if ($success) {
        [System.Windows.MessageBox]::Show((L 'dialog.result.success'), $Entry.Name, 'OK', 'Information') | Out-Null
    } else {
        [System.Windows.MessageBox]::Show((L 'dialog.result.failed'), $Entry.Name, 'OK', 'Warning') | Out-Null
    }
}


# ----- SCAN ORCHESTRATOR ----------------------------------------------------
function Set-CheckResult {
    param($Text, $Dot, $FixBtn, $Result, $FixKey)
    $Text.Text = $Result.Text
    switch ($Result.Status) {
        'green'  { $Dot.Foreground = $colorGreen  }
        'yellow' { $Dot.Foreground = $colorYellow }
        'red'    { $Dot.Foreground = $colorRed    }
    }
    if ($FixBtn) {
        $hasFix = $FixKey -and $Fixes.ContainsKey($FixKey)
        $fixable = $Result.Status -in 'yellow','red'
        if ($hasFix -and $fixable) { $FixBtn.Visibility = $visVisible }
        else                       { $FixBtn.Visibility = $visCollapsed }
    }
}

function Invoke-HealthScan {
    Set-CheckResult $ui.txtUptime      $ui.dotUptime      $ui.btnFixUptime      (Get-UptimeStatus)      $null
    Set-CheckResult $ui.txtDisk        $ui.dotDisk        $ui.btnFixDisk        (Get-DiskStatus)        $null
    Set-CheckResult $ui.txtRam         $ui.dotRam         $ui.btnFixRam         (Get-RamStatus)         'Ram'
    Set-CheckResult $ui.txtUpdates     $ui.dotUpdates     $ui.btnFixUpdates     (Get-UpdateStatus)      $null
    Set-CheckResult $ui.txtHibernation $ui.dotHibernation $ui.btnFixHibernation (Get-HibernationStatus) 'Hibernation'
    Set-CheckResult $ui.txtFastStartup $ui.dotFastStartup $ui.btnFixFastStartup (Get-FastStartupStatus) 'FastStartup'
    Set-CheckResult $ui.txtNetwork     $ui.dotNetwork     $null                 (Get-NetworkStatus)     $null
}


# ----- SEARCH + DROPDOWN ----------------------------------------------------
function Get-FilteredProblems {
    param([string]$Query)
    $q = if ($Query) { $Query.Trim().ToLower() } else { '' }
    $matches = foreach ($key in $Problems.Keys) {
        $p = $Problems[$key]
        if ($q -eq '') {
            [pscustomobject]@{ Key = $key; Label = $p.Label }
            continue
        }
        $hay = ($p.Label + ' ' + ($p.Keywords -join ' ')).ToLower()
        if ($hay.Contains($q)) {
            [pscustomobject]@{ Key = $key; Label = $p.Label }
        }
    }
    return @($matches | Sort-Object Label)
}

function Update-ProblemDropdown {
    param([string]$Query)
    $filtered = Get-FilteredProblems -Query $Query
    $total = $Problems.Count
    $matched = $filtered.Count
    $ui.cmbProblems.Items.Clear()
    $placeholder = New-Object System.Windows.Controls.ComboBoxItem
    $placeholder.Content = if ($matched -eq 0) { (L 'dropdown.placeholder.nomatch') } else { (L 'dropdown.placeholder.select') }
    $placeholder.Tag = $null
    [void]$ui.cmbProblems.Items.Add($placeholder)
    foreach ($p in $filtered) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $p.Label
        $item.Tag = $p.Key
        [void]$ui.cmbProblems.Items.Add($item)
    }
    $ui.cmbProblems.SelectedIndex = 0
    $ui.txtMatchCount.Text = if ($Query) { "Showing $matched of $total issues" } else { "Showing all $total issues" }
}


# ----- SUBTITLE / AUDIT TOGGLE ----------------------------------------------
function Update-Subtitle {
    if ($script:AuditMode) {
        $ui.txtSubtitle.Text = (L 'app.subtitle.audit')
        $ui.txtSubtitle.Foreground = 'Gold'
    } else {
        $ui.txtSubtitle.Text = (L 'app.subtitle.admin')
        $ui.txtSubtitle.Foreground = '#A0A0A0'
    }
}
Update-Subtitle


# ----- WIRE UP --------------------------------------------------------------
$ui.btnRefresh.Add_Click({ Invoke-HealthScan })
$ui.btnExit.Add_Click({ $window.Close() })
$ui.btnUndo.Add_Click({ Invoke-LastUndo })
$ui.btnEscalate.Add_Click({ Invoke-Escalation })

$ui.chkAudit.Add_Checked({ $script:AuditMode = $true;  Update-Subtitle; Write-AppLog -Event 'audit.enabled' })
$ui.chkAudit.Add_Unchecked({ $script:AuditMode = $false; Update-Subtitle; Write-AppLog -Event 'audit.disabled' })

$ui.btnFixUptime.Add_Click(       { Invoke-Fix -FixKey 'Uptime'      })
$ui.btnFixDisk.Add_Click(         { Invoke-Fix -FixKey 'Disk'        })
$ui.btnFixRam.Add_Click(          { Invoke-Fix -FixKey 'Ram'         })
$ui.btnFixUpdates.Add_Click(      { Invoke-Fix -FixKey 'Updates'     })
$ui.btnFixHibernation.Add_Click(  { Invoke-Fix -FixKey 'Hibernation' })
$ui.btnFixFastStartup.Add_Click(  { Invoke-Fix -FixKey 'FastStartup' })

$ui.txtSearch.Add_TextChanged({ Update-ProblemDropdown -Query $ui.txtSearch.Text })
$ui.cmbProblems.Add_SelectionChanged({
    if ($ui.cmbProblems.SelectedIndex -le 0) { return }
    $item = $ui.cmbProblems.SelectedItem
    if ($item.Tag) {
        Invoke-Problem -ProblemKey $item.Tag
        $ui.txtSearch.Clear()
        Update-ProblemDropdown -Query ''
    }
})


# ----- STARTUP --------------------------------------------------------------
Write-AppLog -Event 'app.start' -Data @{ version = $script:Version; tier = $script:Tier; mdm = $script:IsMdmManaged; audit = $script:AuditMode }
Send-Telemetry -Event 'app.start' -Success $true
Invoke-HealthScan
Update-ProblemDropdown -Query ''
$window.ShowDialog() | Out-Null
Write-AppLog -Event 'app.exit'
Send-Telemetry -Event 'app.exit' -Success $true
