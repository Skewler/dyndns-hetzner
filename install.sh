#!/usr/bin/env bash
# =============================================================================
# install.sh — Installiert den Hetzner DynDNS Updater als systemd-Service
# Ausführen mit: sudo bash install.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Hetzner DynDNS Updater — Installation ==="

# 1. Abhängigkeiten prüfen
for cmd in curl dig; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "FEHLER: '${cmd}' ist nicht installiert."
        echo "  → sudo apt install curl dnsutils   (Debian/Ubuntu)"
        echo "  → sudo dnf install curl bind-utils  (Fedora/RHEL)"
        exit 1
    fi
done

# 2. Script installieren
install -m 0755 "${SCRIPT_DIR}/dyndns-hetzner.sh" /usr/local/bin/dyndns-hetzner.sh
echo "✓ Script nach /usr/local/bin/dyndns-hetzner.sh kopiert"

# 3. Konfiguration anlegen (nur wenn noch nicht vorhanden)
mkdir -p /etc/dyndns-hetzner
if [[ ! -f /etc/dyndns-hetzner/dyndns-hetzner.conf ]]; then
    install -m 0600 "${SCRIPT_DIR}/dyndns-hetzner.conf" /etc/dyndns-hetzner/dyndns-hetzner.conf
    echo "✓ Konfiguration nach /etc/dyndns-hetzner/dyndns-hetzner.conf kopiert"
    echo "  ⚠ WICHTIG: Konfiguration jetzt anpassen!"
    echo "  → sudo nano /etc/dyndns-hetzner/dyndns-hetzner.conf"
else
    echo "✓ Konfiguration existiert bereits — wird nicht überschrieben"
fi

# 4. Log-Datei vorbereiten
touch /var/log/dyndns-hetzner.log
chmod 0644 /var/log/dyndns-hetzner.log
echo "✓ Log-Datei unter /var/log/dyndns-hetzner.log angelegt"

# 5. Systemd-Service installieren
install -m 0644 "${SCRIPT_DIR}/dyndns-hetzner.service" /etc/systemd/system/dyndns-hetzner.service
systemctl daemon-reload
echo "✓ Systemd-Service installiert"

echo ""
echo "=== Installation abgeschlossen ==="
echo ""
echo "Nächste Schritte:"
echo "  1. Konfiguration anpassen:   sudo nano /etc/dyndns-hetzner/dyndns-hetzner.conf"
echo "  2. Service starten:          sudo systemctl start dyndns-hetzner"
echo "  3. Autostart aktivieren:     sudo systemctl enable dyndns-hetzner"
echo "  4. Status prüfen:            sudo systemctl status dyndns-hetzner"
echo "  5. Logs verfolgen:           tail -f /var/log/dyndns-hetzner.log"
echo "                               journalctl -u dyndns-hetzner -f"
