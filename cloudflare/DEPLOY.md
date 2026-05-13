# MendOS - Deploy From Scratch

This guide assumes **zero prior experience** with Git, GitHub, Node.js, Cloudflare Workers, or any of it. Every command is shown. Every screen is described. If you follow each step in order, you'll have a working public install one-liner in about an hour.

If something doesn't work, jump to the **Troubleshooting** section at the very bottom.

---

## What you need before you start

- A **Windows or Mac computer** you can install software on
- A **Cloudflare account** (free tier is fine) — sign up at cloudflare.com if you don't have one
- A **domain you own** that's been added to Cloudflare (so Cloudflare is the nameserver for it). If you don't have one yet, you can buy one through Cloudflare itself for ~$10/year — easiest path.
- A **GitHub account** — sign up at github.com if you don't have one. It's free.
- About **60 minutes** of uninterrupted time
- The **mendos folder** that was built for you — put it somewhere you can find it, like your Desktop

---

## Phase 0 — Install the three tools you need (one-time, ~15 min)

You only do this once. If you've already installed Git and Node.js before, skip this phase.

### 0.1 — Install Git

Git is the tool that uploads your code to GitHub.

**Windows:**
1. Go to https://git-scm.com/download/win
2. The download starts automatically. Run the installer.
3. Click Next, Next, Next through every screen. The defaults are fine.
4. When done, open PowerShell (press the Windows key, type "powershell", hit Enter).
5. Type: `git --version` and press Enter.
6. You should see something like `git version 2.45.1.windows.1`. If you do, Git is installed.

**Mac:**
1. Open Terminal (press Cmd+Space, type "terminal", hit Enter).
2. Type: `git --version` and press Enter.
3. If macOS asks to install Command Line Tools, click Install and wait ~5 minutes.
4. When done, run `git --version` again. You should see something like `git version 2.39.5 (Apple Git-154)`.

### 0.2 — Install Node.js

Node.js gives you `npm`, which we'll use to install Wrangler.

**Windows + Mac:**
1. Go to https://nodejs.org
2. Click the big green button that says "LTS" (Long Term Support). Don't pick the "Current" version.
3. Run the installer. Click through all defaults.
4. After install, open a NEW PowerShell/Terminal window (this is important — old windows won't see the new install).
5. Type: `node --version` and press Enter. You should see `v20.something` or `v22.something`.
6. Type: `npm --version` and press Enter. You should see something like `10.x.x`.

If both worked, Node.js is installed.

### 0.3 — Install Wrangler (Cloudflare's deployment tool)

In your PowerShell/Terminal window, run:

```bash
npm install -g wrangler
```

This might take 30-60 seconds. You may see a few warnings — that's normal, ignore them.

When it finishes, test:

```bash
wrangler --version
```

You should see something like `⛅️ wrangler 3.90.0`. If you do, Wrangler is installed.

### 0.4 — Connect Wrangler to your Cloudflare account

```bash
wrangler login
```

A browser window opens asking you to authorize Wrangler. Click "Allow". You'll see a success page. Close the browser tab and come back to the terminal — it should now say "Successfully logged in."

You're now ready to deploy to Cloudflare.

---

## Phase 1 — Get your project ready (~5 min)

### 1.1 — Open the project folder in your terminal

You need to "be in" the mendos folder when running commands. Here's how:

**Windows (PowerShell):**
```powershell
cd "$HOME\Desktop\mendos"
```
(If you put the folder somewhere else, change the path. Like `cd "C:\Users\YourName\Documents\mendos"`.)

**Mac (Terminal):**
```bash
cd ~/Desktop/mendos
```

### 1.2 — Confirm you're in the right place

Run this:

**Windows:**
```powershell
ls
```

**Mac:**
```bash
ls
```

You should see folders named `cloudflare`, `config`, `docs`, `examples`, `src`, `strings` and files like `README.md`, `LICENSE`, `SHIP_CHECKLIST.md`. If you see those, you're in the right folder.

If you see something else (like your Desktop contents), you're not in the right folder yet. Use `cd` to navigate to it.

---

## Phase 2 — Make it yours (~3 min)

The project files have two placeholders that need to be replaced with your actual info:

- `heliosprima.com` → your domain (e.g. `frntzn.dev` or `myhelpdesk.com`)
- `fr4ntz0n` → your GitHub username (e.g. `frantzonj`)

### 2.1 — Decide on your values

Pick your domain name and GitHub username and write them down. You'll use them in the next step.

Example:
- Your domain: `mycoolsite.dev`
- Your GitHub username: `frantzonj`

### 2.2 — Run the replacement command

**Make sure you're still in the mendos folder.** Then run:

**Windows (PowerShell):**
```powershell
Get-ChildItem -Recurse -Include *.ps1,*.sh,*.js,*.toml,*.json,*.html,*.md |
  Where-Object { $_.FullName -notlike '*\.git\*' } |
  ForEach-Object {
    (Get-Content $_.FullName -Raw) `
      -replace 'YOURDOMAIN\.TLD','mycoolsite.dev' `
      -replace 'fr4ntz0n','frantzonj' |
      Set-Content $_.FullName -NoNewline
  }
```

(Replace `mycoolsite.dev` and `frantzonj` with YOUR actual values before running.)

**Mac (Terminal):**
```bash
find . -type f \( -name "*.ps1" -o -name "*.sh" -o -name "*.js" -o -name "*.toml" -o -name "*.json" -o -name "*.html" -o -name "*.md" \) \
  -not -path "./.git/*" \
  -exec sed -i.bak 's/YOURDOMAIN\.TLD/mycoolsite.dev/g; s/fr4ntz0n/frantzonj/g' {} \;
find . -name "*.bak" -delete
```

(Again, swap `mycoolsite.dev` and `frantzonj` for YOUR values.)

### 2.3 — Verify the replacement worked

**Windows:**
```powershell
Select-String -Path .\src\windows\h3l1os.ps1 -Pattern 'ScriptUrl' | Select-Object -First 1
```

**Mac:**
```bash
grep "ScriptUrl" src/windows/h3l1os.ps1 | head -1
```

You should see your real domain and username. No `heliosprima.com` or `fr4ntz0n` left.

If you see the placeholders, the replacement didn't work — try the command again, making sure you replaced the example values with your real ones.

---

## Phase 3 — Push to GitHub (~10 min)

### 3.1 — Create the repo on GitHub

1. Go to https://github.com/new in your browser
2. **Repository name:** `mendos`
3. **Description:** "Self-service IT diagnostic tool for Windows and macOS" (or whatever you want)
4. **Public** (must be public so `raw.githubusercontent.com` works)
5. DO NOT check "Add a README file", "Add .gitignore", or "Choose a license" — we already have those
6. Click the green "Create repository" button

You'll see a page with instructions. Ignore them — we have our own.

### 3.2 — Configure your local Git identity (first time only)

If this is your first time using Git, you need to tell it who you are:

```bash
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
```

(Use the same email as your GitHub account.)

### 3.3 — Push the code to GitHub

Still in the `mendos` folder, run these one at a time:

```bash
git init
```

```bash
git add .
```

```bash
git commit -m "MendOS v1.0.0"
```

```bash
git branch -M main
```

```bash
git remote add origin https://github.com/frantzonj/mendos.git
```

(Replace `frantzonj` with your actual GitHub username.)

```bash
git push -u origin main
```

The last command might pop up a browser asking you to log in to GitHub — do it. After authentication, the upload runs (~10-30 seconds).

### 3.4 — Verify it's on GitHub

Open `https://github.com/frantzonj/mendos` in your browser (with your username). You should see all the files. If yes — code is published.

### 3.5 — Test the raw URL

In your browser, go to:

```
https://raw.githubusercontent.com/frantzonj/mendos/main/src/windows/h3l1os.ps1
```

You should see the raw PowerShell code as plain text. If you do, your install URL is working. (We'll create the versioned `v1.0.0` URL in Phase 7.)

---

## Phase 4 — Add Cloudflare DNS (~3 min)

We need to tell Cloudflare that `api.mycoolsite.dev` exists (so the Worker has somewhere to live).

1. Go to https://dash.cloudflare.com and log in
2. Click your domain name (the one you'll use)
3. In the left sidebar, click **DNS** → **Records**
4. Click **Add record** (top right)
5. Fill in:
   - **Type:** A
   - **Name:** `api` (just the word "api", not the full domain)
   - **IPv4 address:** `192.0.2.1` (this is a placeholder; the Worker overrides it)
   - **Proxy status:** Toggle ON (orange cloud — VERY IMPORTANT)
   - **TTL:** Auto
6. Click **Save**

You should now see a row in the DNS records table for `api.mycoolsite.dev` with an orange cloud icon.

### Verify

In your terminal:
```bash
nslookup api.mycoolsite.dev
```

(Use your real domain.) You should get an answer (the IP doesn't matter — what matters is that you GET an answer). If you get "can't find" or "NXDOMAIN", DNS hasn't propagated yet — wait 60 seconds and try again.

---

## Phase 5 — Create KV namespaces and set the secret (~5 min)

### 5.1 — Navigate into the cloudflare folder

```bash
cd cloudflare
```

(You should now be in `mendos/cloudflare`.)

### 5.2 — Create the LICENSES namespace

```bash
wrangler kv namespace create LICENSES
```

(Note: newer Wrangler uses `kv namespace` with a space; older versions use `kv:namespace`. If the first form errors, try `wrangler kv:namespace create LICENSES`.)

The output looks like:
```
🌀 Creating namespace with title "mendos-api-LICENSES"
✨ Success!
Add the following to your configuration file:
[[kv_namespaces]]
binding = "LICENSES"
id = "a1b2c3d4e5f6789..."
```

**Copy the long `id` value** — you'll paste it into `wrangler.toml` in a moment.

### 5.3 — Create the TELEMETRY namespace

```bash
wrangler kv namespace create TELEMETRY
```

Copy the `id` from this one too.

### 5.4 — Paste the IDs into wrangler.toml

Open `cloudflare/wrangler.toml` in any text editor (Notepad, VS Code, TextEdit — anything).

Find these lines:
```toml
[[kv_namespaces]]
binding = "LICENSES"
id = "REPLACE_WITH_LICENSES_KV_ID"

[[kv_namespaces]]
binding = "TELEMETRY"
id = "REPLACE_WITH_TELEMETRY_KV_ID"
```

Replace `REPLACE_WITH_LICENSES_KV_ID` with the LICENSES id you copied, and `REPLACE_WITH_TELEMETRY_KV_ID` with the TELEMETRY id. Save the file.

### 5.5 — Generate and set the HMAC secret

The HMAC secret is a random string that signs the license responses. Generate one:

**Mac/Linux:**
```bash
openssl rand -hex 32
```

**Windows (PowerShell):**
```powershell
-join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
```

Copy the output (a long hex string like `7a3f...`).

Now save it as a Worker secret:

```bash
wrangler secret put HMAC_SECRET
```

When it prompts, paste the secret and press Enter. You should see "Success!"

You'll never need this value again — Cloudflare stores it for the Worker only.

---

## Phase 6 — Deploy the Worker (~3 min)

Still in the `cloudflare` folder:

```bash
wrangler deploy
```

You'll see output like:
```
Total Upload: 5.2 KiB / gzip: 2.1 KiB
Uploaded mendos-api (1.2 sec)
Published mendos-api (0.4 sec)
  https://mendos-api.your-account.workers.dev
  api.mycoolsite.dev/v1/*
Current Deployment ID: ...
```

If you see `api.mycoolsite.dev/v1/*` (your real domain) in the output, the route is bound. Worker is live.

### Test it

In your terminal or browser, hit the health endpoint:

```bash
curl https://api.mycoolsite.dev/v1/health
```

You should see:
```json
{"ok":true,"ts":"2026-05-13T..."}
```

If you do — the API is working. If not, jump to Troubleshooting.

Test the license check too:

```bash
curl -X POST https://api.mycoolsite.dev/v1/license/check -H "Content-Type: application/json" -d "{\"key\":\"\",\"machine_hash\":\"deadbeef1234567890abcdef12345678\",\"v\":\"1.0.0\"}"
```

You should get back a JSON object with `"tier":"Light"`, a signature, an expires_at, etc.

---

## Phase 7 — Tag the v1.0.0 release on GitHub (~5 min)

The install one-liners point at the `v1.0.0` tag, not `main`. This makes the URL immutable — even if you push changes later, `v1.0.0` always serves the original code. We need to create that tag.

### 7.1 — Go back to the project root

```bash
cd ..
```

You should now be in `mendos` (one level up from `cloudflare`).

### 7.2 — Create the tag

```bash
git tag -a v1.0.0 -m "v1.0.0 - initial release"
```

```bash
git push origin v1.0.0
```

### 7.3 — Create a GitHub Release from the tag (optional but recommended)

1. Go to `https://github.com/frantzonj/mendos/releases` in your browser
2. Click **Draft a new release** (or "Create a new release")
3. **Choose a tag:** pick `v1.0.0` from the dropdown
4. **Release title:** `MendOS v1.0.0`
5. **Description:** Write a few lines about what it does. Or paste your README intro.
6. (Optional) Attach SHA-256 hash files — see below
7. Click **Publish release**

### 7.4 — Generate and attach SHA-256 hashes (recommended)

Hashes let people verify the script wasn't tampered with. From the project root:

**Mac/Linux:**
```bash
shasum -a 256 src/windows/h3l1os.ps1 > h3l1os.ps1.sha256
shasum -a 256 src/mac/h3l1os.sh > h3l1os.sh.sha256
```

**Windows (PowerShell):**
```powershell
(Get-FileHash src\windows\h3l1os.ps1 -Algorithm SHA256).Hash | Out-File h3l1os.ps1.sha256 -Encoding ascii
(Get-FileHash src\mac\h3l1os.sh -Algorithm SHA256).Hash | Out-File h3l1os.sh.sha256 -Encoding ascii
```

Drag both `.sha256` files into the GitHub Release page (in the "Attach binaries" area). Save the release.

### 7.5 — Verify the versioned raw URL works

In your browser, go to:

```
https://raw.githubusercontent.com/frantzonj/mendos/v1.0.0/src/windows/h3l1os.ps1
```

(Use your real username.) You should see the raw PowerShell code. This URL will never change — anyone who runs it three years from now gets the exact same code.

---

## Phase 8 — Run the install one-liner end-to-end (~3 min)

### 8.1 — On Windows

Open PowerShell (regular, not admin — UAC will prompt automatically). Run:

```powershell
irm 'https://raw.githubusercontent.com/frantzonj/mendos/v1.0.0/src/windows/h3l1os.ps1' | iex
```

(Replace `frantzonj` with your username.)

A UAC prompt appears asking for admin privileges. Click Yes.

The tool launches in a new PowerShell window. You should see the MendOS WPF window with:
- "Light tier (free)" badge in the header
- 7 health-check rows
- A search box and dropdown picker
- Footer buttons (Undo, Escalate, Refresh, Exit)

If you see all that — **you've shipped a real product.**

### 8.2 — On Mac (if you have one)

Open Terminal. Run:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/frantzonj/mendos/v1.0.0/src/mac/h3l1os.sh)"
```

The bash menu launches. You'll see options to run a health scan, pick an issue, etc.

---

## Phase 9 — Optional: Grant yourself Ultimate to test the gate (~3 min)

Make sure the gate-check is actually working by giving yourself an Ultimate key.

### 9.1 — Generate a license key

Any uppercase-letters-and-numbers string (8-64 chars) works. Examples:

- `FRNTZN-TEST-ULTI-MATE`
- `BETA-7K9X-3M2P-2026`

Pick one and write it down.

### 9.2 — Add it to KV

From the `cloudflare` folder:

```bash
wrangler kv key put --binding=LICENSES "FRNTZN-TEST-ULTI-MATE" "{\"tier\":\"Ultimate\",\"machines\":[],\"created\":\"2026-05-13\"}"
```

(Use your key. Note: older Wrangler uses `kv:key` with a colon.)

### 9.3 — Run the tool with the key set

**Windows (PowerShell):**
```powershell
$env:FRNTZN_KEY = 'FRNTZN-TEST-ULTI-MATE'
irm 'https://raw.githubusercontent.com/frantzonj/mendos/v1.0.0/src/windows/h3l1os.ps1' | iex
```

**Mac (Terminal):**
```bash
export FRNTZN_KEY='FRNTZN-TEST-ULTI-MATE'
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/frantzonj/mendos/v1.0.0/src/mac/h3l1os.sh)"
```

The header should now say "Ultimate tier" in gold instead of "Light tier" in teal. Multi-step workflows like "Boost Low-End System" should run instead of showing the "Ultimate tier required" dialog.

### 9.4 — Confirm machine binding works

Check your KV — the machine_hash should now be registered:

```bash
wrangler kv key get --binding=LICENSES "FRNTZN-TEST-ULTI-MATE"
```

You should see your key's data with `"machines":["abc123..."]` — that's your machine hash. If you try the same key on a 4th machine, it'll silently downgrade to Light.

---

## You did it

You now have:

- ✅ Code on GitHub at `https://github.com/yourusername/mendos`
- ✅ Versioned install URL at `https://raw.githubusercontent.com/yourusername/mendos/v1.0.0/src/...`
- ✅ Worker live at `https://api.yourdomain/v1/*`
- ✅ License gate with machine binding
- ✅ Opt-in telemetry sink
- ✅ A real, shippable product

Post the one-liners anywhere. Notion, LinkedIn, your support docs, your portfolio site, Hacker News, Reddit r/sysadmin. They work.

---

## Cutting a new release later

When you fix something or add a feature and want to release v1.0.1:

1. Edit the version constants inside both scripts — swap `1.0.0` for `1.0.1`:
   - `src/windows/h3l1os.ps1`: change `$script:Version = '1.0.0'` and update the `/v1.0.0/` in the ScriptUrl
   - `src/mac/h3l1os.sh`: change `H3L1OS_VERSION="1.0.0"` and update `/v1.0.0/` in H3L1OS_SCRIPT_URL
2. Update worker version manifest — edit `cloudflare/worker.js`, find `handleVersion()`, change `1.0.0` to `1.0.1`

Then:

```bash
git add .
git commit -m "v1.0.1 - what changed"
git push origin main

git tag -a v1.0.1 -m "v1.0.1"
git push origin v1.0.1

cd cloudflare
wrangler deploy
```

Then update your README's quick-start commands to point at `v1.0.1` instead of `v1.0.0`.

---

## Granting Ultimate to a paying customer (later)

When you actually have a customer:

```bash
cd cloudflare
wrangler kv key put --binding=LICENSES "THEIR-LICENSE-KEY" "{\"tier\":\"Ultimate\",\"machines\":[],\"created\":\"2026-05-13\"}"
```

To revoke:

```bash
wrangler kv key delete --binding=LICENSES "THEIR-LICENSE-KEY"
```

(Their local cache continues honoring Ultimate up to 14 days. For instant revocation you'd need to bump them — for one customer that's usually not worth a support call.)

---

## Migrating to Lemon Squeezy (later, when ready to sell)

1. Sign up at lemonsqueezy.com, create a product
2. Add API key as Worker secret: `wrangler secret put LEMON_SQUEEZY_API_KEY`
3. Edit `cloudflare/worker.js`, replace the body of `handleLicenseCheck` so KV lookup is preceded by a `fetch()` to `https://api.lemonsqueezy.com/v1/licenses/validate`
4. Cache the validated tier in KV with 24h TTL to avoid hammering their API
5. `wrangler deploy`

Desktop tool needs no changes.

---

## Cost ceiling (free tier)

| Resource | Free limit | What it means |
|---|---|---|
| Worker requests | 100k/day | ~30 tool launches/sec sustained |
| KV reads | 100k/day | Same |
| KV writes | 1k/day | Telemetry constraint if opt-in scales |
| GitHub raw bandwidth | "Soft fair use" | Hundreds of GB before they email |

If you blow past Worker limits, the paid plan is $5/month for 10M requests.

---

## Troubleshooting

### "git: command not found"
Phase 0.1 didn't finish. Close and reopen your terminal, then try again. If still nothing, reinstall Git and tick "Add Git to PATH" during install.

### "wrangler: command not found"
After `npm install -g wrangler`, you may need a new terminal window for it to be on PATH. Close and reopen.

### `wrangler login` browser doesn't open
Copy the URL it printed into your browser manually.

### `wrangler kv:namespace create` says "command not found" or "did you mean..."
Wrangler v3.60+ moved to `kv namespace` (with space). Try:
```bash
wrangler kv namespace create LICENSES
```

### `wrangler deploy` says "10026" or "couldn't find zone"
The domain you set in `wrangler.toml` (`zone_name`) doesn't match a domain in your Cloudflare account, OR DNS for the api subdomain isn't set up yet. Re-check Phase 4.

### `curl https://api.mycoolsite.dev/v1/health` returns "could not resolve host"
DNS propagation. Wait 1-2 minutes and try again. If still failing after 5 minutes, check Cloudflare → DNS Records → your `api` record exists and is **orange-cloud proxied** (not grey).

### `curl` returns 522 or 1016 or "Error 1014"
The DNS record's `Proxy status` is wrong. It must be **proxied (orange cloud)**, not DNS-only (grey cloud).

### Install one-liner fails with "could not parse certificate" or SSL error
Cloudflare SSL hasn't provisioned yet. Wait 2-3 minutes after adding the DNS record. Re-test.

### Install one-liner fails with PowerShell "running scripts is disabled"
The user's machine has restrictive PowerShell ExecutionPolicy. They need to run an admin PowerShell once and execute:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

### Tool launches but stays "Light tier" even with FRNTZN_KEY set
1. Did you set the env var in the SAME PowerShell window where you run the install command? Env vars don't carry across windows by default.
2. Is the key actually in KV? Check: `wrangler kv key get --binding=LICENSES "YOUR-KEY"`.
3. Is the existing license cache lying? Delete it: `Remove-Item "$env:LOCALAPPDATA\frntzn\license.cache.json"` (Win) or `rm "~/Library/Application Support/FRNTZN/license.cache.json"` (Mac), then retry.

### "Permission denied (publickey)" when running `git push`
GitHub auth issue. Easiest fix: use HTTPS (which we do) and let Git pop up the browser for OAuth. If your URL is `git@github.com:...`, change to `https://github.com/...`:
```bash
git remote set-url origin https://github.com/frantzonj/mendos.git
```

### `wrangler deploy` succeeds but `https://api.mycoolsite.dev/v1/health` returns 404
The route pattern in `wrangler.toml` doesn't match. Check it reads exactly:
```toml
pattern = "api.mycoolsite.dev/v1/*"
zone_name = "mycoolsite.dev"
```
(With your real domain.) Re-deploy: `wrangler deploy`.

### "KV namespace not found" warning during deploy
You didn't paste the real IDs into `wrangler.toml`. Re-do Phase 5.4.

### When stuck on any other issue
1. Read the error message carefully — it usually says what's wrong
2. Search the exact error message in Google
3. Check Cloudflare Dashboard → Workers & Pages → mendos-api → Logs (live tail) — you'll see what's actually happening when you hit the API

---

## Glossary

- **CDN** — Content Delivery Network. Cloudflare's edge servers that cache and serve files globally.
- **CLI** — Command Line Interface. Tools you type into a terminal (Git, Wrangler, Node).
- **DNS** — Domain Name System. Maps `api.yourdomain.com` to an actual server.
- **KV** — Key-Value store. Cloudflare's simple database. Free tier is plenty for licenses + telemetry.
- **Repo** — Repository. A folder of code tracked by Git, hosted on GitHub.
- **Tag** — A git pointer to a specific commit. `v1.0.0` always points to the same exact code.
- **Worker** — A small program that runs on Cloudflare's edge. Like a tiny serverless function.
- **Wrangler** — The CLI tool to deploy Cloudflare Workers.
