#!/bin/bash
cd /home/container || exit 1

INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

export DISPLAY=:99

# steam.sh returns early from show_message under gamescope instead of opening a
# dialog and waiting on it. Without this, a failed requirement check leaves Steam
# blocked on "Press enter to continue" forever rather than exiting.
export XDG_CURRENT_DESKTOP=gamescope
export LD_LIBRARY_PATH=/home/container:${LD_LIBRARY_PATH}

# Wings reuses a cached image when the tag has not changed under it, so a run can
# silently use an old entrypoint. Print a hash of this file so the version being
# run is never in doubt.
echo "Entrypoint build: $(sha256sum "$0" 2>/dev/null | cut -c1-12 || echo unknown)"

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
  --arg     panelIp   "${SERVER_IP:-}" \
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
   | .DashboardPublicHost = $panelIp
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

echo "Allocation: ip=${SERVER_IP:-<unset>} port=${SERVER_PORT:-<unset>} rcon=${RCON_PORT:-<unset>}"

if [ -n "${SERVER_PORT}" ] && [ "${RCON_PORT:-27015}" = "${SERVER_PORT}" ]; then
    echo "The panel and RCON are both set to port ${SERVER_PORT}. The panel takes it"
    echo "and RCON will not start. Give RCON its own allocation to run both."
fi

if [ -z "${SERVER_PORT}" ]; then
    echo "SERVER_PORT is not set, so the panel falls back to 8778. Pterodactyl only"
    echo "publishes ports it allocated, so give the server an allocation and the"
    echo "panel will follow it."
fi

# ---- steam login from the command line ----
# Steam's client dropped its -login flag, but steamcmd kept one, and both keep
# their credentials in config/config.vdf and config/loginusers.vdf. So sign in
# with steamcmd and hand the result to the client, which auto-signs-in when it
# finds a token and an AutoLoginUser.
STEAM_CONFIG_DIR="${STEAM_ROOT}/config"

already_signed_in() {
    grep -qi "${STEAM_USER}" "${STEAM_CONFIG_DIR}/loginusers.vdf" 2>/dev/null
}

# The client reads this to decide whether to sign in without being asked.
write_autologin() {
    mkdir -p /home/container/.steam

    cat > /home/container/.steam/registry.vdf <<REGEOF
"Registry"
{
	"HKCU"
	{
		"Software"
		{
			"Valve"
			{
				"Steam"
				{
					"AutoLoginUser"		"${STEAM_USER}"
					"RememberPassword"		"1"
					"SkipOfflineModeWarning"		"1"
				}
			}
		}
	}
}
REGEOF
}

steamcmd_login() {
    echo "Signing in with steamcmd so the client can reuse the credentials..."

    rm -rf /home/container/.steamcmd-home
    mkdir -p /home/container/.steamcmd-home

    # steamcmd updates itself in place, so it needs a copy it owns rather than the
    # root-owned one in /opt that the container user cannot write to or execute.
    _sc=/home/container/.steamcmd-home/steamcmd
    mkdir -p "${_sc}"
    cp -r /opt/steamcmd/. "${_sc}/" 2>/dev/null
    chmod -R u+rwX "${_sc}" 2>/dev/null
    chmod u+x "${_sc}/steamcmd.sh" 2>/dev/null

    if [ ! -x "${_sc}/steamcmd.sh" ]; then
        echo "steamcmd could not be made runnable at ${_sc}/steamcmd.sh."
        return 1
    fi

    _out=/home/container/steamcmd-login.log
    : > "${_out}"

    # stdin from /dev/null so a Steam Guard prompt fails fast instead of blocking
    # for the whole timeout, and the status is kept rather than lost down a pipe.
    HOME=/home/container/.steamcmd-home timeout 300 "${_sc}/steamcmd.sh" \
        +@ShutdownOnFailedCommand 1 \
        +login "${STEAM_USER}" "${STEAM_PASS}" ${STEAM_GUARD_CODE} \
        +quit </dev/null >"${_out}" 2>&1
    _rc=$?

    redact < "${_out}" | sed -u "s/^/[steamcmd] /" | tail -40
    echo "[steamcmd] exit status ${_rc}"

    if grep -qi "Steam Guard\|two.factor\|Two-factor" "${_out}" 2>/dev/null; then
        echo "steamcmd wants a Steam Guard code. Put a fresh one in STEAM_GUARD_CODE"
        echo "and start the server straight away, because they expire in minutes."
        return 1
    fi

    if grep -qi "Invalid Password\|password is incorrect\|Login Failure" "${_out}" 2>/dev/null; then
        echo "steamcmd says the account name or password is wrong."
        return 1
    fi

    # steamcmd.sh sets its root to its own directory, so its config lands beside
    # the script rather than under HOME.
    _cfg="${_sc}/config"
    [ -d "${_cfg}" ] || _cfg=/home/container/.steamcmd-home/Steam/config

    echo "[steamcmd] files written to ${_cfg}:"
    ls -la "${_cfg}" 2>/dev/null | tail -n +2 || echo "  no config directory at all"

    # The client needs a token to sign in unattended. Name the keys present so a
    # sign-in that produced no usable credential is obvious.
    if [ -f "${_cfg}/config.vdf" ]; then
        echo "[steamcmd] credential keys in config.vdf:"
        grep -oiE "\"(ConnectCache|Accounts|SentryFile|MostRecent|RefreshToken)\""             "${_cfg}/config.vdf" 2>/dev/null | sort -u | sed "s/^/  /"             || echo "  none of the expected keys"
    fi

    if [ "${_rc}" -ne 0 ] || [ ! -f "${_cfg}/config.vdf" ]; then
        echo "steamcmd did not sign in, so the client has no credentials to reuse."
        return 1
    fi

    mkdir -p "${STEAM_CONFIG_DIR}"

    for f in config.vdf; do
        if [ -f "${_cfg}/${f}" ]; then
            cp -f "${_cfg}/${f}" "${STEAM_CONFIG_DIR}/${f}"
            echo "[steamcmd] handed ${f} to the client."
        fi
    done

    # steamcmd writes config.vdf but no loginusers.vdf, and that is the file the
    # client reads to decide which account may sign in without being asked. Build
    # it from the SteamID steamcmd recorded against the account.
    # Debian ships mawk, which has neither IGNORECASE nor {n} interval
    # expressions, so an awk pattern for a 17 digit id silently never matched.
    _id=$(grep -iA6 "\"${STEAM_USER}\"" "${_cfg}/config.vdf" 2>/dev/null           | grep -oE "7656[0-9]{13}" | head -1)

    # The account block is the reliable place, but a lone id elsewhere in the
    # file beats giving up when only one account has ever signed in here.
    if [ -z "${_id}" ]; then
        _id=$(grep -oE "7656119[0-9]{10}" "${_cfg}/config.vdf" 2>/dev/null | head -1)
    fi

    # STEAM_ID is the override for when steamcmd records no id of its own.
    [ -n "${STEAM_ID}" ] && _id="${STEAM_ID}"

    if [ -z "${_id}" ]; then
        echo "steamcmd signed in but recorded no SteamID for ${STEAM_USER}."
        echo "Put the account's SteamID in STEAM_ID and restart. What it wrote:"
        grep -oE "\"(Accounts|SteamID|[0-9]{17})\"|\"${STEAM_USER}\""             "${_cfg}/config.vdf" 2>/dev/null | sort -u | sed "s/^/  /"             || echo "  no account section at all"
        return 1
    fi

    cat > "${STEAM_CONFIG_DIR}/loginusers.vdf" <<USEREOF
"users"
{
	"${_id}"
	{
		"AccountName"		"${STEAM_USER}"
		"RememberPassword"		"1"
		"WantsOfflineMode"		"0"
		"SkipOfflineModeWarning"		"0"
		"AllowAutoLogin"		"1"
		"MostRecent"		"1"
		"Timestamp"		"$(date +%s)"
	}
}
USEREOF

    write_autologin
    echo "steamcmd signed in as ${STEAM_USER} (${_id})."
    return 0
}

# ---- steam login through a browser ----
# SteamMatchmaking.CreateLobby is a user API, so this needs a signed-in account
# rather than a game server token. Steam's own login runs in its UI, which has no
# command-line route any more, so show that UI over the display it already draws
# on and let a person sign in once. The volume keeps the session afterwards.
start_login_ui() {
    [ -n "${VNC_PASSWORD}" ] || {
        echo "STEAM_LOGIN_UI is on but VNC_PASSWORD is empty, so the login screen"
        echo "would be open to anyone. Set a password and restart."
        return 1
    }

    mkdir -p /home/container/.vnc
    x11vnc -storepasswd "${VNC_PASSWORD}" /home/container/.vnc/passwd >/dev/null 2>&1

    x11vnc -display "${DISPLAY}" -rfbauth /home/container/.vnc/passwd         -localhost -rfbport 5900 -forever -shared -noxdamage -quiet         >>/home/container/vnc.log 2>&1 &

    websockify --web=/usr/share/novnc "0.0.0.0:${VNC_PORT:-8080}" 127.0.0.1:5900         >>/home/container/vnc.log 2>&1 &

    echo "Steam login screen: http://${SERVER_IP}:${VNC_PORT:-8080}/vnc.html"
    echo "Sign in there once. Steam keeps the session in this server's files, so"
    echo "turn STEAM_LOGIN_UI off again afterwards to close the screen."
    return 0
}

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

# Steam's React login rewrite stopped -login being read, which is why the console
# log records the credentials on the command line and then never attempts a
# sign-in. -noreactlogin restores the old path and has to come first.
# No -login here. Steam ignores it, and leaving it off keeps the password out of
# ps and out of Steam's own logs. The client signs in from the credentials
# steamcmd cached and the AutoLoginUser written next to them.
#
# -no-cef-sandbox because Steam's sign-in runs inside steamwebhelper, which is
# Chromium, whose sandbox needs the user namespaces this node refuses. Without
# it steamwebhelper never starts, so nothing ever asks Steam to sign in.
start_steam() {
    if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL -eL steam -no-cef-sandbox -no-browser -silent             >>/home/container/steam.log 2>&1 &
    else
        steam -no-cef-sandbox -no-browser -silent >>/home/container/steam.log 2>&1 &
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

wrap_webhelper >/dev/null 2>&1     && echo "Wrapped steamwebhelper so CEF does not need the container's small /dev/shm."

if already_signed_in; then
    echo "Steam already has credentials for ${STEAM_USER}."
    write_autologin
else
    steamcmd_login || echo "Falling back to whatever the client can do on its own."
fi

if [ "$(as_bool "${STEAM_LOGIN_UI}" false)" = "true" ]; then
    start_login_ui || true
fi

if ! steam_alive; then
    echo "Starting Steam as ${STEAM_USER}..."
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

# A container gets 64M of /dev/shm whatever its memory limit, and Chromium wants
# a great deal more, so steamwebhelper dies on mmap and Steam never gets the UI
# it signs in through. --disable-dev-shm-usage sends that shared memory to a temp
# directory instead. Steam gives no way to pass CEF a flag, so wrap the binary it
# launches. A client update replaces it, hence the re-check.
wrap_webhelper() {
    _found=0
    _changed=0

    for helper in "${STEAM_ROOT}"/ubuntu12_64/steamwebhelper                   "${STEAM_ROOT}"/ubuntu12_32/steamwebhelper
    do
        [ -f "${helper}" ] || continue
        _found=$((_found + 1))

        # Ours is a shell script sitting next to the real binary.
        if [ -f "${helper}.real" ] && head -c 2 "${helper}" 2>/dev/null | grep -q "#!"; then
            continue
        fi

        mv -f "${helper}" "${helper}.real" 2>/dev/null || continue

        {
            echo "#!/bin/sh"
            echo "# fusion-dedicated: keep CEF off the container's 64M /dev/shm."
            echo "exec \"${helper}.real\" --disable-dev-shm-usage \"\$@\""
        } > "${helper}" 2>/dev/null || continue

        chmod +x "${helper}" 2>/dev/null || continue
        _changed=$((_changed + 1))
    done

    [ "${_found}" -eq 0 ] && return 1
    [ "${_changed}" -gt 0 ] && return 0
    return 1
}

# Steam forks a -child-update-ui process to apply its own update, and that is
# the process burning 99% CPU on every start so far. It exits when the update
# finishes, so its absence is the signal that Steam has settled.
steam_updating() {
    ps -ef 2>/dev/null | grep -q "[-]child-update-ui"
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

    # steam.sh replaces the whole runtime directory whenever the archive checksum
    # changes, which a self-update guarantees, so one disarm cannot survive. Put
    # the no-op back every time a fresh binary appears.
    if disarm_requirement_checks >/dev/null 2>&1; then
        echo "Replaced Steam's namespace check again after a runtime update."
        RETRIED=$((RETRIED + 1))
    fi

    if STEAM_CLIENT=$(find_steamclient) && ! steam_updating && steam_alive; then
        echo "Steam settled after $((i * 5))s: ${STEAM_CLIENT}"
        break
    fi

    # Steam exits 71 when the namespace check refuses the node. That happens
    # after a runtime update has overwritten the no-op, so restarting it once the
    # runtime has stopped changing is what gets it through, rather than giving up.
    if steam_alive; then
        DEAD=0
    else
        DEAD=$((DEAD + 1))

        if [ "${DEAD}" -ge 2 ]; then
            echo "Steam is not running; restarting it with the check disarmed."
            disarm_requirement_checks >/dev/null 2>&1
            stop_steam
            start_steam
            DEAD=0
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

        if steam_updating; then
            echo "        still applying Steam's own update"
        fi
    fi

    sleep 5
done

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

if steam_updating; then
    echo "Steam is updating itself. Starting anyway, since the server retries"
    echo "SteamAPI_Init for ten minutes and the watchdog restarts Steam after."
fi

echo "--- can Steam sign in? ---"
echo "Shared memory: $(df -h /dev/shm 2>/dev/null | awk 'NR==2 {print $2 " total, " $4 " free"}' || echo unknown)"
echo "Address space limit: $(ulimit -v 2>/dev/null || echo unknown)"
echo "Open file limit: $(ulimit -n 2>/dev/null || echo unknown)"

if pgrep -f steamwebhelper >/dev/null 2>&1; then
    echo "steamwebhelper: running, so Steam has the UI it signs in through."
else
    echo "steamwebhelper: NOT running. Steam's sign-in lives in it, so the client"
    echo "  stays anonymous and no lobby can be created. Its own words:"
    grep -iE "webhelper|cef|sandbox|shared memory|mmap" "${STEAM_CONSOLE}" 2>/dev/null         | redact | tail -12 | sed "s/^/    /" || echo "    (nothing logged about it)"
fi
echo "--- end ---"

echo "--- Steam's own log, at the moment the server starts ---"
tail -60 "${STEAM_CONSOLE}" 2>/dev/null | redact || echo "  (no console log written)"
echo "--- end of Steam log ---"

# Steam not signing in is the single reason a server stays invisible, so pull the
# lines that say why out of a log too long to read on a console.
echo "--- what Steam says about signing in ---"
grep -iE "logon|log ?in|sign ?in|steam ?guard|two.factor|auth|password|credential|account name"     "${STEAM_CONSOLE}" 2>/dev/null | redact | tail -25     || echo "  (nothing about login in the console log)"
echo "--- end ---"

echo "Memory: $(cat /sys/fs/cgroup/memory.max 2>/dev/null     || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null     || echo unknown) bytes. Steam's UI needs roughly 1.5G to start."
echo "Steam signs in on its own schedule, so the server now retries"
echo "SteamAPI_Init every 5s for ten minutes. Updating on first run is normal."

# Steam restarts itself after updating, so the minutes after this point are
# where it either signs in or does not. Mirror its log while the server retries
# rather than leaving that window blank. Stops on its own so the console does
# not stay noisy for the life of the server.
( timeout 720 tail -n 0 -F "${STEAM_CONSOLE}" 2>/dev/null | redact | sed -u "s/^/[steam] /" ) &

# A curl to loopback proves nothing about whether the panel is reachable: it
# answers the same whether it bound 0.0.0.0 or 127.0.0.1 only. Print the actual
# listening address and try the container's own IP.
(
    sleep 45
    port="${SERVER_PORT:-8778}"

    echo "[panel] listening sockets on ${port}:"
    ss -ltn 2>/dev/null | grep ":${port}" || netstat -ltn 2>/dev/null | grep ":${port}"         || echo "  nothing bound to ${port} at all"

    for target in "127.0.0.1" "${INTERNAL_IP}"; do
        [ -n "${target}" ] || continue
        code=$(curl -s -o /dev/null -m 5 -w "%{http_code}" "http://${target}:${port}/" 2>/dev/null)
        echo "[panel] http://${target}:${port}/ -> ${code:-no answer}"
    done

    echo "[panel] a 401 on the container IP means it is reachable and the port is fine."
    echo "[panel] a 401 on 127.0.0.1 but nothing on the container IP means it bound"
    echo "[panel] loopback only, which is the server's fault rather than the network's."
) &

# Steam replaces its whole runtime whenever it updates itself, which puts the
# namespace check back and kills the client. That can happen long after startup,
# so keep putting the no-op back and restart the client when it dies, rather than
# only doing it while waiting.
(
    while true; do
        if disarm_requirement_checks >/dev/null 2>&1; then
            echo "[steam] put the namespace check back to a no-op after an update."
        fi

        # steamwebhelper only exists once the client update has landed, so this
        # is usually the first chance to wrap it.
        if wrap_webhelper >/dev/null 2>&1; then
            echo "[steam] wrapped steamwebhelper to keep CEF off /dev/shm; restarting Steam."
            stop_steam
            start_steam
            sleep 25
        fi

        if ! steam_alive; then
            echo "[steam] the client is not running; restarting it."
            disarm_requirement_checks >/dev/null 2>&1
            start_steam
            sleep 25
        fi

        sleep 5
    done
) &

# ---- run ----
MODIFIED_STARTUP=$(echo -e ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

eval ${MODIFIED_STARTUP}
