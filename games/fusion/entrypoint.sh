#!/bin/bash
cd /home/container || exit 1

INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

export DISPLAY=:99
export LD_LIBRARY_PATH=/home/container:${LD_LIBRARY_PATH}

# ---- configuration ----
# Applied before anything can fail, so the panel's variables reach server.json
# even when Steam does not come up. Env vars own their own keys; everything else
# in the file survives untouched.
if [ ! -f /home/container/server.json ]; then
    cp /home/container/server.example.json /home/container/server.json
fi

# jq --argjson needs a real JSON literal. A panel can hand us 1, TRUE or yes, and
# any of those would write a non-boolean into server.json that the server then
# refuses to read.
as_bool() {
    case "$(printf '%s' "${1}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on)   printf 'true' ;;
        0|false|no|off)  printf 'false' ;;
        *)               printf '%s' "${2}" ;;
    esac
}

jq \
  --arg name        "${SERVER_NAME:-My Fusion Server}" \
  --arg description "${SERVER_DESCRIPTION:-}" \
  --arg barcode     "${LEVEL_BARCODE:-fa534c5a868247138f50c62e424c4144.Level.VoidG114}" \
  --arg title       "${LEVEL_TITLE:-15 - Void G114}" \
  --arg panelUser   "${PANEL_USER:-admin}" \
  --arg panelPass   "${PANEL_PASS:-}" \
  --arg rconPass    "${RCON_PASSWORD:-}" \
  --argjson players   "${MAX_PLAYERS:-10}" \
  --argjson privacy   "${PRIVACY:-0}" \
  --argjson major     "${FUSION_VERSION_MAJOR:-1}" \
  --argjson minor     "${FUSION_VERSION_MINOR:-14}" \
  --argjson entities  "${MAX_ENTITIES:-2000}" \
  --argjson global    "$(as_bool "${GLOBAL_LISTS}" true)" \
  --argjson extended  "$(as_bool "${EXTENDED_PROTECTION}" true)" \
  --argjson whitelist "$(as_bool "${WHITELIST}" false)" \
  --argjson maxDamage "${MAX_REMOTE_DAMAGE:-200}" \
  --argjson antispam  "$(as_bool "${ANTISPAM}" true)" \
  --argjson burst     "${SPAWN_BURST_LIMIT:-25}" \
  --argjson perPlayer "${MAX_ENTITIES_PER_PLAYER:-300}" \
  --argjson panelPort "${SERVER_PORT:-8778}" \
  --argjson rconPort  "${RCON_PORT:-27015}" \
  '.ServerName = $name
   | .Description = $description
   | .MaxPlayers = $players
   | .Privacy = $privacy
   | .VersionMajor = $major
   | .VersionMinor = $minor
   | .LevelBarcode = $barcode
   | .LevelTitle = $title
   | .MaxEntities = $entities
   | .GlobalListsEnabled = $global
   | .ExtendedProtection = $extended
   | .WhitelistEnabled = $whitelist
   | .MaxRemoteDamage = $maxDamage
   | .AntiSpamEnabled = $antispam
   | .SpawnBurstLimit = $burst
   | .MaxEntitiesPerPlayer = $perPlayer
   | .DashboardHost = "+"
   | .DashboardPort = $panelPort
   | .DashboardUser = $panelUser
   | .DashboardPassword = $panelPass
   | .RconPort = $rconPort
   | .RconPassword = $rconPass' \
  /home/container/server.json > /home/container/server.json.tmp \
  && mv /home/container/server.json.tmp /home/container/server.json

echo "Config: $(jq -r '"\(.ServerName), \(.MaxPlayers) slots, Fusion v\(.VersionMajor).\(.VersionMinor)"' /home/container/server.json)"

if [ -z "${PANEL_PASS}" ]; then
    echo "PANEL_PASS is empty, so the control panel will refuse to start."
fi

# ---- virtual display ----
# Steam refuses to start without one, even headless.
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &

for _ in $(seq 1 15); do
    [ -e /tmp/.X11-unix/X99 ] && break
    sleep 1
done

if [ ! -e /tmp/.X11-unix/X99 ]; then
    echo "Xvfb did not start; Steam cannot run without a display."
    exit 1
fi

STEAM_ROOT=/home/container/.local/share/Steam
STEAM_BOOTSTRAP=/usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz

# steam.sh runs steam-runtime-check-requirements and refuses to start if it fails.
# It demands an unprivileged user namespace for bubblewrap, which many container
# hosts disallow. The sandbox adds nothing here because the container is already
# the boundary, so the check is replaced with a no-op that exits 0.
#
# Globs rather than find: a missing find would fail silently and this has to work.
# Both known runtime layouts are covered, and a non-matching glob stays literal,
# which the -f test discards.
disarm_requirement_checks() {
    _found=0
    _changed=0

    for check in \
        "${STEAM_ROOT}"/*/steam-runtime/*/usr/bin/steam-runtime-check-requirements \
        "${STEAM_ROOT}"/*/steam-runtime/usr/bin/steam-runtime-check-requirements
    do
        [ -f "${check}" ] || continue

        _found=$((_found + 1))

        grep -q 'fusion-dedicated no-op' "${check}" 2>/dev/null && continue

        {
            echo '#!/bin/sh'
            echo '# fusion-dedicated no-op: the container is the sandbox boundary,'
            echo '# so Steam does not need a user namespace of its own here.'
            echo 'exit 0'
        } > "${check}" 2>/dev/null || continue

        chmod +x "${check}" 2>/dev/null || continue

        _changed=$((_changed + 1))
    done

    [ "${_found}" -eq 0 ] && return 1
    [ "${_changed}" -gt 0 ] && return 0

    return 1
}

# Unpack the bootstrap ourselves so the check exists before Steam ever reads it.
# Steam's own launcher does this and then immediately runs the check, leaving no
# moment to intervene; doing it here removes the race entirely. bin_steam.sh skips
# its own setup when steam.sh is present and the data link resolves.
if [ ! -x "${STEAM_ROOT}/steam.sh" ] && [ -f "${STEAM_BOOTSTRAP}" ]; then
    echo "Unpacking Steam's bootstrap so its namespace check can be replaced first..."

    mkdir -p "${STEAM_ROOT}"

    if tar xJf "${STEAM_BOOTSTRAP}" -C "${STEAM_ROOT}" 2>/dev/null; then
        mkdir -p /home/container/.steam
        ln -fns "${STEAM_ROOT}" /home/container/.steam/steam
    else
        echo "Could not unpack it here; leaving Steam to do it."
    fi
fi

if disarm_requirement_checks; then
    echo "Replaced Steam's user-namespace check with a no-op."
else
    if [ -x "${STEAM_ROOT}/steam.sh" ]; then
        echo "Steam's user-namespace check is already a no-op."
    else
        echo "Steam's runtime is not unpacked yet; the check will be replaced once it appears."
    fi
fi

# ---- user namespaces ----
# Tested by asking the kernel for a namespace rather than reading a sysctl,
# because the governing setting differs between distributions. A missing unshare
# must not be read as a blocked namespace, or this stops a node that was fine.
# Informational rather than fatal: the requirement check above is disabled, so
# Steam starts either way. A node that allows namespaces lets Steam keep its own
# sandbox, which is worth having, so the settings are still worth naming.
if command -v unshare >/dev/null 2>&1 && ! unshare --user --map-root-user true >/dev/null 2>&1; then
    echo "Note: this node blocks unprivileged user namespaces, so Steam runs without"
    echo "its bubblewrap sandbox. The container is the boundary instead, and the"
    echo "server works. To give Steam its sandbox back, the node administrator can set:"
    echo "  Debian: kernel.unprivileged_userns_clone=1"
    echo "  Ubuntu 24.04 and newer: also kernel.apparmor_restrict_unprivileged_userns=0"
    echo "  Every host: user.max_user_namespaces must be more than 0"
    echo "in /etc/sysctl.d/99-steam-userns.conf, then run sysctl --system."
fi

# ---- steam ----
# SteamAPI.Init needs a signed-in client, so Steam must come up first.
if [ -z "${STEAM_USER}" ] || [ -z "${STEAM_PASS}" ]; then
    echo "STEAM_USER and STEAM_PASS are required."
    echo "Use a separate account with SteamVR (app 250820, free) and Steam Guard off."
    exit 1
fi

# steam -login puts the password on its command line, so it turns up in ps, in
# steam.log and in Steam's own console log. Strip the literal value out of
# anything on its way to the panel console.
redact() {
    if command -v awk >/dev/null 2>&1; then
        awk -v secret="${STEAM_PASS}" '
            {
                if (secret != "") {
                    while ((at = index($0, secret)) > 0) {
                        $0 = substr($0, 1, at - 1) "<redacted>" substr($0, at + length(secret))
                    }
                }
                print
            }
        '
    else
        # Without awk there is no reliable way to strip it, so print nothing.
        cat >/dev/null
        echo "  (output suppressed: no awk to redact the Steam password)"
    fi
}

# Steam's launcher runs as bin_steam.sh, then steam.sh, then the client itself.
# Matching an exact process name misses all of those, so match the command line.
steam_alive() {
    # Match what the client is, not what it is not. A bare "steam" also matches
    # srt-logger and steamdeps, which outlive the client and would report a dead
    # one as alive. Excluding "srt-logger" is wrong too: the client's own command
    # line carries a -srt-logger-opened flag.
    ps -ef 2>/dev/null \
        | grep -qE "[s]team\.sh|[u]buntu12_(32|64)/steam( |$)|[/]usr/bin/steam( |$)"
}

start_steam() {
    if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL -eL steam -login "${STEAM_USER}" "${STEAM_PASS}" -no-browser \
            >>/home/container/steam.log 2>&1 &
    else
        steam -login "${STEAM_USER}" "${STEAM_PASS}" -no-browser >>/home/container/steam.log 2>&1 &
    fi
}

# steam.sh reports a failed requirement check through show_message, which opens a
# dialog on the virtual display and waits. The process therefore stays alive after
# it has already given up, so waiting for it to exit never ends.
stop_steam() {
    pkill -f "[s]team\.sh" 2>/dev/null
    pkill -f "[u]buntu12_32/steam" 2>/dev/null
    sleep 3
}

if ! steam_alive; then
    echo "Signing in to Steam as ${STEAM_USER}..."
    start_steam
fi

# On a fresh volume Steam downloads its runtime, which takes minutes rather than
# seconds. SteamAPI.Init fails against a client that has not finished, so wait for
# the client library to appear instead of guessing at a sleep.
find_steamclient() {
    for candidate in \
        /home/container/.local/share/Steam/linux64/steamclient.so \
        /home/container/.local/share/Steam/ubuntu12_64/steamclient.so \
        /home/container/.steam/sdk64/steamclient.so \
        /home/container/.steam/steam/linux64/steamclient.so; do
        [ -f "${candidate}" ] && { echo "${candidate}"; return 0; }
    done
    return 1
}

echo "Waiting for Steam to finish bootstrapping (first run downloads its runtime)..."

# SteamAPI_IsSteamRunning reads ~/.steam/steam.pid and checks that process is
# alive, so that file is what "logged in and serving" actually looks like.
# steamclient.so ships in the bootstrap and appears minutes earlier.
steam_pid_alive() {
    [ -f /home/container/.steam/steam.pid ] || return 1
    pid=$(cat /home/container/.steam/steam.pid 2>/dev/null)
    [ -n "${pid}" ] || return 1
    kill -0 "${pid}" 2>/dev/null
}

STEAM_CLIENT=""
DEAD=0
RETRIED=0
LAST_REPORTED=""

STEAM_CONSOLE=/home/container/.local/share/Steam/logs/console-linux.txt

# The newest line Steam has written, from whichever log actually has content.
steam_latest() {
    line=""

    if [ -s "${STEAM_CONSOLE}" ]; then
        line=$(tail -1 "${STEAM_CONSOLE}" 2>/dev/null | tr -d '\r' | redact)
    fi

    if [ -z "${line}" ] && [ -s /home/container/steam.log ]; then
        line=$(tail -1 /home/container/steam.log 2>/dev/null | tr -d '\r' | redact)
    fi

    printf '%s' "${line}"
}

steam_snapshot() {
    echo "--- what the container actually has (one-off diagnostic) ---"
    echo "xz:    $(command -v xz || echo MISSING)"
    echo "steam: $(command -v steam || echo MISSING)"

    echo "Steam dir:"
    ls -la /home/container/.local/share/Steam/ 2>/dev/null | head -12 || echo "  does not exist"

    for candidate in /home/container/.local/share/Steam/ubuntu12_32/steam \
                     /home/container/.local/share/Steam/ubuntu12_64/steam; do
        if [ -f "${candidate}" ]; then
            echo "Client binary ${candidate}:"
            ldd "${candidate}" 2>&1 | grep -i "not found" | head -10 \
                || echo "  all shared libraries resolve"
        fi
    done

    echo "Steam log directory:"
    ls -la /home/container/.local/share/Steam/logs/ 2>/dev/null | head -8 || echo "  none yet"

    # steam -login puts the password on the command line, so it shows in ps.
    # Strip it before anything reaches the console.
    echo "Steam pid file:"
    if [ -f /home/container/.steam/steam.pid ]; then
        echo "  ~/.steam/steam.pid holds $(cat /home/container/.steam/steam.pid 2>/dev/null)"
    else
        echo "  not written yet, so Steam has not signed in"
    fi

    echo "Steam processes:"
    ps -ef 2>/dev/null | grep "[s]team" | redact | head -5
    echo "--- end diagnostic ---"
}

for i in $(seq 1 180); do
    [ "${i}" -eq 6 ] && steam_snapshot

    # On a fresh volume the check binary only exists once Steam has unpacked the
    # runtime, which is after we first looked. Catch it here and restart Steam,
    # because by now it has either failed the check or is stuck showing the error.
    if [ "${RETRIED}" -eq 0 ] && disarm_requirement_checks >/dev/null 2>&1; then
        echo "Neutralised Steam's user-namespace check; restarting Steam."
        RETRIED=1
        DEAD=0

        stop_steam
        start_steam

        sleep 5
        continue
    fi

    if STEAM_CLIENT=$(find_steamclient) && steam_pid_alive; then
        echo "Steam is ready: ${STEAM_CLIENT}"
        echo "Steam signed in after $((i * 5))s."
        break
    fi

    # The client library appearing is what actually matters. Process detection is
    # only an early exit for a genuine crash, so it needs three consecutive dead
    # readings after the first minute before it is believed, a wrong reading here
    # would abort a perfectly healthy first-run download.
    if [ "${i}" -gt 12 ]; then
        if steam_alive; then
            DEAD=0
        else
            DEAD=$((DEAD + 1))
        fi

        if [ "${DEAD}" -ge 3 ]; then
            echo "Steam exited while starting up. Last lines of its console log:"
            tail -40 "${STEAM_CONSOLE}" 2>/dev/null | redact
            echo "--- launcher output ---"
            tail -20 /home/container/steam.log 2>/dev/null | redact
            exit 1
        fi
    fi

    # A bare counter tells you nothing about whether Steam is working or stuck.
    # Echo its latest output instead, and only when it changes.
    if [ $((i % 6)) -eq 0 ]; then
        LATEST=$(steam_latest)

        if [ "${LATEST}" != "${LAST_REPORTED}" ] && [ -n "${LATEST}" ]; then
            echo "  ($((i * 5))s) ${LATEST}"
            LAST_REPORTED="${LATEST}"
        else
            echo "  ($((i * 5))s) still waiting; Steam has written nothing new"
        fi

        ls -la /home/container/.local/share/Steam/ 2>/dev/null | tail -n +2 | wc -l \
            | xargs -I{} echo "        Steam directory holds {} entries"
    fi

    sleep 5
done

if [ -n "${STEAM_CLIENT}" ] && ! steam_pid_alive; then
    echo "Steam unpacked but never signed in within fifteen minutes."
    echo "Starting anyway; the server retries for another ten minutes."
    echo "If it never connects, check the account for Steam Guard:"
    grep -iE "steam guard|two.factor|login fail|invalid password|logon deni"         "${STEAM_CONSOLE}" 2>/dev/null | redact | tail -10         || echo "  (nothing in the console log about login)"
fi

if [ -z "${STEAM_CLIENT}" ]; then
    echo "Steam did not finish bootstrapping in fifteen minutes."
    echo "--- Steam console log ---"
    tail -60 "${STEAM_CONSOLE}" 2>/dev/null | redact || echo "  (no console log written)"
    echo "--- launcher output ---"
    tail -20 /home/container/steam.log 2>/dev/null | redact
    echo "--- what exists ---"
    ls -la /home/container/.local/share/Steam/ 2>/dev/null | head -20
    exit 1
fi

# Steamworks looks for the client library here.
mkdir -p /home/container/.steam/sdk64
cp -f "${STEAM_CLIENT}" /home/container/.steam/sdk64/steamclient.so 2>/dev/null || true

sleep 10

# ---- run ----
MODIFIED_STARTUP=$(echo -e ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

eval ${MODIFIED_STARTUP}
