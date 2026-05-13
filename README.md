# FRNTZN H3L1OS

> Self-service IT diagnostic & remediation tool for Windows and macOS.
> One-line install. Vendor-neutral. Open source.

[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-blue)]()
[![macOS](https://img.shields.io/badge/macOS-12%2B-blue)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()
[![Version](https://img.shields.io/badge/version-1.0.0-orange)]()

---

## What it does

FRNTZN H3L1OS is a free, open-source tool that helps non-technical users diagnose and fix common IT problems on their own — DNS issues, audio glitches, Bluetooth pairing, slow performance, browser cache problems, MFA loops, printer offline, and more — without waiting for IT.

Built for call centers, BPOs, MSPs, and anyone who runs IT support at scale. Particularly tuned for **low-end hardware** (Celeron N4500-class machines with 4–8 GB RAM) where every gram of optimization matters.

## Quick start

### Windows (PowerShell)

```powershell
irm 'https://raw.githubusercontent.com/PH30N1X-PR1Me/frntzn-h3l1os/v1.0.0/src/windows/h3l1os.ps1' | iex
```

UAC will prompt for elevation. After that, the tool runs.

### macOS (Terminal)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/PH30N1X-PR1Me/frntzn-h3l1os/v1.0.0/src/mac/h3l1os.sh)"
```

You'll be prompted for your admin password only when a fix needs it.

*Hybrid hosting: scripts on GitHub raw (versioned, auditable), license + telemetry API on Cloudflare Worker. See [`cloudflare/DEPLOY.md`](cloudflare/DEPLOY.md).*

## Features

| | Light (free) | Ultimate ($29–49/yr) |
|---|:---:|:---:|
| Health scan (CPU, RAM, disk, network, updates) | ✅ | ✅ |
| Single-shot fixes (DNS flush, audio reset, etc.) | ✅ | ✅ |
| Problem picker with smart search | ✅ | ✅ |
| Audit mode (preview without changes) | ✅ | ✅ |
| Undo last action | ✅ | ✅ |
| Diagnostic bundle export for IT | ✅ | ✅ |
| Multi-step verified workflows | — | ✅ |
| Low-end system optimization | — | ✅ |
| Network stack reset | — | ✅ |
| Multi-language (es, tl, hi) | — | ✅ |
| Custom branding via config.json | — | ✅ |
| MDM/Group Policy awareness | — | ✅ |
| ITSM integrations (Freshdesk/Zendesk/ServiceNow) | — | ✅ |

## What it covers

12 categories of common IT issues:

1. **Identity / SSO / MFA** — Okta loops, MFA push not arriving, account locked
2. **Audio** — Logitech double-mute, no sound, mic not working
3. **Communication apps** — Slack blank, Zoom crash, Teams login loop
4. **Browser** — Chrome cache, Edge cache, slow pages
5. **Network** — DNS failures, WiFi disconnects
6. **Hardware** — Bluetooth, camera, USB
7. **Performance** — slow startup, low-end optimization, high RAM
8. **Updates** — stuck installs, reset Windows Update
9. **Display** — external monitors not detected
10. **Email** — Outlook stuck syncing
11. **Print** — spooler crashed, "offline" stuck
12. **OS / Account / Profile** — sign-in, storage cleanup

## Security & trust

This tool runs with admin privileges and modifies system state. **Read [SECURITY.md](docs/SECURITY.md) before running it on a managed corporate machine.**

Highlights:
- **Open source.** Every line readable. No obfuscation, no Base64 blobs.
- **AMSI stays on.** We never disable, bypass, or manipulate Windows Defender.
- **Every change is reversible.** Undo registry tracks every modification.
- **Restore point before risky workflows** (Windows).
- **No telemetry by default.** Opt-in only. Strictly local logs.
- **No keylogging, clipboard reading, or credential capture. Ever.**
- **Policy-aware.** Refuses to override settings managed by Group Policy or MDM.

## For MSPs / IT teams

Deploy with custom branding via `config.json`:

```json
{
  "client": {
    "name": "Acme IT Helpdesk",
    "supportContact": "ithelp@acme.example",
    "ticketSystemUrl": "https://acme.freshservice.com/support/tickets/new"
  },
  "environment": {
    "ssoProvider": "okta",
    "ssoUrl": "https://acme.okta.com",
    "managedByMdm": true
  }
}
```

Place at `~/.frntzn/config.json` or pass via `FRNTZN_CONFIG=path` environment variable.

See [`examples/`](examples/) for full examples.

## Verifying download integrity

For every release, we publish a SHA-256 hash:

```powershell
# Windows
$expected = 'abc123...'  # from release page
$actual = (Get-FileHash 'h3l1os.ps1' -Algorithm SHA256).Hash
if ($actual -eq $expected) { 'verified' } else { 'TAMPERED' }
```

```bash
# macOS
shasum -a 256 -c h3l1os.sh.sha256
```

## License

MIT for the Light tier code. Ultimate tier features are commercial. Both ship in the same script; the Ultimate features are gated by a license stub that you can read in [`docs/LICENSING.md`](docs/LICENSING.md).

## Roadmap

- v1.0 — Windows + Mac, 12-category coverage, freemium stub, audit + undo
- v1.1 — ITSM integrations, scheduled scans, Spanish localization
- v2.0 — Microsoft Store distribution, code signing via Azure Trusted Signing

## Contributing

Pull requests welcome. Please read [CONTRIBUTING.md](docs/CONTRIBUTING.md).

## Why this exists

Most IT support tickets are repetitive — DNS flush, restart audio, clear cache, sign in again. FRNTZN H3L1OS lets people fix those themselves, in seconds, without filing a ticket. IT teams get to focus on the hard stuff. Users get unstuck faster.

Built originally to support Remedy Meds call-center operations. Now generalized.
