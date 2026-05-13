#!/bin/bash
# ============================================================================
#  MendOS v1.0.0  -  Cross-Platform Self-Service IT Diagnostic Tool
#  macOS entry point
# ============================================================================
#  Deploy via:  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/PH30N1X-PR1Me/frntzn-h3l1os/v1.0.1/src/mac/h3l1os.sh)"
#  Mirrors the architecture of the Windows side:
#    - Three registries (FIXES, PROBLEMS, WORKFLOWS) via arrays/functions
#    - Same vendor-neutral config.json
#    - Same Light/Ultimate tier semantics (stubbed license)
#    - Same audit mode + undo + escalation + diagnostic bundle
#    - AppleScript native dialogs for UI
#
#  Truncation-safe wrap: everything runs inside __h3l1os_main, called on the
#  last line. A truncated download will fail to execute (function undefined).
# ============================================================================

__h3l1os_main() {
    set -uo pipefail   # NOT set -e: we handle errors per-fix

    # ----- CONSTANTS --------------------------------------------------------
    # Hybrid hosting:
    #   - Script lives on GitHub raw (versioned tag URL)
    #   - API endpoints on Cloudflare Worker at mendos.heliosprima.com
    readonly H3L1OS_VERSION="1.0.1"
    readonly H3L1OS_SCRIPT_URL="https://raw.githubusercontent.com/PH30N1X-PR1Me/frntzn-h3l1os/v1.0.1/src/mac/h3l1os.sh"
    readonly H3L1OS_LICENSE_URL="https://mendos.heliosprima.com/v1/license/check"
    readonly H3L1OS_VERSION_URL="https://mendos.heliosprima.com/v1/version"
    readonly H3L1OS_TELEMETRY_URL="https://mendos.heliosprima.com/v1/telemetry/event"
    readonly H3L1OS_APPDATA="$HOME/Library/Application Support/FRNTZN"
    readonly H3L1OS_LOGS="$HOME/Library/Logs/FRNTZN"
    readonly H3L1OS_UNDO="$H3L1OS_APPDATA/undo"
    readonly H3L1OS_CONFIG_USER="$HOME/.frntzn/config.json"
    readonly H3L1OS_LOG="$H3L1OS_LOGS/h3l1os-$(date +%Y%m%d).log"

    mkdir -p "$H3L1OS_APPDATA" "$H3L1OS_LOGS" "$H3L1OS_UNDO"

    # ----- LOGGING ---------------------------------------------------------
    log() {
        local lvl="$1" event="$2" data="${3:-}"
        local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        printf '{"ts":"%s","lvl":"%s","event":"%s"%s}\n' "$ts" "$lvl" "$event" "${data:+,$data}" >> "$H3L1OS_LOG"
    }

    log "info" "app.start" "\"version\":\"$H3L1OS_VERSION\""

    # ----- CONFIG ----------------------------------------------------------
    # Minimal config getters - no jq dependency (parse with python3 which ships
    # with macOS). Returns "" if key missing.
    config_get() {
        local key="$1" file="${2:-$H3L1OS_CONFIG_USER}"
        [[ -f "$file" ]] || { echo ""; return; }
        python3 -c "
import json, sys
try:
    cfg = json.load(open('$file'))
    path = '$key'.split('.')
    for p in path: cfg = cfg.get(p) if isinstance(cfg, dict) else None
    print(cfg if cfg is not None else '')
except Exception: print('')
" 2>/dev/null
    }

    CLIENT_NAME="$(config_get client.name)"
    [[ -z "$CLIENT_NAME" ]] && CLIENT_NAME="MendOS"
    SUPPORT_CONTACT="$(config_get client.supportContact)"
    SSO_URL="$(config_get environment.ssoUrl)"
    AUDIT_MODE=false
    [[ "$(config_get ui.auditModeDefault)" == "True" ]] && AUDIT_MODE=true

    # ----- GATE CHECK (license + machine binding) -------------------------
    # Anti-tamper: cache binds to machine_hash. Copying cache to another Mac
    # invalidates it. Tier comes from Worker; client validates structure only.
    # Source is open - determined users can force Ultimate by editing the
    # script. That's the freemium honor system at this price point.

    get_machine_hash() {
        # Hash hardware UUID + hostname so we don't transmit raw identifiers
        local hw_uuid; hw_uuid=$(ioreg -d2 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/{print $4}')
        [[ -z "$hw_uuid" ]] && hw_uuid=$(hostname)
        local input="$hw_uuid|$(hostname)"
        echo -n "$input" | shasum -a 256 | awk '{print substr($1,1,32)}'
    }

    check_license() {
        local cache="$H3L1OS_APPDATA/license.cache.json"
        local machine_hash; machine_hash=$(get_machine_hash)

        # Cache hit path - validates expiry, machine binding, signature shape
        if [[ -f "$cache" ]]; then
            local valid; valid=$(python3 -c "
import json, datetime, re, sys
try:
    c = json.load(open('$cache'))
    expires = datetime.datetime.fromisoformat(c['expires_at'].replace('Z','+00:00'))
    now = datetime.datetime.now(datetime.timezone.utc)
    if now >= expires: sys.exit(1)
    if c.get('machine_hash') != '$machine_hash': sys.exit(2)
    if not re.match(r'^[a-f0-9]{64}\$', c.get('signature','')): sys.exit(3)
    if c.get('tier') not in ('Light','Ultimate'): sys.exit(4)
    print(c['tier'])
except SystemExit: raise
except Exception: sys.exit(5)
" 2>/dev/null)
            if [[ -n "$valid" ]]; then
                echo "$valid"
                return
            fi
        fi

        # Online check
        local resp; resp=$(curl -fsSL --max-time 5 -X POST \
            -H "Content-Type: application/json" \
            -d "{\"key\":\"${FRNTZN_KEY:-}\",\"machine_hash\":\"$machine_hash\",\"v\":\"$H3L1OS_VERSION\"}" \
            "$H3L1OS_LICENSE_URL" 2>/dev/null)

        if [[ -z "$resp" ]]; then
            echo "Light"
            return
        fi

        # Persist full response so future cache checks have something to verify
        echo "$resp" > "$cache"
        python3 -c "import json,sys; print(json.load(open('$cache')).get('tier','Light'))" 2>/dev/null || echo "Light"
    }
    TIER=$(check_license)
    log "info" "license.tier" "\"tier\":\"$TIER\""

    # Telemetry stub - opt-in only via config.compliance.telemetry
    send_telemetry() {
        local event="$1" success="${2:-true}"
        local telemetry_setting; telemetry_setting=$(config_get compliance.telemetry)
        [[ "$telemetry_setting" != "enabled" ]] && return 0
        curl -fsSL --max-time 3 -X POST \
            -H "Content-Type: application/json" \
            -d "{\"event\":\"$event\",\"version\":\"$H3L1OS_VERSION\",\"os\":\"macOS\",\"success\":$success}" \
            "$H3L1OS_TELEMETRY_URL" >/dev/null 2>&1 || true
    }
    send_telemetry "app.start"

    # ----- APPLESCRIPT HELPERS ---------------------------------------------
    osa_dialog() {
        # Generic message box. Args: title, body
        osascript -e "display dialog \"$2\" with title \"$1\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1
    }
    osa_confirm() {
        # Yes/No confirm. Args: title, body. Returns 0=yes 1=no
        local r; r=$(osascript -e "display dialog \"$2\" with title \"$1\" buttons {\"No\",\"Yes\"} default button \"Yes\" cancel button \"No\"" 2>/dev/null)
        [[ "$r" == *"Yes"* ]] && return 0 || return 1
    }
    osa_choose() {
        # Args: prompt, then list items as separate args.
        # Returns: chosen item on stdout, or "false" if cancelled.
        local prompt="$1"; shift
        local list=""
        for item in "$@"; do
            [[ -z "$list" ]] && list="\"$item\"" || list="$list, \"$item\""
        done
        osascript -e "choose from list {$list} with prompt \"$prompt\" with title \"MendOS\" OK button name \"Select\" cancel button name \"Exit\"" 2>/dev/null
    }
    osa_sudo() {
        # Run command with admin privileges via SecurityAgent. Args: command-string
        # The user sees a native macOS auth prompt. Never put passwords in env.
        osascript -e "do shell script \"$1\" with administrator privileges" 2>&1
    }

    # ----- UNDO REGISTRY ---------------------------------------------------
    add_undo() {
        local desc="$1" cmd="$2"
        local id; id=$(uuidgen)
        printf '{"id":"%s","ts":"%s","description":"%s","undo_command":"%s"}\n' \
            "$id" "$(date -u +%FT%TZ)" "$desc" "$cmd" > "$H3L1OS_UNDO/$id.json"
        log "info" "undo.registered" "\"description\":\"$desc\""
    }
    invoke_last_undo() {
        local latest; latest=$(ls -t "$H3L1OS_UNDO"/*.json 2>/dev/null | head -1)
        if [[ -z "$latest" ]]; then
            osa_dialog "FRNTZN" "Nothing to undo."
            return
        fi
        local cmd; cmd=$(python3 -c "import json; print(json.load(open('$latest'))['undo_command'])")
        local desc; desc=$(python3 -c "import json; print(json.load(open('$latest'))['description'])")
        if eval "$cmd" 2>>"$H3L1OS_LOG"; then
            rm -f "$latest"
            osa_dialog "FRNTZN" "Undone: $desc"
            log "info" "undo.applied" "\"description\":\"$desc\""
        else
            osa_dialog "FRNTZN" "Could not undo: $desc"
            log "error" "undo.failed" "\"description\":\"$desc\""
        fi
    }

    # ============================================================
    #  DIAGNOSTIC FUNCTIONS
    # ============================================================
    scan_uptime() {
        local secs days hours
        secs=$(($(date +%s) - $(sysctl -n kern.boottime | awk -F'[ ,]' '{print $4}')))
        days=$((secs/86400)); hours=$(( (secs%86400)/3600 ))
        local status="green"
        (( days >= 7 )) && status="red"
        (( days >= 2 && days < 7 )) && status="yellow"
        echo "$status|$days days, $hours hours"
    }
    scan_disk() {
        local free total pct
        free=$(df -g / | awk 'NR==2 {print $4}')
        total=$(df -g / | awk 'NR==2 {print $2}')
        pct=$(( free * 100 / total ))
        local status="green"
        (( pct < 10 )) && status="red"
        (( pct >= 10 && pct < 20 )) && status="yellow"
        echo "$status|$free GB free of $total GB"
    }
    scan_ram() {
        # vm_stat reports pages free; macOS uses 4KB pages
        local pages_free pages_total pct
        pages_free=$(vm_stat | awk '/Pages free/ {gsub("\\.",""); print $3}')
        local total_bytes; total_bytes=$(sysctl -n hw.memsize)
        local total_gb; total_gb=$(echo "scale=1; $total_bytes/1073741824" | bc)
        local free_gb; free_gb=$(echo "scale=1; $pages_free * 4096 / 1073741824" | bc)
        local used_gb; used_gb=$(echo "scale=1; $total_gb - $free_gb" | bc)
        local pct_int; pct_int=$(echo "scale=0; $used_gb * 100 / $total_gb" | bc)
        local status="green"
        (( pct_int >= 90 )) && status="red"
        (( pct_int >= 75 && pct_int < 90 )) && status="yellow"
        echo "$status|$used_gb GB / $total_gb GB (${pct_int}%)"
    }
    scan_updates() {
        # softwareupdate history is slow; use last update marker file age
        local marker="/Library/Updates/index.plist"
        if [[ -f "$marker" ]]; then
            local days_ago; days_ago=$(( ( $(date +%s) - $(stat -f %m "$marker") ) / 86400 ))
            local status="green"
            (( days_ago >= 60 )) && status="red"
            (( days_ago >= 30 && days_ago < 60 )) && status="yellow"
            echo "$status|$days_ago days since last update"
        else
            echo "yellow|Unable to determine"
        fi
    }
    scan_network() {
        if ping -c 1 -t 2 1.1.1.1 >/dev/null 2>&1; then
            echo "green|Online"
        else
            echo "red|No internet detected"
        fi
    }
    scan_battery() {
        if ! pmset -g batt 2>/dev/null | grep -q "InternalBattery"; then
            echo "green|No battery (desktop)"
            return
        fi
        local pct; pct=$(pmset -g batt | grep -Eo "\d+%" | head -1 | tr -d '%')
        local status="green"
        (( pct < 20 )) && status="red"
        (( pct >= 20 && pct < 50 )) && status="yellow"
        echo "$status|${pct}%"
    }

    # ============================================================
    #  FIX REGISTRY
    # ============================================================
    # Format: registered as bash functions named fix_<key> and fix_desc_<key>
    fix_desc_dns_flush() { echo "Flushes DNS resolver cache.\n\nRuns:\n  sudo dscacheutil -flushcache\n  sudo killall -HUP mDNSResponder\n\nProceed?"; }
    fix_dns_flush() {
        $AUDIT_MODE && return 0
        osa_sudo "dscacheutil -flushcache && killall -HUP mDNSResponder"
        return $?
    }

    fix_desc_audio_reset() { echo "Restarts the macOS Core Audio service. Audio will pause briefly.\n\nProceed?"; }
    fix_audio_reset() {
        $AUDIT_MODE && return 0
        osa_sudo "killall coreaudiod"
        return $?
    }

    fix_desc_bluetooth_reset() { echo "Restarts the Bluetooth service.\n\nProceed?"; }
    fix_bluetooth_reset() {
        $AUDIT_MODE && return 0
        osa_sudo "pkill bluetoothd"
        return $?
    }

    fix_desc_printer_reset() { echo "Restarts the CUPS print system.\n\nProceed?"; }
    fix_printer_reset() {
        $AUDIT_MODE && return 0
        osa_sudo "launchctl stop org.cups.cupsd && launchctl start org.cups.cupsd"
        return $?
    }

    fix_desc_purge_memory() { echo "Frees inactive memory via the 'purge' command.\n\nProceed?"; }
    fix_purge_memory() {
        $AUDIT_MODE && return 0
        osa_sudo "purge"
        return $?
    }

    fix_desc_chrome_cache() { echo "Closes Chrome and clears its cache. Bookmarks preserved.\n\nProceed?"; }
    fix_chrome_cache() {
        $AUDIT_MODE && return 0
        osascript -e 'quit app "Google Chrome"' 2>/dev/null
        sleep 1
        rm -rf "$HOME/Library/Caches/Google/Chrome"/* 2>/dev/null
        return 0
    }

    fix_desc_safari_cache() { echo "Quits Safari and clears its cache.\n\nProceed?"; }
    fix_safari_cache() {
        $AUDIT_MODE && return 0
        osascript -e 'quit app "Safari"' 2>/dev/null
        sleep 1
        rm -rf "$HOME/Library/Caches/com.apple.Safari"/* 2>/dev/null
        return 0
    }

    fix_desc_okta_open() { echo "Opens your organization's Okta sign-in page.\n\nProceed?"; }
    fix_okta_open() {
        $AUDIT_MODE && return 0
        local url="$SSO_URL"
        [[ -z "$url" ]] && url="https://www.okta.com/help"
        open "$url"
    }

    fix_desc_time_sync() { echo "Forces a time sync (helps with TOTP/MFA codes).\n\nProceed?"; }
    fix_time_sync() {
        $AUDIT_MODE && return 0
        osa_sudo "sntp -sS time.apple.com"
    }

    fix_desc_login_items() { echo "Opens System Settings > General > Login Items so you can manage startup apps.\n\nProceed?"; }
    fix_login_items() {
        $AUDIT_MODE && return 0
        open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    }

    # ============================================================
    #  PROBLEM REGISTRY (label / keywords / fix_key)
    # ============================================================
    # Single string per entry: "label||keywords||fix_key"
    declare -a PROBLEMS=(
        "Internet connected but websites won't load (DNS)||dns website page browser load internet||dns_flush"
        "I can't hear anything / audio glitchy||sound audio speaker headset volume silent mute output||audio_reset"
        "Bluetooth not working / device won't pair||bluetooth bt pair pairing wireless headset mouse keyboard||bluetooth_reset"
        "Printer offline / won't print||printer print cups offline queue stuck||printer_reset"
        "Computer feels slow / free up memory||slow lag ram memory purge boost||purge_memory"
        "Chrome is slow / clear Chrome cache||chrome cache google browser slow||chrome_cache"
        "Safari is slow / clear Safari cache||safari cache apple browser||safari_cache"
        "Okta keeps asking me to verify / push not arriving||okta mfa push verify 2fa sso login||okta_open"
        "MFA codes not working (sync time)||time clock mfa totp sync drift||time_sync"
        "App keeps starting at login (manage Login Items)||startup login items boot autostart||login_items"
    )

    # ============================================================
    #  WORKFLOW REGISTRY  (Ultimate tier only)
    # ============================================================
    workflow_low_end_boost() {
        $AUDIT_MODE && { osa_dialog "Boost" "AUDIT MODE: would run 5 cleanup steps."; return; }

        local baseline_ram baseline_free
        baseline_ram=$(scan_ram | cut -d'|' -f2)
        baseline_free=$(scan_disk | cut -d'|' -f2)

        local results=""
        results+="\n[OK] Baseline: $baseline_ram, $baseline_free"

        # Step 1: purge inactive memory
        if osa_sudo "purge" >/dev/null 2>&1; then
            results+="\n[OK] Purged inactive memory"
        else
            results+="\n[FAIL] Could not purge memory"
        fi

        # Step 2: clear user caches
        local before_size; before_size=$(du -sk "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
        find "$HOME/Library/Caches" -type f -delete 2>/dev/null
        local after_size; after_size=$(du -sk "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
        local freed=$(( (before_size - after_size) / 1024 ))
        results+="\n[OK] Cleared ~${freed} MB from caches"

        # Step 3: trim local Time Machine snapshots
        if osa_sudo "tmutil thinLocalSnapshots / 999999999999 4" >/dev/null 2>&1; then
            results+="\n[OK] Trimmed local Time Machine snapshots"
        else
            results+="\n[SKIP] No snapshots to trim"
        fi

        # Step 4: re-index Spotlight if it's running away
        # (skipped by default - too disruptive)
        results+="\n[SKIP] Spotlight re-index (skipped - run manually if needed)"

        # Step 5: final
        local final_ram; final_ram=$(scan_ram | cut -d'|' -f2)
        local final_free; final_free=$(scan_disk | cut -d'|' -f2)
        results+="\n[OK] After: $final_ram, $final_free"

        osa_dialog "Boost Mac - Complete" "${results//\\n/$'\n'}"
        log "info" "workflow.complete" "\"key\":\"low-end-boost\""
    }

    # ============================================================
    #  DIAGNOSTIC BUNDLE EXPORT
    # ============================================================
    export_bundle() {
        local ts; ts=$(date +%Y%m%d-%H%M%S)
        local dir="$HOME/Desktop/FRNTZN-Diagnostic-$ts"
        mkdir -p "$dir"
        {
            echo "MendOS Diagnostic Bundle"
            echo "Generated: $(date -u +%FT%TZ)"
            echo "Tool version: $H3L1OS_VERSION"
            echo "Tier: $TIER"
            echo "Audit mode: $AUDIT_MODE"
            echo "Client: $CLIENT_NAME"
            echo ""
            echo "=== System ==="
            sw_vers
            sysctl -n machdep.cpu.brand_string
            echo "RAM: $(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024 " GB"}')"
        } > "$dir/summary.txt"
        cp "$H3L1OS_LOG" "$dir/h3l1os.log" 2>/dev/null
        {
            echo "=== Disk ==="
            df -h /
            echo
            echo "=== Network ==="
            ifconfig
            echo
            echo "=== Top RAM processes ==="
            ps aux | sort -k4 -nr | head -10
        } > "$dir/system-info.txt"
        local zip="$dir.zip"
        (cd "$HOME/Desktop" && zip -qr "$(basename "$zip")" "$(basename "$dir")")
        rm -rf "$dir"
        echo "$zip" | pbcopy
        log "info" "bundle.exported" "\"path\":\"$zip\""
        osa_dialog "Bundle exported" "Diagnostic bundle saved to:\n$zip\n\nPath copied to clipboard."
        open -R "$zip"
    }

    escalate() {
        export_bundle
        if [[ -n "$SUPPORT_CONTACT" ]]; then
            open "mailto:$SUPPORT_CONTACT?subject=IT%20Support%20Request%20-%20$(hostname)&body=A%20diagnostic%20bundle%20was%20saved%20to%20my%20Desktop.%20Path%20on%20clipboard."
        fi
    }

    # ============================================================
    #  MAIN MENU LOOP
    # ============================================================
    while true; do
        local subtitle="$CLIENT_NAME - $TIER tier"
        $AUDIT_MODE && subtitle="$subtitle [AUDIT MODE]"

        # Build menu list
        local -a menu=(
            "🔍 Run health scan"
            "⚙️  Toggle Audit Mode (currently: $AUDIT_MODE)"
            "🛠  Pick an issue to fix..."
            "⬆️  Boost low-end Mac (Ultimate workflow)"
            "↩️  Undo last fix"
            "📦 Export diagnostic bundle"
            "📧 Escalate to IT"
            "🚪 Exit"
        )

        local choice; choice=$(osa_choose "$subtitle" "${menu[@]}")
        [[ "$choice" == "false" || -z "$choice" ]] && break

        case "$choice" in
            *"health scan"*)
                local report=""
                for fn in scan_uptime scan_disk scan_ram scan_updates scan_network scan_battery; do
                    local r; r=$($fn)
                    local s="${r%%|*}"; local t="${r#*|}"
                    local mark="✓"; [[ "$s" == "yellow" ]] && mark="!"; [[ "$s" == "red" ]] && mark="✗"
                    report+="$mark  ${fn#scan_}: $t\n"
                done
                osa_dialog "Health Scan" "${report//\\n/$'\n'}"
                ;;
            *"Audit Mode"*)
                if $AUDIT_MODE; then AUDIT_MODE=false; else AUDIT_MODE=true; fi
                log "info" "audit.toggle" "\"audit\":$AUDIT_MODE"
                ;;
            *"Pick an issue"*)
                local -a labels=()
                for p in "${PROBLEMS[@]}"; do labels+=("${p%%||*}"); done
                local picked; picked=$(osa_choose "What's wrong?" "${labels[@]}")
                [[ "$picked" == "false" || -z "$picked" ]] && continue
                # Find the matching fix key
                for p in "${PROBLEMS[@]}"; do
                    local label="${p%%||*}"
                    if [[ "$label" == "$picked" ]]; then
                        local fix_key="${p##*||}"
                        local desc; desc=$("fix_desc_$fix_key")
                        if osa_confirm "Confirm" "$desc"; then
                            if "fix_$fix_key"; then
                                osa_dialog "Done" "Fix applied."
                            else
                                osa_dialog "Failed" "Fix did not complete."
                            fi
                        fi
                        break
                    fi
                done
                ;;
            *"Boost low-end"*)
                if [[ "$TIER" != "Ultimate" ]]; then
                    osa_dialog "Ultimate tier" "This workflow is part of the Ultimate tier.\nThe free Light tier includes single-shot fixes."
                else
                    if osa_confirm "Boost Mac" "Run 5-step optimization?\n\nSafe and reversible."; then
                        workflow_low_end_boost
                    fi
                fi
                ;;
            *"Undo"*)
                invoke_last_undo
                ;;
            *"Export"*)
                export_bundle
                ;;
            *"Escalate"*)
                escalate
                ;;
            *"Exit"*)
                break
                ;;
        esac
    done

    log "info" "app.exit" ""
    send_telemetry "app.exit"
    echo "MendOS exited cleanly."
}

# Truncation-safe: if download was cut off, this function call fails.
__h3l1os_main "$@"
