#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "error: run as root (use sudo)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_BIN="${NOCTALIA_GREETER_SESSION_BIN:-/usr/local/bin/noctalia-greeter-session}"
SYNCED_DATA_DIR="/var/lib/noctalia-greeter"

find_apply_appearance() {
  for candidate in \
    "${NOCTALIA_GREETER_APPLY_APPEARANCE:-}" \
    /usr/local/bin/noctalia-greeter-apply-appearance \
    /usr/bin/noctalia-greeter-apply-appearance \
    "${SCRIPT_DIR}/../build/noctalia-greeter-apply-appearance" \
    "${SCRIPT_DIR}/../build-user/noctalia-greeter-apply-appearance"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

resolve_greeter_user() {
  if [[ -n "${GREETER_USER:-}" ]]; then
    echo "${GREETER_USER}"
    return 0
  fi
  local helper=""
  if helper="$(find_apply_appearance)"; then
    if user="$("${helper}" --print-greeter-user 2>/dev/null)"; then
      echo "${user}"
      return 0
    fi
  fi
  echo "warn: could not resolve greeter user from greetd config; defaulting to 'greeter'" >&2
  echo "greeter"
}

APPLY_APPEARANCE="$(find_apply_appearance || true)"
GREETER_USER="$(resolve_greeter_user)"

echo "info: applying greetd PAM runtime module patch..."
"${SCRIPT_DIR}/setup_greetd_pam.sh"

echo "info: preparing greeter paths..."
mkdir -p "${SYNCED_DATA_DIR}"
chmod 0755 "${SYNCED_DATA_DIR}"
if id -u "${GREETER_USER}" >/dev/null 2>&1; then
  chown "${GREETER_USER}:${GREETER_USER}" "${SYNCED_DATA_DIR}"
fi
touch /var/log/noctalia-greeter.log /var/lib/noctalia-greeter/greeter.log /tmp/noctalia-greeter.log

if id -u "${GREETER_USER}" >/dev/null 2>&1; then
  chown "${GREETER_USER}:${GREETER_USER}" /var/log/noctalia-greeter.log \
    /var/lib/noctalia-greeter/greeter.log /tmp/noctalia-greeter.log
else
  echo "warn: user '${GREETER_USER}' does not exist yet; skipping log chown."
fi

chmod 0664 /var/log/noctalia-greeter.log /var/lib/noctalia-greeter/greeter.log /tmp/noctalia-greeter.log

if [[ -n "${APPLY_APPEARANCE}" ]]; then
  echo "info: installing greeter.conf via ${APPLY_APPEARANCE} --setup-system"
  GREETER_USER="${GREETER_USER}" "${APPLY_APPEARANCE}" --setup-system
else
  echo "error: noctalia-greeter-apply-appearance not found; build/install first." >&2
  exit 1
fi

echo "info: appearance sync target: ${SYNCED_DATA_DIR}"

if [[ ! -x "${SESSION_BIN}" ]]; then
  echo "warn: session launcher '${SESSION_BIN}' not found or not executable."
  echo "warn: install first via: sudo meson install -C build"
fi

echo
echo "System setup complete."
echo
echo "Next steps:"
echo "  1. Add to /etc/greetd/config.toml:"
echo
echo "     [default_session]"
echo "     command = \"${SESSION_BIN}\""
echo "     user = \"${GREETER_USER}\""
echo
echo "  2. Restart greetd:"
if command -v systemctl >/dev/null 2>&1; then
  echo "     sudo systemctl restart greetd"
fi
if command -v sv >/dev/null 2>&1; then
  echo "     sudo sv restart greetd"
fi
if ! command -v systemctl >/dev/null 2>&1 && ! command -v sv >/dev/null 2>&1; then
  echo "     restart greetd using your init system"
fi
