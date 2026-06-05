#!/usr/bin/with-contenv bash

set -e

# ─────────────────────────────────────────────────────────────
# Create CUPS data directories in the persistent HA share
# ─────────────────────────────────────────────────────────────
mkdir -p /share/cups/cache
mkdir -p /share/cups/logs
mkdir -p /share/cups/state
mkdir -p /share/cups/config
mkdir -p /share/cups/config/ppd
mkdir -p /share/cups/config/ssl

# Set proper permissions
chown -R root:lp /share/cups
chmod -R 775 /share/cups

write_cupsd_conf() {
    # Write this after migration so legacy cupsd.conf files cannot silently
    # disable printer sharing, remote access, or discovery on restart.
    cat > /share/cups/config/cupsd.conf << 'EOL'
# Listen on all interfaces so clients can print over the network.
Listen 0.0.0.0:631
ServerAlias *

# Share printers and advertise them with DNS-SD/AirPrint where available.
Browsing Yes
BrowseLocalProtocols dnssd
BrowseWebIF Yes
DefaultShared Yes

# Enable the web interface.
WebInterface Yes

# Default settings.
DefaultAuthType None
JobSheets none,none
PreserveJobHistory No

# Allow access from private/local networks.
<Location />
  Order allow,deny
  Allow localhost
  Allow @LOCAL
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

# Allow remote administration from private/local networks.
<Location /admin>
  Order allow,deny
  Allow localhost
  Allow @LOCAL
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

# Allow clients to discover printers/classes and submit jobs.
<Location /printers>
  Order allow,deny
  Allow localhost
  Allow @LOCAL
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

<Location /classes>
  Order allow,deny
  Allow localhost
  Allow @LOCAL
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

# Allow job management from private/local networks.
<Location /jobs>
  Order allow,deny
  Allow localhost
  Allow @LOCAL
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>
EOL
}

share_existing_printers() {
    # DefaultShared only affects newly-created queues. Existing printers keep
    # their own Shared setting, so normalize persisted queues before CUPS starts.
    local printers_conf=/share/cups/config/printers.conf

    [ -f "$printers_conf" ] || touch "$printers_conf"
    [ -s "$printers_conf" ] || return 0

    awk '
        /^<DefaultPrinter[[:space:]]/ || /^<Printer[[:space:]]/ {
            in_printer = 1
            saw_shared = 0
            print
            next
        }
        in_printer && /^[[:space:]]*Shared[[:space:]]+/ {
            if (!saw_shared) {
                print "Shared Yes"
                saw_shared = 1
            }
            next
        }
        in_printer && (/^<\/DefaultPrinter>$/ || /^<\/Printer>$/) {
            if (!saw_shared) {
                print "Shared Yes"
            }
            in_printer = 0
            saw_shared = 0
            print
            next
        }
        { print }
    ' "$printers_conf" > "${printers_conf}.tmp"

    if ! cmp -s "$printers_conf" "${printers_conf}.tmp"; then
        cp "$printers_conf" "${printers_conf}.pre-share"
        mv "${printers_conf}.tmp" "$printers_conf"
        echo "Enabled sharing for existing CUPS printer queues."
    else
        rm -f "${printers_conf}.tmp"
    fi
}


wait_for_cups() {
    for _ in $(seq 1 20); do
        if lpstat -r >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    echo "Error: CUPS did not start in time."
    return 1
}

create_proxy_printer_queue() {
    local name="$1"
    local uri="$2"

    if [ -z "$name" ] || [ -z "$uri" ]; then
        return 0
    fi

    echo "Recreating ${name} as a local CUPS proxy queue for ${uri}..."

    # Remove an existing queue with this name first. This intentionally replaces
    # remote/discovered CUPS queues, because those cannot have their sharing
    # state changed by CUPS and cause: "Cannot change printer-is-shared for
    # remote queues."
    lpadmin -x "$name" >/dev/null 2>&1 || true
    rm -f "/share/cups/config/ppd/${name}.ppd" 2>/dev/null || true

    # Create a permanent local queue that forwards jobs to the upstream IPP
    # printer. The local queue can then be shared from this add-on.
    lpadmin \
        -p "$name" \
        -E \
        -v "$uri" \
        -m everywhere \
        -D "$name" \
        -o printer-is-shared=true

    lpadmin -d "$name" || true
    cupsaccept "$name" || true
    cupsenable "$name" || true

    echo "${name} created and shared."
}

start_discovery_services() {
    # CUPS uses Avahi/D-Bus to publish shared queues for Bonjour/AirPrint.
    # Start them opportunistically; printing by direct IPP URL still works if a
    # platform image does not provide these daemons.
    mkdir -p /run/dbus /run/avahi-daemon

    if command -v dbus-daemon >/dev/null 2>&1 && ! pgrep -x dbus-daemon >/dev/null 2>&1; then
        dbus-daemon --system --fork || echo "Warning: failed to start dbus-daemon; DNS-SD printer discovery may not work."
    fi

    if command -v avahi-daemon >/dev/null 2>&1 && ! pgrep -x avahi-daemon >/dev/null 2>&1; then
        avahi-daemon --daemonize --no-drop-root || echo "Warning: failed to start avahi-daemon; DNS-SD printer discovery may not work."
    fi
}

# Migrate legacy data from /data/cups to /share/cups if present.
if [ -d /data/cups/config ] && [ ! -f /share/cups/config/.migrated ]; then
    echo "Migrating CUPS data from /data/cups to /share/cups..."
    cp -r /data/cups/config/printers.conf /share/cups/config/ 2>/dev/null || true
    cp -r /data/cups/config/ppd/* /share/cups/config/ppd/ 2>/dev/null || true
    cp -r /data/cups/config/ssl/* /share/cups/config/ssl/ 2>/dev/null || true
    cp -r /data/cups/cache/* /share/cups/cache/ 2>/dev/null || true
    cp -r /data/cups/logs/* /share/cups/logs/ 2>/dev/null || true
    cp -r /data/cups/state/* /share/cups/state/ 2>/dev/null || true
    touch /share/cups/config/.migrated
    echo "Migration complete."
fi

# Always own cupsd.conf so stale migrated config cannot break sharing.
write_cupsd_conf
share_existing_printers

# ─────────────────────────────────────────────────────────────
# Replace /etc/cups with a directory-level symlink so that
# CUPS atomic file writes (write .N, rename .O, rename .N)
# operate inside the persistent storage instead of replacing
# individual file symlinks with ephemeral real files.
# ─────────────────────────────────────────────────────────────

if [ -d /etc/cups ] && [ ! -L /etc/cups ]; then
    echo "Replacing /etc/cups directory with symlink to /share/cups/config..."

    # Copy any default config files from the package-installed
    # /etc/cups/ (e.g. cups-files.conf) that don't yet exist in
    # the persistent storage.
    for item in /etc/cups/*; do
        [ -e "$item" ] || continue
        base="$(basename "$item")"
        # Skip files/dirs we manage ourselves or that may be
        # stale from a previous file-level symlink approach.
        case "$base" in
            cupsd.conf|printers.conf|printers.conf.O|ppd|ssl)
                continue
                ;;
        esac
        if [ ! -e "/share/cups/config/$base" ]; then
            cp -r "$item" "/share/cups/config/$base"
            echo "  Copied default $base to persistent storage."
        fi
    done

    rm -rf /etc/cups
    ln -sf /share/cups/config /etc/cups
    echo "/etc/cups → /share/cups/config"
else
    # Already a symlink or does not exist — just ensure it.
    rm -rf /etc/cups
    ln -sf /share/cups/config /etc/cups
fi

# Verify printers.conf exists in the persistent location.
touch /share/cups/config/printers.conf

# Install user-supplied printer driver .deb (e.g. Canon UFR II for MF4412)
DRIVER_DEB=$(jq -r '.printer_driver_deb // empty' /data/options.json 2>/dev/null || true)
if [ -n "$DRIVER_DEB" ]; then
    DRIVER_PATH="/share/${DRIVER_DEB}"
    if [ -f "$DRIVER_PATH" ]; then
        echo "Installing printer driver from ${DRIVER_PATH}..."
        EXTRACT_DIR=$(mktemp -d)
        dpkg -x "$DRIVER_PATH" "$EXTRACT_DIR"
        # Copy CUPS filters
        if [ -d "${EXTRACT_DIR}/usr/lib/cups/filter" ]; then
            cp -r "${EXTRACT_DIR}/usr/lib/cups/filter/." /usr/lib/cups/filter/
            chmod 755 /usr/lib/cups/filter/*
        fi
        # Copy shared libraries
        if [ -d "${EXTRACT_DIR}/usr/lib" ]; then
            find "${EXTRACT_DIR}/usr/lib" -name "*.so*" -exec cp {} /usr/lib/ \;
        fi
        # Copy PPD files
        if [ -d "${EXTRACT_DIR}/usr/share/cups/model" ]; then
            cp -r "${EXTRACT_DIR}/usr/share/cups/model/." /usr/share/cups/model/
        fi
        rm -rf "$EXTRACT_DIR"
        echo "Printer driver installed."
    else
        echo "Warning: printer_driver_deb set to '${DRIVER_DEB}' but /share/${DRIVER_DEB} was not found."
    fi
fi

start_discovery_services

# Verify printer drivers are available
echo "Available printer drivers:"
lpinfo -m 2>/dev/null | head -20 || echo "CUPS not yet running; drivers will be listed after start."

# Optional local proxy queue. This is useful when an auto-discovered remote
# CUPS queue needs to be re-published by this add-on: CUPS will not let remote
# queues change printer-is-shared, so the queue must be recreated locally.
PROXY_PRINTER_NAME=$(jq -r '.proxy_printer_name // empty' /data/options.json 2>/dev/null || true)
PROXY_PRINTER_URI=$(jq -r '.proxy_printer_uri // empty' /data/options.json 2>/dev/null || true)

# Start CUPS in the background briefly so startup can configure any requested
# proxy queue through CUPS itself, then wait on it to keep the container alive.
echo "Starting CUPS..."
/usr/sbin/cupsd -f &
CUPSD_PID=$!

trap 'kill "$CUPSD_PID" 2>/dev/null || true; wait "$CUPSD_PID" 2>/dev/null || true' TERM INT

if [ -n "$PROXY_PRINTER_URI" ]; then
    if [ -z "$PROXY_PRINTER_NAME" ]; then
        PROXY_PRINTER_NAME="proxy_printer"
    fi

    wait_for_cups
    create_proxy_printer_queue "$PROXY_PRINTER_NAME" "$PROXY_PRINTER_URI"
fi

echo "CUPS is running."
wait "$CUPSD_PID"
