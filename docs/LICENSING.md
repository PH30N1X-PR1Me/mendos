# Licensing & Tiers

FRNTZN H3L1OS uses a **freemium model**:

- **Light** — free, MIT-licensed. Everything you need for self-service IT.
- **Ultimate** — paid, commercial license. Multi-step workflows, localization, MDM-awareness, MSP branding, ITSM integrations.

## How the license check works (and why it fails open)

When the tool starts, it makes a 5-second HTTPS call to `https://license.frntzn.dev/v1/check` with your license key (from the `FRNTZN_KEY` environment variable). The response looks like:

```json
{ "tier": "Light" }
```

or

```json
{ "tier": "Ultimate" }
```

The result is cached locally for 14 days at `%LOCALAPPDATA%\frntzn\license.cache.json` (Win) or `~/Library/Application Support/FRNTZN/license.cache.json` (Mac).

**If the network call fails for any reason** — captive portal, firewall, server down — the tool **falls open to Light tier**. We chose this over locking out legitimate users. The trade-off: brief tier downgrades during outages.

## v1.0 status: stub

The endpoint above currently returns `{"tier":"Light"}` for everyone. There is no payment integration yet. The infrastructure for swapping it is one line.

When we wire up Lemon Squeezy (the planned backend, post Stripe acquisition in 2024), the swap is:

```powershell
# in h3l1os.ps1
$script:LicenseUrl = 'https://api.lemonsqueezy.com/v1/licenses/validate'
```

…plus a small adjustment to the request body. The license-cache, fail-open, tier-gating logic stays identical.

## Why we picked this architecture

- **No DRM, no obfuscation.** A $29 product doesn't justify enterprise-grade anti-piracy. Honor system + low price + good product is the model (CleanMyMac, Sublime Text, 1Password).
- **Per-machine hash check.** The license is bound to a SHA-256 hash of the machine's SID/UUID, never to the raw identifier. Hash on the client side; only the hash is transmitted.
- **Offline grace.** 14 days. Enough for travel, captive portals, transient network issues. Not enough for indefinite piracy.
- **Light is genuinely free, not crippleware.** The free tier is a real product that solves real problems. The paid tier is for organizations that need workflows, branding, integrations.

## Buying Ultimate

(Coming soon.) Subscription will be ~$29–49/year per user, or volume-licensed for MSPs. Until then, run the Light tier — it's free, MIT-licensed, and covers the most common 80% of IT tickets.

If you're an MSP/IT team interested in early access to Ultimate (including custom config.json branding for your clients), email **hello@frntzn.dev**.

## What about source visibility?

The script is open source. That means the Ultimate tier code is also visible. We accept this. Patterns we deliberately don't use:

- ❌ Encrypted blob in the script decrypted at runtime by a server-returned key (CCleaner-class supply-chain risk).
- ❌ Per-client compiled binaries (forks the codebase, hurts users).
- ❌ Server-side execution of "premium" features (defeats the irm|iex zero-install model).

The Ultimate code being inspectable is a feature, not a bug. It builds trust. Anyone determined enough can pirate it; that audience is not our customer.

Last updated: 2026-05-12
