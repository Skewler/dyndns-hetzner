#!/usr/bin/env bash
# =============================================================================
# dyndns-hetzner.sh — Hetzner DynDNS Updater
# Vergleicht die externe IP mit dem DNS-Eintrag und aktualisiert bei Bedarf.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------
CONFIG_FILE="/etc/dyndns-hetzner/dyndns-hetzner.conf"
LOG_FILE="/var/log/dyndns-hetzner.log"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }

# ---------------------------------------------------------------------------
# Konfiguration laden
# ---------------------------------------------------------------------------
load_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Konfigurationsdatei nicht gefunden: ${CONFIG_FILE}"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"

    local missing=()
    [[ -z "${DOMAIN:-}" ]]               && missing+=("DOMAIN")
    [[ -z "${ZONE:-}" ]]                 && missing+=("ZONE")
    [[ -z "${AUTHENTICATION_TOKEN:-}" ]] && missing+=("AUTHENTICATION_TOKEN")
    [[ -z "${INTERVAL:-}" ]]             && missing+=("INTERVAL")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Fehlende Konfigurationsparameter: ${missing[*]}"
        exit 1
    fi

    log_info "Konfiguration geladen — Domain=${DOMAIN}, Zone=${ZONE}, Intervall=${INTERVAL}s"
}

# ---------------------------------------------------------------------------
# Externe IP abfragen
# ---------------------------------------------------------------------------
get_external_ip() {
    local ip
    ip="$(curl --silent --fail --max-time 10 -4 "https://ip.hetzner.com")" || {
        log_error "Externe IP konnte nicht abgefragt werden https://ip.hetzner.com"
        return 1
    }

    # Validierung: muss eine gültige IPv4-Adresse sein
    if [[ ! "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Ungültige externe IP erhalten: '${ip}'"
        return 1
    fi

    echo "${ip}"
}

# ---------------------------------------------------------------------------
# DNS-IP abfragen
# ---------------------------------------------------------------------------
get_dns_ip() {
    local ip
    ip="$(dig +short A "${ZONE}.${DOMAIN}" @213.239.242.238 | head -n1)" || {
        log_error "DNS-Abfrage fehlgeschlagen für ${ZONE}.${DOMAIN}"
        return 1
    }

    if [[ -z "${ip}" ]]; then
        log_warn "Kein A-Record für ${ZONE}.${DOMAIN} gefunden"
        echo ""
        return 0
    fi

    echo "${ip}"
}

# ---------------------------------------------------------------------------
# DNS-Eintrag über Hetzner API aktualisieren
# ---------------------------------------------------------------------------
update_dns_record() {
    local new_ip="$1"
    local http_code
    local response

    response="$(curl --silent --write-out "\n%{http_code}" --max-time 15 \
        --request POST \
        --header "Content-Type: application/json" \
        --header "Authorization: Bearer ${AUTHENTICATION_TOKEN}" \
        --data "{\"records\":[{\"value\":\"${new_ip}\",\"comment\":\"DynDNS with Hetzner CLI\"}]}" \
        "https://api.hetzner.cloud/v1/zones/${DOMAIN}/rrsets/${ZONE}/A/actions/set_records"
    )"

    http_code="$(echo "${response}" | tail -n1)"
    local body
    body="$(echo "${response}" | sed '$d')"

    if [[ "${http_code}" =~ ^2 ]]; then
        log_info "DNS-Update erfolgreich — ${ZONE}.${DOMAIN} -> ${new_ip} (HTTP ${http_code})"
        return 0
    else
        log_error "DNS-Update fehlgeschlagen (HTTP ${http_code}): ${body}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Einzelner Prüf-Durchlauf
# ---------------------------------------------------------------------------
check_and_update() {
    local ipExternal ipDomain

    ipExternal="$(get_external_ip)" || return 1
    ipDomain="$(get_dns_ip)"        || return 1

    if [[ "${ipExternal}" == "${ipDomain}" ]]; then
        log_info "IPs identisch (${ipExternal}) — kein Update nötig"
        return 0
    fi

    log_warn "IP-Abweichung erkannt — Extern: ${ipExternal}, DNS: ${ipDomain}"
    update_dns_record "${ipExternal}"
}

# ---------------------------------------------------------------------------
# Graceful Shutdown
# ---------------------------------------------------------------------------
shutdown() {
    log_info "Service wird beendet (Signal empfangen)"
    exit 0
}

trap shutdown SIGTERM SIGINT SIGHUP

# ---------------------------------------------------------------------------
# Main Loop
# ---------------------------------------------------------------------------
main() {
    load_config
    log_info "=== Hetzner DynDNS Updater gestartet ==="

    while true; do
        check_and_update || true
        sleep "${INTERVAL}" &
        wait $!
    done
}

main "$@"
