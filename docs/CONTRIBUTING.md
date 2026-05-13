# Contributing to FRNTZN H3L1OS

Thanks for considering a contribution. This document is short and direct.

## What we want

- **Bug reports** with clear repro steps.
- **New fixes** in the `$Fixes` or `$Problems` registry following the existing pattern.
- **New workflows** in `$Workflows` with verified steps.
- **Translations** of `strings/en.json` into new languages.
- **Documentation improvements**.

## What we don't want (without discussion first)

- Architectural rewrites.
- New dependencies (this is a self-contained PowerShell + bash project; we don't want runtime fetching of NuGet, npm, or Homebrew packages).
- Code that touches AMSI.
- Code that disables Windows Defender, BitLocker, or other security features.
- "Optimizations" that disable Windows Update by default.

## How to add a new fix

Open `src/windows/h3l1os.ps1`. Find the `$Problems` hashtable. Add an entry:

```powershell
'category.your-fix-id' = @{
    Label       = 'User-facing description in plain English'
    Keywords    = @('keyword1','keyword2','synonyms','for','search')
    Name        = 'Title for confirmation dialog'
    Description = "Multi-line description of what will happen.`n`nProceed?"
    Action      = {
        if ($script:AuditMode) { return $true }
        # Your fix code here.
        # If it writes to the registry, use Set-RegistryValueSafe.
        # If it changes system state, register an undo with Add-UndoEntry first.
        return $true
    }
}
```

Then add the Mac equivalent in `src/mac/h3l1os.sh`:

```bash
fix_desc_your_fix_id() { echo "Description\n\nProceed?"; }
fix_your_fix_id() {
    $AUDIT_MODE && return 0
    # Your fix code here.
    # If it needs sudo, use osa_sudo "command".
    return 0
}
```

Add it to the `PROBLEMS` array:

```bash
"User-facing description||keywords for search||your_fix_id"
```

## How to add a workflow (Ultimate tier)

Workflows are multi-step procedures with state threading. Open the `$Workflows` hashtable in `h3l1os.ps1`:

```powershell
'your-workflow-id' = @{
    Name         = 'Display name'
    Description  = "What this workflow does, with step list.`n`nProceed?"
    UltimateOnly = $true   # set to $false if it should be free
    Steps        = @(
        @{
            Label  = 'Step 1 description'
            Action = {
                param($State)
                # State is shared across steps. Read/write freely.
                # Return @{ Success = $bool; Message = 'string' }
                return @{ Success = $true; Message = 'OK' }
            }
        }
        # ... more steps
    )
}
```

## Translation

Copy `strings/en.json` to `strings/<lang>.json` (e.g. `strings/fr.json`). Translate every value. Keep keys identical. Submit PR.

We prioritize languages by call-center/BPO market size:
1. Spanish (LATAM, Mexico, Philippines)
2. Tagalog (Manila)
3. Hindi (Bangalore/Hyderabad/Noida)
4. Portuguese-Brazil

## Code style

- PowerShell: follow the existing style. Verb-Noun function names. `$script:` for module-scoped state. CIM not WMI. Foreach statements over pipeline where performance matters.
- Bash: POSIX-friendly where possible. Bash 3.2+ (the macOS default). No `set -e` for the main loop — we handle errors per-action.
- Comments: explain *why*, not *what*. The code already says what.

## Pull requests

1. Fork the repo.
2. Create a feature branch.
3. Add or modify code following the patterns above.
4. Test locally (run the tool, exercise the new feature).
5. Open a PR with a clear description of the change and why.

We try to review within 7 days.

## Reporting security issues

**Do not** open a public issue for security problems. Email **security@frntzn.dev** or use GitHub's private security advisory feature.
