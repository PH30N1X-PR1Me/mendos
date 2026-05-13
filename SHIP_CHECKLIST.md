# Ship It Checklist - FRNTZN H3L1OS v1.0.0

You now have a complete v1.0 product. Here's what's in your hands and what to do next.

## What's in the box

```
frntzn-h3l1os/
├── README.md                         # Public-facing README
├── LICENSE                           # MIT for Light tier
├── config/
│   └── config.default.json           # Vendor-neutral default
├── src/
│   ├── windows/
│   │   └── h3l1os.ps1               # Main Windows entry (PowerShell + WPF)
│   └── mac/
│       └── h3l1os.sh                # Main Mac entry (bash + AppleScript)
├── strings/
│   ├── en.json                      # English (master)
│   └── es.json                      # Spanish (LATAM/Philippines BPO market)
├── examples/
│   └── config.remedy-meds.json      # MSP/client customization example
└── docs/
    ├── SECURITY.md                  # Trust & transparency
    ├── LICENSING.md                 # Freemium model explained
    └── CONTRIBUTING.md              # How others can help
```

## Architecture recap

The whole product is three registries plus cross-cutting concerns:

- **$Fixes** — single-shot remediations triggered by Fix buttons
- **$Problems** — user-pickable issues from the dropdown (with search + keywords)
- **$Workflows** — multi-step verified procedures (Ultimate tier)

Plus:

- Smart elevation (both file-on-disk and `irm | iex` paths)
- Pluggable `config.json` (defaults → user override → env override → CLI)
- Localization scaffolding (en + es shipped; tl, hi, pt-BR ready slots)
- License stub (HTTP call, 14-day cache, fails open to Light)
- Audit mode (preview without changes)
- Undo registry (per-action rollback)
- MDM/Group Policy detection (refuses to override locked settings)
- Diagnostic bundle export
- Escalation to IT (mailto + clipboard path)
- JSON structured logging
- Restore Point creation (Windows)

## Coverage

12 categories, 22 problems, 3 fixes, 2 workflows in v1.0:

Identity (Okta MFA, account locked), Audio (no output, mic, Logitech double-mute), Comms (Slack, Zoom, Teams), Browser (Chrome, Edge), Network (DNS, WiFi), Hardware (Bluetooth, camera), Performance (slow, startup), Updates (check, reset), Display (external monitor), Email (Outlook), Print (spooler), OS (PIN setup, storage cleanup).

## What to do next (in order)

### 1. Create the GitHub repo

- Make a public repo named `frntzn-h3l1os` (or your chosen name) on GitHub.
- Upload the entire `frntzn-h3l1os/` folder contents.
- Make `main` your default branch.
- Enable branch protection: require PRs, require 1 review.

### 2. Update the URLs in the script

Find and replace `PH30N1X-PR1Me` in:
- `src/windows/h3l1os.ps1` line 32 (`$script:ScriptUrl`)
- `src/mac/h3l1os.sh` line 19 (`H3L1OS_SCRIPT_URL`)
- `README.md` (both quick-start lines)

Commit the change.

### 3. Tag the v1.0.0 release

```bash
git tag -a v1.0.0 -m "FRNTZN H3L1OS v1.0.0 - initial release"
git push origin v1.0.0
```

Create a GitHub Release from the tag. Attach SHA-256 hashes:

```bash
shasum -a 256 src/windows/h3l1os.ps1 > h3l1os.ps1.sha256
shasum -a 256 src/mac/h3l1os.sh > h3l1os.sh.sha256
```

Upload both `.sha256` files to the release.

### 4. Test the one-liner

On a Windows machine:
```powershell
irm 'https://raw.githubusercontent.com/PH30N1X-PR1Me/frntzn-h3l1os/main/src/windows/h3l1os.ps1' | iex
```

On a Mac:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/PH30N1X-PR1Me/frntzn-h3l1os/main/src/mac/h3l1os.sh)"
```

### 5. Drop it on Notion

Create a Notion page titled "FRNTZN H3L1OS" with:
- The one-liner as a code block
- A link to your GitHub repo
- A link to the SECURITY.md doc
- A short "What it does" blurb

### 6. Tell people

- Post on your LinkedIn with a screenshot and the one-liner.
- Submit to Hacker News (Show HN).
- Cross-post to r/sysadmin, r/PowerShell, r/MSP.
- Tag the repo on GitHub topics: `it-support`, `powershell`, `macos`, `troubleshooting`, `msp`, `call-center`, `bpo`, `okta`, `system-administration`.

### 7. Set up the license stub endpoint (when you're ready)

For now, the license URL in the script returns `{"tier":"Light"}` for everyone via a placeholder. Two paths when you want to start selling Ultimate:

**Quickest (15 minutes):** Create a tiny GitHub Pages site at `frntzn.github.io/license` with a static `check` endpoint returning JSON. Map your beta-tester keys via redirect rules.

**Real (1-2 days):** Sign up for Lemon Squeezy (Stripe-owned, 5% + $0.50 per transaction, handles VAT). Use their license-key API. Update `$script:LicenseUrl` in `h3l1os.ps1`. Done.

## What's NOT done yet (deliberate)

These are Phase 2 items per the research dossier — pull forward as customers demand:

- ITSM webhook integrations (Freshdesk, Zendesk, ServiceNow). Stubs are designed; implementation is one connector per integration.
- Runspace-based async scan (current scan blocks the UI for ~1-2 seconds on low-end hardware; acceptable for v1).
- Spanish/Tagalog/Hindi translation completion (es scaffolding is there, file is half-translated as example).
- Auto-update mechanism.
- Code signing (defer until Azure Trusted Signing eligibility — US/Canada org with 3+ years history).
- Microsoft Store MSIX submission.
- Homebrew Cask tap.

## Known limitations

- **`irm | iex` model trades convenience for tamper risk.** Mitigation: SHA-256 hash on release page, commit-pinned tag URLs, transparency doc. Future: code signing.
- **License stub fails open.** A user behind a permanent captive portal could run Ultimate features without paying after they cancel. This is intentional — we don't punish legitimate users for network issues. The 14-day grace + per-machine hash binding deter casual piracy.
- **Mac side is leaner than Windows.** AppleScript dialogs don't compose like WPF. The native experience is menu-driven loops rather than a single dashboard window. To get parity, future versions can compile an Automator app or ship a swiftDialog-based UI.
- **No driver/battery/thermal diagnostic in v1.** The research dossier lists them; they need per-vendor hardware probing that's out of scope for first ship.

## You shipped a real product

Two days ago this was a single PowerShell file checking 6 things. Now it's a documented, cross-platform, vendor-neutral, freemium, open-source IT support tool with a real architecture other people can extend. **Ship it.**
