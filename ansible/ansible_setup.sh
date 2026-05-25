#!/bin/sh
# uv-based local Ansible control-node installer for RHEL/Rocky/Alma-like hosts.
# One-liner:
#   curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo sh
set -eu

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
# Keep ANSIBLE_CORE_VERSION as a legacy input name for old notes, but install
# the Ansible community package. ansible-core itself uses 2.x versions.
ANSIBLE_VERSION="${ANSIBLE_VERSION:-${ANSIBLE_CORE_VERSION:-13.4.0}}"
ANSIBLE_HOME="${ANSIBLE_HOME:-/opt/ansible}"
ANSIBLE_RUNTIME="${ANSIBLE_RUNTIME:-${PYTHON_VERSION}_${ANSIBLE_VERSION}}"
ANSIBLE_VENV_PATH="${ANSIBLE_VENV_PATH:-${ANSIBLE_HOME}/apps/${ANSIBLE_RUNTIME}}"
ANSIBLE_UV_MARKER="${ANSIBLE_HOME}/.ansible-uv-installer"
# Default concrete layout: /opt/ansible/apps/<runtime>, /opt/ansible/current,
# /etc/profile.d/ansible.sh, /etc/ansible, ansible-local-switch, adoc.
# Package install pattern: uv pip install --python /opt/ansible/apps/<runtime>/bin/python ansible==${ANSIBLE_VERSION} argcomplete.
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main}"
UV_BIN="${UV_BIN:-}"

log() { printf '[ansible-installer] %s\n' "$*"; }
fail() { printf '[ansible-installer] ERROR: %s\n' "$*" >&2; exit 1; }

is_ansible_uv_installation() {
  [ -f "$ANSIBLE_UV_MARKER" ] && return 0
  [ -d "$ANSIBLE_HOME/apps" ] && [ -x /usr/local/sbin/ansible-local-switch ] && return 0
  [ -r /etc/profile.d/ansible.sh ] && grep -q 'ANSIBLE_UV_INSTALLER=1' /etc/profile.d/ansible.sh && return 0
  return 1
}

detect_foreign_ansible_installation() {
  if is_ansible_uv_installation; then
    log "This is an ansible-uv managed installation; continuing and upgrading runtime if needed"
    return 0
  fi

  reasons=""

  if command -v rpm >/dev/null 2>&1; then
    rpm_matches="$(rpm -q ansible ansible-core 2>/dev/null | grep -v 'is not installed' || true)"
    if [ -n "$rpm_matches" ]; then
      reasons="${reasons}
- RPM-managed Ansible package detected:
${rpm_matches}"
    fi
  fi

  if command -v python3 >/dev/null 2>&1; then
    pip_matches="$(python3 -m pip show ansible ansible-core 2>/dev/null | awk '/^Name: / || /^Version: / {print}' || true)"
    if [ -n "$pip_matches" ]; then
      reasons="${reasons}
- pip-managed Ansible package detected:
${pip_matches}"
    fi
  fi

  ansible_path="$(command -v ansible 2>/dev/null || true)"
  case "$ansible_path" in
    ""|"$ANSIBLE_HOME"/current/bin/ansible|"$ANSIBLE_HOME"/apps/*/bin/ansible) ;;
    *)
      reasons="${reasons}
- Existing ansible command detected outside ansible-uv: ${ansible_path}"
      ;;
  esac

  if [ -r /etc/profile.d/ansible.sh ] && ! grep -q 'ANSIBLE_UV_INSTALLER=1' /etc/profile.d/ansible.sh; then
    reasons="${reasons}
- Existing /etc/profile.d/ansible.sh without ansible-uv marker detected. This may come from ansible.bitbull.ch or another installer."
  fi

  if [ -e /etc/ansible ] && [ ! -L /etc/ansible ] && [ ! -f "$ANSIBLE_UV_MARKER" ]; then
    reasons="${reasons}
- Existing /etc/ansible directory detected. This may be from RPM, ansible.bitbull.ch, pip, or manual installation."
  fi

  if [ -n "$reasons" ]; then
    cat >&2 <<EOF_CONFLICT
[ansible-installer] ERROR: Foreign Ansible installation detected.

This installer intentionally stops instead of mixing ansible-uv with another
Ansible installation method such as RPM, ansible.bitbull.ch, pip, or a manual
/usr/local installation.
${reasons}

Please remove or migrate the existing Ansible installation first, then rerun:
  curl -L ansible-uv.bitbull.ch | sudo sh

If this host is already managed by ansible-uv, make sure ${ANSIBLE_UV_MARKER}
exists or /etc/profile.d/ansible.sh contains ANSIBLE_UV_INSTALLER=1.
EOF_CONFLICT
    exit 1
  fi
}

install_repo_file() {
  src="$1"
  dest="$2"
  mode="$3"
  owner_group="$4"
  tmp="${dest}.tmp.$$"
  mkdir -p "$(dirname "$dest")"
  curl -fsSL "$RAW_BASE/$src" -o "$tmp"
  chmod "$mode" "$tmp"
  chown "$owner_group" "$tmp"
  mv -f "$tmp" "$dest"
}

[ "$(id -u)" -eq 0 ] || fail "run as root, e.g. curl -L .../ansible_setup.sh | sudo sh"
detect_foreign_ansible_installation

[ -r /etc/os-release ] || fail "missing /etc/os-release"
# shellcheck disable=SC1091
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *rhel*|*fedora*|*centos*|*rocky*|*almalinux*|*ol*) ;;
  *) fail "unsupported OS: ID=${ID:-unknown} ID_LIKE=${ID_LIKE:-unknown}" ;;
esac
command -v dnf >/dev/null 2>&1 || fail "dnf is required"

log "Installing required OS packages"
dnf install -y curl ca-certificates tar gzip bash-completion python3 python3-devel gcc openssl-devel libffi-devel less util-linux

if [ -z "$UV_BIN" ]; then
  for candidate in /usr/local/bin/uv /usr/bin/uv "$HOME/.local/bin/uv"; do
    if [ -x "$candidate" ]; then UV_BIN="$candidate"; break; fi
  done
fi
if [ -z "$UV_BIN" ]; then
  log "Installing uv into /usr/local/bin"
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
  UV_BIN=/usr/local/bin/uv
fi
[ -x "$UV_BIN" ] || fail "uv not executable at $UV_BIN"

log "Creating ansible group and shared /opt/ansible tree"
getent group ansible >/dev/null 2>&1 || groupadd --system ansible
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ] && id "${SUDO_USER}" >/dev/null 2>&1; then
  log "Adding ${SUDO_USER} to ansible group"
  usermod -aG ansible "${SUDO_USER}"
fi
install -d -o root -g ansible -m 2770 \
  "$ANSIBLE_HOME" \
  "$ANSIBLE_HOME/apps" \
  "$ANSIBLE_HOME/inventory" \
  "$ANSIBLE_HOME/logs" \
  "$ANSIBLE_HOME/tmp" \
  "$ANSIBLE_HOME/playbooks" \
  "$ANSIBLE_HOME/projects" \
  "$ANSIBLE_HOME/roles"

if [ -x "$ANSIBLE_VENV_PATH/bin/python" ]; then
  log "Reusing existing uv runtime at $ANSIBLE_VENV_PATH"
else
  log "Creating uv runtime at $ANSIBLE_VENV_PATH"
  "$UV_BIN" venv --python "$PYTHON_VERSION" "$ANSIBLE_VENV_PATH"
fi

log "Installing/upgrading ansible==${ANSIBLE_VERSION} and argcomplete"
# Reruns use the equivalent of: uv pip install --upgrade ansible==${ANSIBLE_VERSION} argcomplete
"$UV_BIN" pip install --upgrade --python "$ANSIBLE_VENV_PATH/bin/python" "ansible==${ANSIBLE_VERSION}" argcomplete

log "Updating active runtime symlink"
ln -sfn "$ANSIBLE_VENV_PATH" "$ANSIBLE_HOME/current.tmp"
mv -Tf "$ANSIBLE_HOME/current.tmp" "$ANSIBLE_HOME/current"

if [ ! -e "$ANSIBLE_HOME/ansible.cfg" ]; then
  log "Creating minimal ansible.cfg"
  cat > "$ANSIBLE_HOME/ansible.cfg" <<'CFG'
[defaults]
inventory=/opt/ansible/inventory
roles_path=/opt/ansible/roles
log_path=/opt/ansible/logs/ansible.log
host_key_checking=False
retry_files_enabled=False
deprecation_warnings=False
interpreter_python=auto_silent
forks=20

[ssh_connection]
pipelining=True
CFG
fi

if [ ! -e "$ANSIBLE_HOME/inventory/localhost" ]; then
  log "Creating localhost inventory seed"
  printf '%s\n' 'localhost ansible_connection=local ansible_become=False' > "$ANSIBLE_HOME/inventory/localhost"
fi

log "Installing /etc/profile.d/ansible.sh from repository"
install_repo_file "ansible/files/etc/profile.d/ansible.sh" /etc/profile.d/ansible.sh 0644 root:root
# Render install-time defaults into the profile template.
sed -i \
  -e "s|@PYTHON_VERSION@|${PYTHON_VERSION}|g" \
  -e "s|@ANSIBLE_VERSION@|${ANSIBLE_VERSION}|g" \
  /etc/profile.d/ansible.sh

log "Installing ansible-local-switch from repository"
install_repo_file "ansible/files/usr/local/sbin/ansible-local-switch" /usr/local/sbin/ansible-local-switch 0750 root:ansible
ln -sfn /usr/local/sbin/ansible-local-switch /usr/local/bin/ansible-local-switch

log "Installing adoc helper from this repository"
install_repo_file "ansible/files/usr/local/bin/adoc" /usr/local/bin/adoc 0755 root:root

if [ -d /etc/bash_completion.d ]; then
  log "Installing argcomplete hook"
  "$ANSIBLE_VENV_PATH/bin/register-python-argcomplete" ansible > /etc/bash_completion.d/ansible || true
fi

if [ ! -e /etc/ansible ]; then
  ln -s "$ANSIBLE_HOME" /etc/ansible
fi

log "Marking installation as ansible-uv managed"
cat > "$ANSIBLE_UV_MARKER" <<EOF_MARKER
ANSIBLE_UV_INSTALLER=1
ANSIBLE_HOME=$ANSIBLE_HOME
PYTHON_VERSION=$PYTHON_VERSION
ANSIBLE_VERSION=$ANSIBLE_VERSION
ANSIBLE_RUNTIME=$ANSIBLE_RUNTIME
RAW_BASE=$RAW_BASE
EOF_MARKER

log "Applying ownership and permissions"
chown -R root:ansible "$ANSIBLE_HOME"
chmod -R ug+rwX,o-rwx "$ANSIBLE_HOME"
find "$ANSIBLE_HOME" -type d -exec chmod g+s {} +

log "Done. Active runtime: $ANSIBLE_RUNTIME"
"$ANSIBLE_VENV_PATH/bin/ansible" --version | sed -n '1,8p'
printf '\nActivate in the current shell with:\n  source /etc/profile.d/ansible.sh\n'
