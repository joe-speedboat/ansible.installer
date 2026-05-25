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
# Default concrete layout: /opt/ansible/apps/<runtime>, /opt/ansible/current,
# /etc/profile.d/ansible.sh, /etc/ansible, ansible-local-switch, adoc.
# Package install pattern: uv pip install --python /opt/ansible/apps/<runtime>/bin/python ansible==${ANSIBLE_VERSION} argcomplete.
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main}"
UV_BIN="${UV_BIN:-}"

log() { printf '[ansible-installer] %s\n' "$*"; }
fail() { printf '[ansible-installer] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "run as root, e.g. curl -L .../ansible_setup.sh | sudo sh"
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

log "Installing ansible==${ANSIBLE_VERSION} and argcomplete"
"$UV_BIN" pip install --python "$ANSIBLE_VENV_PATH/bin/python" "ansible==${ANSIBLE_VERSION}" argcomplete

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

log "Installing /etc/profile.d/ansible.sh"
cat > /etc/profile.d/ansible.sh <<EOF_PROFILE
#!/bin/bash

export ANSIBLE_HOME="\${ANSIBLE_HOME:-/opt/ansible}"
export PYTHON_VERSION="\${PYTHON_VERSION:-${PYTHON_VERSION}}"
export ANSIBLE_VERSION="\${ANSIBLE_VERSION:-${ANSIBLE_CORE_VERSION:-${ANSIBLE_VERSION}}}"
# Compatibility for older shells/scripts that still inspect ANSIBLE_CORE_VERSION.
export ANSIBLE_CORE_VERSION="\${ANSIBLE_CORE_VERSION:-\${ANSIBLE_VERSION}}"
export ANSIBLE_RUNTIME="\${ANSIBLE_RUNTIME:-\${PYTHON_VERSION}_\${ANSIBLE_VERSION}}"

_ansible_user_overrides_venv=0
if [[ -r "\$HOME/.ansible.sh" ]]; then
  if grep -Eq '^[[:space:]]*(export[[:space:]]+)?ANSIBLE_VENV_PATH=' "\$HOME/.ansible.sh"; then
    _ansible_user_overrides_venv=1
  fi
  source "\$HOME/.ansible.sh"
fi

export ANSIBLE_VERSION="\${ANSIBLE_VERSION:-\${ANSIBLE_CORE_VERSION:-${ANSIBLE_VERSION}}}"
export ANSIBLE_CORE_VERSION="\${ANSIBLE_CORE_VERSION:-\${ANSIBLE_VERSION}}"
export ANSIBLE_RUNTIME="\${ANSIBLE_RUNTIME:-\${PYTHON_VERSION}_\${ANSIBLE_VERSION}}"
if [[ "\$_ansible_user_overrides_venv" -eq 1 && -n "\${ANSIBLE_VENV_PATH:-}" ]]; then
  export ANSIBLE_VENV_PATH
else
  export ANSIBLE_VENV_PATH="\${ANSIBLE_HOME}/apps/\${ANSIBLE_RUNTIME}"
fi
unset _ansible_user_overrides_venv

if [[ -n "\${VIRTUAL_ENV:-}" ]]; then
  _ansible_new_path=""
  IFS=':' read -r -a _ansible_path_parts <<< "\$PATH"
  for _ansible_path_part in "\${_ansible_path_parts[@]}"; do
    if [[ "\$_ansible_path_part" != "\${VIRTUAL_ENV}/bin" ]]; then
      if [[ -z "\$_ansible_new_path" ]]; then
        _ansible_new_path="\$_ansible_path_part"
      else
        _ansible_new_path="\${_ansible_new_path}:\${_ansible_path_part}"
      fi
    fi
  done
  export PATH="\$_ansible_new_path"
  unset _ansible_new_path _ansible_path_part _ansible_path_parts
fi

export VIRTUAL_ENV="\$ANSIBLE_VENV_PATH"
export VIRTUAL_ENV_DISABLE_PROMPT=1

alias cda='cd \$ANSIBLE_HOME'
alias via='ansible-vault edit'

if [[ -r "\$ANSIBLE_VENV_PATH/bin/activate" ]]; then
  source "\$ANSIBLE_VENV_PATH/bin/activate"
fi

umask 0007
export PS1="(\${ANSIBLE_RUNTIME})[\\u@\\h \\W]\\$ "

ansible-local-switch() {
  local _ansible_permanent=0
  local _ansible_runtime=""
  local _arg

  if [[ "\${1:-}" == "--help" || "\${1:-}" == "-h" ]]; then
    command /usr/local/sbin/ansible-local-switch --help
    return \$?
  fi
  if [[ "\${1:-}" == "--list" ]]; then
    command /usr/local/sbin/ansible-local-switch --list
    return \$?
  fi

  while [[ \$# -gt 0 ]]; do
    _arg="\$1"
    case "\$_arg" in
      --permanent) _ansible_permanent=1 ;;
      --*) command /usr/local/sbin/ansible-local-switch --help; return 2 ;;
      *)
        if [[ -n "\$_ansible_runtime" ]]; then
          echo "Only one runtime may be specified." >&2
          command /usr/local/sbin/ansible-local-switch --help >&2
          return 2
        fi
        _ansible_runtime="\$_arg"
        ;;
    esac
    shift
  done

  if [[ -z "\$_ansible_runtime" ]]; then
    command /usr/local/sbin/ansible-local-switch --help >&2
    return 2
  fi
  case "\$_ansible_runtime" in
    *_*) ;;
    *) echo "Runtime must look like <python-version>_<ansible-version>" >&2; return 2 ;;
  esac
  if [[ ! -x "\${ANSIBLE_HOME}/apps/\${_ansible_runtime}/bin/ansible" ]]; then
    echo "Runtime does not exist or has no ansible: \${ANSIBLE_HOME}/apps/\${_ansible_runtime}" >&2
    return 1
  fi

  if [[ "\$_ansible_permanent" -eq 1 ]]; then
    local _ansible_switch_status=0
    if [[ "\${EUID:-\$(id -u)}" -eq 0 ]]; then
      command /usr/local/sbin/ansible-local-switch --permanent "\$_ansible_runtime" || _ansible_switch_status=\$?
    else
      sudo /usr/local/sbin/ansible-local-switch --permanent "\$_ansible_runtime" || _ansible_switch_status=\$?
    fi
    [[ "\$_ansible_switch_status" -eq 0 ]] || return "\$_ansible_switch_status"
    unset PYTHON_VERSION ANSIBLE_VERSION ANSIBLE_CORE_VERSION ANSIBLE_RUNTIME ANSIBLE_VENV_PATH VIRTUAL_ENV
  else
    export PYTHON_VERSION="\${_ansible_runtime%%_*}"
    export ANSIBLE_VERSION="\${_ansible_runtime#*_}"
    export ANSIBLE_CORE_VERSION="\$ANSIBLE_VERSION"
    export ANSIBLE_RUNTIME="\$_ansible_runtime"
    unset ANSIBLE_VENV_PATH VIRTUAL_ENV
    echo "Switched current shell to \$_ansible_runtime"
    echo "Use: ansible-local-switch --permanent \$_ansible_runtime  # to change the default"
  fi

  source /etc/profile.d/ansible.sh
}

if [[ "\$USER" == "root" ]]; then
  echo "WARNING: Using Ansible as root is not recommended. Use an unprivileged user in the ansible group instead."
fi
EOF_PROFILE
chmod 0644 /etc/profile.d/ansible.sh

log "Installing ansible-local-switch"
cat > /usr/local/sbin/ansible-local-switch <<'EOF_SWITCH'
#!/usr/bin/env bash
set -euo pipefail
ANSIBLE_HOME="${ANSIBLE_HOME:-/opt/ansible}"
PROFILE=/etc/profile.d/ansible.sh
usage() {
  cat <<'USAGE'
Usage:
  ansible-local-switch --help | -h
  ansible-local-switch --list
  ansible-local-switch <python-version>_<ansible-version>
  ansible-local-switch --permanent <python-version>_<ansible-version>

Behavior:
  <runtime>              Switch only the current shell session when used via
                         the shell function from /etc/profile.d/ansible.sh.
  --permanent <runtime>  Also update /opt/ansible/current and profile defaults.
  --list                 List installed runtimes.

Examples:
  ansible-local-switch --list
  ansible-local-switch 3.12_11.3.0
  ansible-local-switch --permanent 3.12_13.4.0
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then usage; exit 0; fi
if [ "${1:-}" = "--list" ]; then
  find "$ANSIBLE_HOME/apps" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
  exit 0
fi

permanent=0
runtime=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --permanent) permanent=1 ;;
    --*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$runtime" ]; then echo "Only one runtime may be specified." >&2; usage >&2; exit 2; fi
      runtime="$1"
      ;;
  esac
  shift
done

[ -n "$runtime" ] || { usage >&2; exit 2; }
case "$runtime" in *_*) ;; *) echo "Runtime must look like <python-version>_<ansible-version>" >&2; exit 2;; esac
target="$ANSIBLE_HOME/apps/$runtime"
[ -x "$target/bin/ansible" ] || { echo "Runtime does not exist or has no ansible: $target" >&2; exit 1; }

if [ "$permanent" -ne 1 ]; then
  echo "Session-only switching must be done through the shell function loaded from /etc/profile.d/ansible.sh." >&2
  echo "Run: source /etc/profile.d/ansible.sh" >&2
  echo "Then: ansible-local-switch $runtime" >&2
  echo "For persistent default: ansible-local-switch --permanent $runtime" >&2
  exit 2
fi

python_version="${runtime%%_*}"
ansible_version="${runtime#*_}"
ln -sfn "$target" "$ANSIBLE_HOME/current.tmp"
mv -Tf "$ANSIBLE_HOME/current.tmp" "$ANSIBLE_HOME/current"
if grep -q '^export PYTHON_VERSION=' "$PROFILE"; then
  sed -i "s|^export PYTHON_VERSION=.*|export PYTHON_VERSION=\"\${PYTHON_VERSION:-$python_version}\"|" "$PROFILE"
fi
if grep -q '^export ANSIBLE_VERSION=' "$PROFILE"; then
  sed -i "s|^export ANSIBLE_VERSION=.*|export ANSIBLE_VERSION=\"\${ANSIBLE_VERSION:-\${ANSIBLE_CORE_VERSION:-$ansible_version}}\"|" "$PROFILE"
fi
if grep -q '^export ANSIBLE_CORE_VERSION=' "$PROFILE"; then
  sed -i "s|^export ANSIBLE_CORE_VERSION=.*|export ANSIBLE_CORE_VERSION=\"\${ANSIBLE_CORE_VERSION:-\${ANSIBLE_VERSION}}\"|" "$PROFILE"
fi
echo "Permanently switched /opt/ansible/current -> $target"
echo "Current shell updated automatically when using the ansible-local-switch shell function."
EOF_SWITCH
chmod 0750 /usr/local/sbin/ansible-local-switch
chown root:ansible /usr/local/sbin/ansible-local-switch
ln -sfn /usr/local/sbin/ansible-local-switch /usr/local/bin/ansible-local-switch

log "Installing adoc helper from this repository"
curl -fsSL "$RAW_BASE/ansible/files/adoc" -o /usr/local/bin/adoc
chmod 0755 /usr/local/bin/adoc
chown root:root /usr/local/bin/adoc

if [ -d /etc/bash_completion.d ]; then
  log "Installing argcomplete hook"
  "$ANSIBLE_VENV_PATH/bin/register-python-argcomplete" ansible > /etc/bash_completion.d/ansible || true
fi

if [ ! -e /etc/ansible ]; then
  ln -s "$ANSIBLE_HOME" /etc/ansible
fi

log "Applying ownership and permissions"
chown -R root:ansible "$ANSIBLE_HOME"
chmod -R ug+rwX,o-rwx "$ANSIBLE_HOME"
find "$ANSIBLE_HOME" -type d -exec chmod g+s {} +

log "Done. Active runtime: $ANSIBLE_RUNTIME"
"$ANSIBLE_VENV_PATH/bin/ansible" --version | sed -n '1,8p'
printf '\nActivate in the current shell with:\n  source /etc/profile.d/ansible.sh\n'
