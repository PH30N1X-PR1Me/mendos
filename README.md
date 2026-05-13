# MendOS

### Mend your OS. One paste. One window. Most problems gone.

```powershell
irm 'https://mendos.heliosprima.com/win' | iex
```

```bash
/bin/bash -c "$(curl -fsSL https://mendos.heliosprima.com/mac)"
```

A [Helios Prima](https://heliosprima.com) product.

---

## Why this exists

Your computer broke. Right when you didn't have time for it. The audio cuts mid-meeting. WiFi drops for the third time today. The printer pretends it's offline but the green light is right there. Slack is frozen. Okta wants you to verify again, even though you literally just did.

You're not a computer person. You shouldn't have to be. But here you are, calling someone.

If you work somewhere with IT, you call IT. You wait on hold. When they pick up, you spend ten minutes trying to describe a screen they can't see and they ask you to right-click things and you can't tell which right is right. If you don't have IT, you call your son who lives in another state, or the tech-savvy friend you feel bad about bothering, or the 1-800 number on the back of the laptop where someone reads a script.

Most of the time, the actual fix is one or two commands. They take thirty seconds to run. The person on the other end of the phone has the playbook memorized. You don't. That gap is the whole problem.

MendOS is the playbook in a window with buttons. Paste one line, a scanner runs, it tells you in plain words what's wrong, you click Fix. Most of the time it just works. When it doesn't, the tool builds a clean diagnostic bundle so the person you eventually call has something useful to look at.

## The name

Mend is what you do to something that's broken. OS is your operating system. The logo is bionic: **Mend** in bold, OS in lighter weight. Like two strands of a helix that hold the structure together. When one strand breaks, MendOS finds the broken part and stitches it back.

Pronounced *mend-OH-S*. Built by [FR4NTZ0N](https://github.com/fr4ntz0n). Shipped under [Helios Prima](https://heliosprima.com).

## Who it's for

**Parents and grandparents.** You don't have to feel bad about calling your kid for the fourth time this month. Paste the line. Pick the problem. Click Fix. If something goes weird, MendOS exports a zip your kid can actually open and figure out.

**Students and freelancers.** Your laptop is everything. School, income, social life, the 2am panic before a deadline when Chrome won't load. IT isn't open. You need it working now. Free, no install, no signup, no account.

**Small business owners running shops without an IT team.** You ARE the IT team, except you also have a business to run. Stop spending Saturday morning on what should be a five-minute click.

**IT pros running help desks.** You know what your queue looks like. The same fifty problems, every week, in slightly different costumes. You have real work to do. Give this to your users with your branding on it and watch the queue drop.

## Where this came from

I work in tech support. I started as a regular agent. Not the most technical person on the floor, but I was good at keeping users calm when they were frustrated. That got me promoted into the technical role, not because I knew more than the people next to me, but because I could talk to anyone without making them feel stupid.

The job put me in a spot where I was fixing things I barely understood myself, walking users through PowerShell commands while they were already stressed and short on patience. Clear cache. Flush DNS. Restart spooler. Try explaining how to open PowerShell as administrator to someone who has never seen a black window with white text on it. They feel dumb. You feel useless. The actual fix takes thirty seconds. The call takes thirty minutes.

I built MendOS so the people I was helping could help themselves. Then I realized the same script could help anyone with the same problems, anywhere, not just the agents on my floor. So here it is. Open source. Free for personal use. Built to keep growing.

## What it does today

One paste, one window, one click per fix.

**Health scan.** Seven checks on Windows, six on Mac, runs in about two seconds. Uptime, free disk, RAM pressure, days since last patch, network, hibernation state, fast startup. Each row gets a green / yellow / red dot so you can see at a glance what's healthy and what isn't.

**22 single-shot fixes across 12 categories.** DNS flush. Audio service reset. Bluetooth restart. Print spooler restart. Browser cache clears. Slack / Zoom / Teams reset. Okta MFA helper. Performance tuning for older machines. External monitor re-detection. Outlook profile repair. WiFi adapter cycle. More.

**Search the problem picker as you type.** Don't see your issue in the dropdown? Type something like "headphones" or "stuck" or "frozen" or "won't connect" and you get live matches across all 22 problems with a counter that updates as you type.

**Audit Mode.** Flip the toggle in the header. The tool runs every check but disables the Fix buttons. You see what *would* happen, without it happening. Use it the first time you run the tool, if you want to learn what's there before you start clicking.

**Undo Last.** Every fix that changes a setting registers its reverse. One click reverts the last action. The undo log persists between launches.

**Escalate to IT.** When a fix doesn't work, click Escalate. The tool zips up your system info, recent log entries, what was tried, what failed. Drops the zip on your Desktop and opens an email pre-addressed to your support contact with the zip path on your clipboard. The hardest part of asking for help, which is explaining what's going on, becomes one click.

## What's coming

v1.0 is the foundation. Here's what's still rough and what's next.

The install one-liner works fine, but you still need to know what PowerShell is. A downloadable installer (`.exe` for Windows, signed `.app` for Mac) is coming so your less-technical relatives don't have to see a terminal.

The fix descriptions are still kind of technical. Plain-English mode is coming. Something like *"this clears your computer's memory of websites it visited so they load fresh next time"* instead of `Remove-Item LOCALAPPDATA\Google\Chrome\Cache`.

A "fix the safe stuff automatically" big-button mode, for users who don't want to read 22 problem descriptions.

Scheduled scans that catch issues before you notice them.

Localization. Spanish first, then Tagalog, Hindi, Portuguese. Built with the global use case in mind.

IT-team mode. Multi-step workflows, MDM and Group Policy awareness, ticket system integrations (Freshdesk, Zendesk, ServiceNow).

Laptop hardware health. Drivers, battery wear, thermal throttling.

Browser deep-cleaners that reset Chrome / Edge / Firefox profiles without losing your bookmarks and saved logins.

If anything on this list matters to you and you can help build it, open an issue or send a PR. The tool gets stronger every time someone adds a fix to the registry, translates a string file, or files a real-world bug report. Adding a new fix is about 15 lines of PowerShell or bash. See [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).

## Two tiers

| | Light (free) | Ultimate |
|---|:---:|:---:|
| Health scan | ✅ | ✅ |
| 22 single-shot fixes | ✅ | ✅ |
| Audit mode | ✅ | ✅ |
| Undo every action | ✅ | ✅ |
| Diagnostic bundle export | ✅ | ✅ |
| Multi-step verified workflows | | ✅ |
| Per-machine license binding | | ✅ |
| MDM / Group Policy awareness | | ✅ |
| Multi-language UI | | ✅ |
| Custom branding via config.json | | ✅ |
| ITSM integrations | | ✅ |

Light is fully MIT-licensed. Always free for personal use, no asterisk. Ultimate is for organizations that need workflows, branding, and integrations. Pricing TBD, contact me for early access.

## For organizations

If you run a call center, a clinic, a small business, an MSP, or any operation where people are paid to do something other than troubleshoot their own computer, MendOS was built for you too.

Drop a `config.json` into the user's profile, or push it through Group Policy / Intune / Jamf, and the tool reskins itself with your branding:

```json
{
  "client": {
    "name": "Acme Helpdesk",
    "supportContact": "ithelp@acme.example",
    "ticketSystemUrl": "https://acme.freshservice.com/support/tickets/new"
  },
  "environment": {
    "ssoProvider": "okta",
    "ssoUrl": "https://acme.okta.com",
    "managedByMdm": true
  },
  "problems": {
    "exclude": ["network.consumer-router-reset"],
    "custom": [
      { "id": "acme.crm-relaunch", "title": "Sales CRM frozen" }
    ]
  }
}
```

Your logo. Your color. Your support email. Your ticket system. Your apps. Your custom problem definitions for the software the rest of the world has never heard of. All hot-swappable, no script changes. One tool, infinite tenants. The example config in [`examples/`](examples/) shows a healthcare deployment with PHI redaction in the diagnostic bundle.

The pitch to your finance team writes itself. Most of your help desk's volume is repetitive. If MendOS deflects 30% of it, you save the cost of the tool in the first month and your IT pros stop clearing the same browser cache for the fiftieth time.

## Trust

This tool runs as administrator. That means it can do real damage if you don't trust it. I'm not asking you to. I'm asking you to read the code.

**Open source.** Every line of every script that runs on your machine is in this repo, pinned to a Git commit tag. No minified blobs. No obfuscated functions. No binaries fetched at runtime that you can't inspect.

**SHA-256 hashes** for every release are on the [Releases](https://github.com/heliosprima/mendos/releases) page. Verify before you run.

**AMSI stays on.** Windows Defender's anti-malware scanner is never disabled. Every AMSI bypass technique on the internet is a defense-evasion pattern with no legitimate use case here. We use zero of them.

**No telemetry by default.** Opt-in only. When opted in, it sends anonymous event names and OS version. No hostnames, no usernames, no IPs.

**No keylogging. No clipboard reading. No credential harvesting.** Ever. Search the source for `Get-Clipboard`, `SetWindowsHookEx`, `Get-Credential`. You get zero matches outside actions you click on yourself.

**Every change is reversible** via Undo Last.

**Restore points** are created automatically before any multi-step workflow on Windows.

In 2017, a similar tool called CCleaner shipped signed malware to 2.27 million users through a supply-chain attack. Code signing is necessary but it's not enough. Reproducible builds, commit-pinning, and transparent open source matter more. See [`docs/SECURITY.md`](docs/SECURITY.md) for the full posture.

If MendOS doesn't pass your security review, tell me why. That kind of feedback is the most valuable PR a project like this can get.

## Try it

```powershell
irm 'https://mendos.heliosprima.com/win' | iex
```

```bash
/bin/bash -c "$(curl -fsSL https://mendos.heliosprima.com/mac)"
```

Paste it. See what it does. If your computer's been fighting you, this is the tool that stops the fight.

## License

MIT for the Light tier. See [`docs/LICENSING.md`](docs/LICENSING.md) for how the Ultimate tier gate works and how the freemium model is implemented.

Copyright (c) 2026 [FR4NTZ0N](https://github.com/fr4ntz0n). A [Helios Prima](https://heliosprima.com) product.

---

MendOS. Mend your OS.
