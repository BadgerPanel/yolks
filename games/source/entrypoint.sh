#!/bin/bash

#
# Copyright (c) 2021 Matthew Penner
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# Wait for the container to fully initialize
sleep 1

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to the container's working directory
cd /home/container || exit 1


## just in case someone removed the defaults.
if [ "${STEAM_USER}" == "" ]; then
    echo -e "steam user is not set.\n"
    echo -e "Using anonymous user.\n"
    STEAM_USER=anonymous
    STEAM_PASS=""
    STEAM_AUTH=""
else
    echo -e "user set to ${STEAM_USER}"
fi

# SRCDS_X64 -> -beta x86-64 auto-derivation. The gmod (and other
# Source) eggs let operators toggle 64-bit binaries via SRCDS_X64;
# the corresponding steamcmd branch is 'x86-64'. Without this
# block, an operator who toggles SRCDS_X64 from 0->1 in the panel
# saves the env var but the per-start steamcmd update below
# never asks for the x86-64 branch, so srcds_linux_x64 is never
# downloaded and srcds_run crashes with
#   ERROR: Source Engine binary 'srcds_linux_x64' not found
# Explicit SRCDS_BETAID still wins (lets advanced users pin to
# prerelease / dev / mod-specific betas).
if [ "${SRCDS_X64}" == "1" ] && [ -z "${SRCDS_BETAID}" ]; then
    echo -e "[entrypoint] SRCDS_X64=1 detected, using -beta x86-64 for steamcmd"
    SRCDS_BETAID="x86-64"
fi

## if auto_update is not set or to 1 update
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    # Update Source Server.
    # 'validate' is hard-coded ON when SRCDS_X64=1 because the
    # 32-bit and 64-bit branches share files but have different
    # binaries; steamcmd's per-file content check skips files
    # whose size matches even when the architecture differs.
    # Validate forces re-fetch of any mismatched file - critical
    # when switching architectures mid-flight.
    if [ ! -z ${SRCDS_APPID} ]; then
        VALIDATE_FLAG=""
        if [ "${SRCDS_X64}" == "1" ] || [ ! -z "${VALIDATE}" ]; then
            VALIDATE_FLAG="validate"
        fi
	    ./steamcmd/steamcmd.sh +force_install_dir /home/container +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update 1007 +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) ${VALIDATE_FLAG} +quit
    else
        echo -e "No appid set. Starting Server"
    fi

else
    echo -e "Not updating game server as auto update was set to 0. Starting Server"
fi

# Defensive guard: SRCDS_X64=1 but the 64-bit binary is missing.
# Two possible binary paths depending on game / SDK version:
#   - /home/container/srcds_linux_x64        (older Source SDK)
#   - /home/container/bin/linux64/srcds_linux (newer GMod / Source 2013+)
# We accept EITHER. srcds_run picks the binary via -binary <name>;
# whichever path the operator's startup command points at is fine
# as long as one of them exists on disk.
#
# Common trap: the x86-64 beta branch is deprecated for newer
# Source titles (notably GMod). The 64-bit files now live on the
# DEFAULT branch under bin/linux64/. Recovery tries the legacy
# '-beta x86-64' first for backward compat, then accepts either
# path before deciding success/failure.
has_x64_binary() {
    [ -f /home/container/srcds_linux_x64 ] || \
    [ -f /home/container/bin/linux64/srcds_linux ]
}

# Always-on bridge between the two binary layouts. If steamcmd
# wrote the binary to bin/linux64/srcds_linux (newer layout) but
# the operator's startup command still uses '-binary srcds_linux_x64'
# (legacy egg field), create the symlink so srcds_run finds it
# without the operator having to edit the Startup tab. Idempotent
# (ln -sf re-points if needed, no-op when the link already matches).
if [ -f /home/container/bin/linux64/srcds_linux ] && [ ! -f /home/container/srcds_linux_x64 ]; then
    ln -sf bin/linux64/srcds_linux /home/container/srcds_linux_x64
fi

if [ "${SRCDS_X64}" == "1" ] && [ ! -z "${SRCDS_APPID}" ] && ! has_x64_binary; then
    echo -e "[entrypoint] SRCDS_X64=1 but no 64-bit binary on disk - running recovery fetch..."
    echo -e "[entrypoint] (checked srcds_linux_x64 and bin/linux64/srcds_linux)"
    set +e
    ./steamcmd/steamcmd.sh +force_install_dir /home/container +login anonymous +app_update ${SRCDS_APPID} -beta x86-64 validate +quit
    STEAMCMD_RC=$?
    set -e
    echo -e "[entrypoint] recovery steamcmd exited rc=${STEAMCMD_RC}"
    if has_x64_binary; then
        echo -e "ENTRYPOINT_FETCH_X64_OK"
        # Auto-bridge legacy and new binary paths. The newer Source
        # layout puts the 64-bit binary at bin/linux64/srcds_linux,
        # but existing eggs/startup commands still reference the
        # legacy ./srcds_linux_x64 path. Symlink so srcds_run -binary
        # srcds_linux_x64 finds the binary regardless of which path
        # steamcmd actually wrote. ln -sf is idempotent on re-run.
        if [ -f /home/container/bin/linux64/srcds_linux ] && [ ! -f /home/container/srcds_linux_x64 ]; then
            echo -e "[entrypoint] 64-bit binary lives at bin/linux64/srcds_linux (newer Source layout)."
            echo -e "[entrypoint] Creating symlink: srcds_linux_x64 -> bin/linux64/srcds_linux"
            ln -sf bin/linux64/srcds_linux /home/container/srcds_linux_x64
        fi
    else
        echo -e "ENTRYPOINT_FETCH_X64_FAIL"
        echo -e "[entrypoint] ============================================================"
        echo -e "[entrypoint] FATAL: 64-bit binary still missing after recovery."
        echo -e "[entrypoint] steamcmd exit code: ${STEAMCMD_RC}"
        echo -e "[entrypoint] Looked at:"
        echo -e "[entrypoint]   - /home/container/srcds_linux_x64"
        echo -e "[entrypoint]   - /home/container/bin/linux64/srcds_linux"
        echo -e "[entrypoint] ---"
        echo -e "[entrypoint] Self-diagnostic: srcds-like binaries found on disk:"
        # Cap at 30 results so a runaway find on a misconfigured
        # data dir can't flood the console. Limit depth to 5 so
        # we don't traverse into massive workshop dirs.
        FOUND_BINARIES=$(find /home/container -maxdepth 5 -type f \( -name "srcds*" -o -name "*srcds_*" \) 2>/dev/null | head -30)
        if [ -z "${FOUND_BINARIES}" ]; then
            echo -e "[entrypoint]   (none - steamcmd may have failed silently)"
        else
            echo "${FOUND_BINARIES}" | while read -r f; do
                echo -e "[entrypoint]   ${f}"
            done
        fi
        echo -e "[entrypoint] ---"
        echo -e "[entrypoint] If you see a binary above that looks like the right server"
        echo -e "[entrypoint] executable but at an unexpected path, please report this in"
        echo -e "[entrypoint] a ticket - the entrypoint check needs updating to recognise"
        echo -e "[entrypoint] the new layout."
        echo -e "[entrypoint] ---"
        echo -e "[entrypoint] Recovery:"
        echo -e "[entrypoint]   - Click Reinstall on the server's Settings tab. This WIPES the"
        echo -e "[entrypoint]     server volume (addons, configs, lua, workshop downloads, all"
        echo -e "[entrypoint]     server files), re-pulls the latest yolk image, and re-runs"
        echo -e "[entrypoint]     the egg install. Back up via SFTP first if you need to keep"
        echo -e "[entrypoint]     anything from this server's data directory."
        echo -e "[entrypoint]   - OR set SRCDS_X64=0 in the Startup tab to fall back to the"
        echo -e "[entrypoint]     32-bit binary (no reinstall needed)."
        echo -e "[entrypoint] ============================================================"
        # Exit instead of letting srcds_run fail with a cryptic
        # error. Status 78 = 'configuration error' per sysexits.
        exit 78
    fi
fi

# Conversely - SRCDS_X64=0 (or unset) but ONLY the 64-bit binary
# is on disk. Happens if an operator went 0 -> 1 -> 0 quickly and
# left the system in a mid-state. Exit early with a clear message
# rather than letting srcds_run fail.
if [ "${SRCDS_X64}" != "1" ] && [ -z "${SRCDS_BETAID}" ] && [ ! -z "${SRCDS_APPID}" ] && [ ! -f /home/container/srcds_linux ] && [ -f /home/container/srcds_linux_x64 ]; then
    echo -e "[entrypoint] SRCDS_X64=0 but only the 64-bit binary is on disk - fetching default branch..."
    set +e
    ./steamcmd/steamcmd.sh +force_install_dir /home/container +login anonymous +app_update ${SRCDS_APPID} validate +quit
    set -e
    if [ ! -f /home/container/srcds_linux ]; then
        echo -e "[entrypoint] FATAL: srcds_linux still missing after recovery fetch. Toggle SRCDS_X64=1 or click Reinstall."
        exit 78
    fi
fi

# Replace Startup Variables
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

# Run the Server
eval ${MODIFIED_STARTUP}
