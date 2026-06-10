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

# Defensive guard: SRCDS_X64=1 but srcds_linux_x64 still missing
# after the update above. Happens when AUTO_UPDATE=0, network
# blip during steamcmd, or the toggle 0->1 didn't trigger a full
# fresh fetch.
#
# Retries once with explicit '-beta x86-64 validate' then HARD-FAILS
# with a clear message if still missing. Previous versions of
# this entrypoint silently fell through to srcds_run which then
# crashed with the cryptic 'Source Engine binary not found' error.
# Now: the operator sees ENTRYPOINT_FETCH_X64_OK / FAIL markers
# in the panel console AND the entrypoint exits with a clear
# remediation message instead of letting srcds_run fail.
if [ "${SRCDS_X64}" == "1" ] && [ ! -z "${SRCDS_APPID}" ] && [ ! -f /home/container/srcds_linux_x64 ]; then
    echo -e "[entrypoint] SRCDS_X64=1 but srcds_linux_x64 missing - running recovery fetch..."
    set +e
    ./steamcmd/steamcmd.sh +force_install_dir /home/container +login anonymous +app_update ${SRCDS_APPID} -beta x86-64 validate +quit
    STEAMCMD_RC=$?
    set -e
    echo -e "[entrypoint] recovery steamcmd exited rc=${STEAMCMD_RC}"
    if [ -f /home/container/srcds_linux_x64 ]; then
        echo -e "ENTRYPOINT_FETCH_X64_OK"
        echo -e "[entrypoint] srcds_linux_x64 now present, continuing to srcds_run."
    else
        echo -e "ENTRYPOINT_FETCH_X64_FAIL"
        echo -e "[entrypoint] ============================================================"
        echo -e "[entrypoint] FATAL: srcds_linux_x64 still missing after recovery."
        echo -e "[entrypoint] steamcmd exit code: ${STEAMCMD_RC}"
        echo -e "[entrypoint] Possible causes:"
        echo -e "[entrypoint]   1. The x86-64 branch is unavailable for AppID ${SRCDS_APPID}"
        echo -e "[entrypoint]   2. steamcmd network/auth failure (check log above)"
        echo -e "[entrypoint]   3. Anonymous user lacks branch access (use STEAM_USER + auth)"
        echo -e "[entrypoint] Recovery:"
        echo -e "[entrypoint]   - Click Reinstall on the server's Settings tab (non-destructive"
        echo -e "[entrypoint]     since v0.2.71 - preserves your addons, configs, lua)."
        echo -e "[entrypoint]   - OR set SRCDS_X64=0 to fall back to the 32-bit binary."
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
