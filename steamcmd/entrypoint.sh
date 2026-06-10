#!/bin/bash

#
# Copyright (c) 2021 Matthew Penner and contributors
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

# Set environment for Steam Proton
if [ -f "/usr/local/bin/proton" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
	    mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
        export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"
        # Fix for pipx with protontricks
        export PATH=$PATH:/root/.local/bin
    else
        echo -e "----------------------------------------------------------------------------------"
        echo -e "WARNING!!! Proton needs variable SRCDS_APPID, else it will not work. Please add it"
        echo -e "Server stops now"
        echo -e "----------------------------------------------------------------------------------"
        exit 1
        fi
fi

# Switch to the container's working directory
cd /home/container || exit 1

## Update server via SteamCMD if AUTO_UPDATE is 1 or not set
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    echo -e "Checking for game server updates..."
    # Check for set App ID
    if [ ! -z ${SRCDS_APPID} ]; then
        # Set default credentials if they are missing
        if [ "${STEAM_USER}" == "" ]; then
            echo -e "Steam user is not set. Defaulting to anonymous user."
            STEAM_USER=anonymous
            STEAM_PASS=""
            STEAM_AUTH=""
        fi
        # SRCDS_X64 -> -beta x86-64 derivation. The gmod (and other
        # Source) eggs let operators toggle 64-bit binaries via the
        # SRCDS_X64 env var; the corresponding steamcmd branch is
        # 'x86-64'. The install script (run on first install /
        # reinstall) already derives this, but the per-start update
        # below did NOT - so toggling SRCDS_X64 from the panel
        # without a reinstall left srcds_linux_x64 missing forever
        # and the server crashed at boot with
        #   ERROR: Source Engine binary 'srcds_linux_x64' not found
        # Now: if SRCDS_X64=1 and the operator hasn't explicitly
        # pinned a different SRCDS_BETAID, default it to x86-64 for
        # the duration of this steamcmd run. Explicit SRCDS_BETAID
        # still wins (lets advanced users pick prerelease / dev / ...).
        if [ "${SRCDS_X64}" == "1" ] && [ -z "${SRCDS_BETAID}" ]; then
            echo -e "[entrypoint] SRCDS_X64=1 detected, using -beta x86-64 for steamcmd update"
            SRCDS_BETAID="x86-64"
        fi
        # Run SteamCMD
        ./steamcmd/steamcmd.sh +force_install_dir /home/container +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) +app_update 1007 +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) ${INSTALL_FLAGS} $( [[ "${VALIDATE}" == "1" ]] && printf %s 'validate' ) +quit
    else
        echo -e "No App ID set! Skipping check."
    fi
else
    echo -e "Skipping game server update check; Auto Update is set to 0."
fi

# Defensive guard: if SRCDS_X64=1 but srcds_linux_x64 still isn't
# on disk after the update (steamcmd failed silently, network blip,
# AUTO_UPDATE=0 etc.), fetch JUST the x86-64 branch one more time
# instead of letting srcds_run crash on the missing binary.
#
# Validate flag forces steamcmd to re-fetch any files whose
# content hash doesn't match the manifest - critical when the
# install was originally done on the 32-bit branch and we're now
# switching to 64-bit (the per-file hashes differ).
#
# We capture steamcmd's exit code and emit explicit
# ENTRYPOINT_FETCH_X64_OK / ENTRYPOINT_FETCH_X64_FAIL markers so
# the panel's console parser (and the operator) can tell at a
# glance whether the recovery worked. Without these markers the
# previous silent fallthrough left the operator guessing why the
# server still failed to start.
if [ "${SRCDS_X64}" == "1" ] && [ ! -z ${SRCDS_APPID} ] && [ ! -f /home/container/srcds_linux_x64 ]; then
    echo -e "[entrypoint] SRCDS_X64=1 but srcds_linux_x64 missing - fetching x86-64 branch (validate)..."
    set +e
    ./steamcmd/steamcmd.sh +force_install_dir /home/container +login anonymous +app_update ${SRCDS_APPID} -beta x86-64 validate +quit
    STEAMCMD_X64_RC=$?
    set -e
    echo -e "[entrypoint] steamcmd x86-64 fetch exited rc=${STEAMCMD_X64_RC}"
    if [ -f /home/container/srcds_linux_x64 ]; then
        echo -e "ENTRYPOINT_FETCH_X64_OK"
        echo -e "[entrypoint] srcds_linux_x64 now present, continuing."
    else
        echo -e "ENTRYPOINT_FETCH_X64_FAIL"
        echo -e "[entrypoint] srcds_linux_x64 STILL missing after recovery fetch (rc=${STEAMCMD_X64_RC})."
        echo -e "[entrypoint] Likely cause: x86-64 branch unavailable for this AppID, steamcmd network failure, or anonymous user lacks branch access."
        echo -e "[entrypoint] To recover: click Reinstall on the server's Settings tab (preserves your addons/configs)."
    fi
fi

# Replace Startup Variables
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')

# Run the Server
echo -e "Starting server..."
echo -e ":/home/container$ ${MODIFIED_STARTUP}"
eval ${MODIFIED_STARTUP}
