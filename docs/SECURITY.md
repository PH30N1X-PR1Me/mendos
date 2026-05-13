# Security Policy & Transparency

MendOS runs with administrator privileges and modifies system state. This document is our commitment to you about what it does and doesn't do.

## Guarantees

1. **Open source, commit-pinned.** Every release links to its exact Git commit SHA. You can audit any line of code.
2. **No telemetry by default.** Strictly local logs. No data leaves your machine unless you click "Export Diagnostic Bundle" or "Escalate to IT", and even then it's saved to your Desktop for you to attach manually.
3. **No keylogging.** Code can be grep'd for `Get-Clipboard`, `SetWindowsHookEx`, `Get-Credential` — there are zero such calls outside explicit, user-clicked actions.
4. **No clipboard reading**, no screen capture, no credential harvesting.
5. **No obfuscation.** Every line is readable PowerShell or bash. No Base64 blobs decoded at runtime. No `iex` on user input.
6. **AMSI never disabled.** Every documented PowerShell AMSI bypass technique is a malware-defense-evasion pattern. We refuse to use any of them. If Defender false-positives a string, we'll rename the variable and submit an FP report to Microsoft — we will never disable AMSI.
7. **Every change is reversible.** Before any registry write, we capture the old value and register an undo action in `%LOCALAPPDATA%\frntzn\undo\` (Win) or `~/Library/Application Support/FRNTZN/undo/` (Mac). The Undo Last button restores it.
8. **Restore point before risky workflows.** On Windows, multi-step workflows create a System Restore Point first (where Windows allows; Windows throttles to 1 per 24 hours).
9. **Policy-aware.** We check `HKLM:\SOFTWARE\Policies\*` and `HKLM:\SOFTWARE\Microsoft\PolicyManager\*` before any state-mutating fix. If your IT department has locked a setting, we refuse to override it and tell you to contact your administrator.
10. **No third-party runtime downloads.** Everything ships in the script or in versioned, hash-verified GitHub release assets. No `Invoke-Expression` on remote content during a session.

## What we MUST NOT do (bright lines)

- ❌ No bundled adware or partner offers.
- ❌ No fake "registry error" or "PC speed" counts to push paid upgrades.
- ❌ No silent data collection.
- ❌ No PII-bearing telemetry without explicit consent.
- ❌ No embedded API keys or secrets that, if extracted, access user accounts elsewhere.
- ❌ No fixes that disable Windows Update or security patches by default (Ultimate-tier double-confirm acceptable for advanced users only).
- ❌ No coupling support payment to ability to undo changes. **Undo always works in the free Light tier.**
- ❌ No DRM-style anti-tamper that makes legitimate forensic inspection harder.

## Cautionary tale: CCleaner (2017)

In August–September 2017, Piriform's CCleaner versions 5.33 and 5.34 — distributed with a **valid Piriform/Avast code-signing certificate** — were compromised at the build server. Approximately 2.27 million users on 32-bit Windows downloaded signed malware. The attack went undetected for four weeks.

Lessons we apply:

- **Code signing is necessary but not sufficient.** A compromised build server signs malware with valid certs.
- **Reproducible builds + commit pinning** beat trust-in-vendor. Anyone can verify our releases byte-for-byte against the source commit.
- **Restricted release branch.** Only repo owners can push to `main`. Signed commits + 2-of-2 review for release tags.
- **No silent auto-update.** We notify, link to the changelog, and let you decide. CCleaner's update mechanism was the delivery vehicle.
- **Transparency reports.** Every release we publish: commit SHA, SHA-256 of the released file, changelog. See [`releases/`](https://github.com/PH30N1X-PR1Me/frntzn-h3l1os/releases).

## Verification

Each release page on GitHub publishes:

- Commit SHA the release was built from.
- SHA-256 hash of `h3l1os.ps1` and `h3l1os.sh`.
- Signed `.sha256` checksum file.

To verify a download:

```powershell
# Windows
$expected = 'paste-from-release-page'
$actual = (Get-FileHash 'h3l1os.ps1' -Algorithm SHA256).Hash
if ($actual -eq $expected) { 'OK' } else { 'FAIL - do not run' }
```

```bash
# macOS
shasum -a 256 h3l1os.sh
# Compare manually with the value on the release page
```

## Reporting vulnerabilities

Email **security@frntzn.dev** (or open a private security advisory on GitHub). We commit to:

- Acknowledge within 48 hours.
- Patch within 7 days for critical issues.
- Publish a CVE if applicable.
- Credit the reporter in the changelog (unless they decline).

## License & liability

This software is provided **AS IS**, without warranty. Read the MIT license. We strongly recommend running in **Audit Mode first** on any machine you don't own.

Last updated: 2026-05-12
