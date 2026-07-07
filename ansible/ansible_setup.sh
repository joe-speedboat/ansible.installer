#!/bin/sh
# uv-based local Ansible control-node installer for RHEL/Rocky/Alma-like hosts.
# One-liner:
#   curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo -n sh
set -eu

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
# Keep ANSIBLE_CORE_VERSION as a legacy input name for old notes, but install
# the Ansible community package. ansible-core itself uses 2.x versions.
ANSIBLE_VERSION="${ANSIBLE_VERSION:-${ANSIBLE_CORE_VERSION:-13.4.0}}"
SCOPE="${SCOPE:-}"
if [ -z "$SCOPE" ]; then
  if [ "$(id -u)" -eq 0 ]; then SCOPE=system; else SCOPE=user; fi
fi
case "$SCOPE" in system|user) ;; *) printf '[ansible-installer] ERROR: SCOPE must be system or user, got: %s\n' "$SCOPE" >&2; exit 1 ;; esac

INSTALL_USER="${INSTALL_USER:-${SUDO_USER:-$(id -un)}}"
[ "$INSTALL_USER" = "root" ] && [ "$SCOPE" = "user" ] && INSTALL_USER="${USER:-root}"

# A previous system-scope install may have been sourced by the current shell and
# exported /opt/ansible, /usr/local/bin, and /etc/profile.d defaults. Do not let
# those ambient system-profile values become user-scope defaults for a later
# independent user install. Explicit non-system overrides such as
# ANSIBLE_HOME=/srv/app1/ansible are still kept.
if [ "$SCOPE" = "user" ] && [ "${ANSIBLE_UV_INSTALLER:-}" = "1" ]; then
  [ "${ANSIBLE_HOME:-}" = "/opt/ansible" ] && unset ANSIBLE_HOME
  [ "${ANSIBLE_BIN_DIR:-}" = "/usr/local/bin" ] && unset ANSIBLE_BIN_DIR
  [ "${ANSIBLE_PROFILE_PATH:-}" = "/etc/profile.d/ansible.sh" ] && unset ANSIBLE_PROFILE_PATH
  [ "${ANSIBLE_SWITCH_BIN:-}" = "/usr/local/bin/ansible-local-switch" ] && unset ANSIBLE_SWITCH_BIN
  [ "${ANSIBLE_ADOC_BIN:-}" = "/usr/local/bin/adoc" ] && unset ANSIBLE_ADOC_BIN
  [ "${ANSIBLE_UV_MARKER:-}" = "/opt/ansible/.ansible-uv-installer" ] && unset ANSIBLE_UV_MARKER
  [ "${ANSIBLE_CONFIG:-}" = "/opt/ansible/ansible.cfg" ] && unset ANSIBLE_CONFIG
  case "${ANSIBLE_LOCAL_TEMP:-}" in /root/.ansible/tmp|/opt/ansible/tmp) unset ANSIBLE_LOCAL_TEMP ;; esac
  case "${ANSIBLE_LOG_PATH:-}" in /root/.ansible/ansible.log|/opt/ansible/logs/ansible.log) unset ANSIBLE_LOG_PATH ;; esac
  case "${ANSIBLE_APPS_DIR:-}" in /opt/ansible/apps) unset ANSIBLE_APPS_DIR ;; esac
  case "${ANSIBLE_VENV_PATH:-}" in /opt/ansible/apps/*) unset ANSIBLE_VENV_PATH ;; esac
fi

if [ "$SCOPE" = "system" ]; then
  INSTALL_GROUP="${INSTALL_GROUP:-ansible}"
  INSTALL_HOME="$(getent passwd "$INSTALL_USER" 2>/dev/null | cut -d: -f6 || true)"
  [ -n "$INSTALL_HOME" ] || INSTALL_HOME="/home/$INSTALL_USER"
  ANSIBLE_HOME="${ANSIBLE_HOME:-/opt/ansible}"
  ANSIBLE_LINK_ETC="${ANSIBLE_LINK_ETC:-1}"
  ANSIBLE_BIN_DIR="${ANSIBLE_BIN_DIR:-/usr/local/bin}"
  ANSIBLE_PROFILE_PATH="${ANSIBLE_PROFILE_PATH:-/etc/profile.d/ansible.sh}"
  ANSIBLE_UV_MARKER="${ANSIBLE_UV_MARKER:-${ANSIBLE_HOME}/.ansible-uv-installer}"
else
  INSTALL_GROUP="${INSTALL_GROUP:-$INSTALL_USER}"
  if [ -n "${HOME:-}" ] && [ "$INSTALL_USER" = "$(id -un 2>/dev/null || printf unknown)" ]; then
    _install_home="$HOME"
  else
    _install_home="$(getent passwd "$INSTALL_USER" 2>/dev/null | cut -d: -f6 || true)"
    [ -n "$_install_home" ] || _install_home="/home/$INSTALL_USER"
  fi
  ANSIBLE_HOME="${ANSIBLE_HOME:-${_install_home}/ansible}"
  INSTALL_HOME="$_install_home"
  ANSIBLE_LINK_ETC="${ANSIBLE_LINK_ETC:-0}"
  ANSIBLE_BIN_DIR="${ANSIBLE_BIN_DIR:-${ANSIBLE_HOME}/apps/bin}"
  ANSIBLE_PROFILE_PATH="${ANSIBLE_PROFILE_PATH:-${ANSIBLE_HOME}/apps/profile.d/ansible.sh}"
  ANSIBLE_UV_MARKER="${ANSIBLE_UV_MARKER:-${ANSIBLE_HOME}/apps/.ansible-uv-installer}"
fi
ANSIBLE_APPS_DIR="${ANSIBLE_APPS_DIR:-${ANSIBLE_HOME}/apps}"
ANSIBLE_RUNTIME="${ANSIBLE_RUNTIME:-${PYTHON_VERSION}_${ANSIBLE_VERSION}}"
ANSIBLE_VENV_PATH="${ANSIBLE_VENV_PATH:-${ANSIBLE_APPS_DIR}/${ANSIBLE_RUNTIME}}"
ANSIBLE_SWITCH_BIN="${ANSIBLE_SWITCH_BIN:-${ANSIBLE_BIN_DIR}/ansible-local-switch}"
ANSIBLE_ADOC_BIN="${ANSIBLE_ADOC_BIN:-${ANSIBLE_BIN_DIR}/adoc}"
ANSIBLE_INSTALL_OS_PACKAGES="${ANSIBLE_INSTALL_OS_PACKAGES:-}"
ANSIBLE_PIP_PACKAGES="${ANSIBLE_PIP_PACKAGES:-ansible==${ANSIBLE_VERSION} argcomplete passlib jmespath netaddr dnspython}"
# Default concrete layout in system scope: /opt/ansible/apps/<runtime>, /opt/ansible/current,
# /etc/profile.d/ansible.sh, /etc/ansible, /usr/local/bin/ansible-local-switch, adoc.
# User scope keeps role-owned integration below ${ANSIBLE_HOME}/apps/profile.d/ansible.sh,
# ${ANSIBLE_HOME}/apps/bin, and ${ANSIBLE_HOME}/apps/.ansible-uv-installer.
# Package install pattern: uv pip install --python ${ANSIBLE_VENV_PATH}/bin/python ${ANSIBLE_PIP_PACKAGES}.
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main}"
UV_BIN="${UV_BIN:-}"
UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-}"
if [ -z "$UV_PYTHON_INSTALL_DIR" ] && [ "$SCOPE" = "system" ]; then
  UV_PYTHON_INSTALL_DIR="${ANSIBLE_APPS_DIR}/python"
fi

log() { printf '[ansible-installer] %s\n' "$*"; }
fail() { printf '[ansible-installer] ERROR: %s\n' "$*" >&2; exit 1; }

user_can_write_target_path() {
  target_path="$1"
  run_as_install_user sh -c '
    target_path="$1"
    if [ -e "$target_path" ]; then
      [ -w "$target_path" ]
      exit $?
    fi
    parent_path="$target_path"
    while [ ! -e "$parent_path" ]; do
      next_parent="$(dirname "$parent_path")"
      [ "$next_parent" != "$parent_path" ] || exit 1
      parent_path="$next_parent"
    done
    [ -d "$parent_path" ] && [ -w "$parent_path" ] && [ -x "$parent_path" ]
  ' sh "$target_path"
}

user_can_execute_file() {
  target_path="$1"
  run_as_install_user sh -c '[ -x "$1" ]' sh "$target_path"
}

validate_user_scope_paths() {
  [ "$SCOPE" = "user" ] || return 0
  [ "$ANSIBLE_LINK_ETC" = "0" ] || fail "SCOPE=user does not support ANSIBLE_LINK_ETC=1"
  [ "${ANSIBLE_INSTALL_OS_PACKAGES:-0}" != "1" ] || fail "SCOPE=user does not support ANSIBLE_INSTALL_OS_PACKAGES=1"

  for var_name in ANSIBLE_HOME ANSIBLE_APPS_DIR ANSIBLE_BIN_DIR ANSIBLE_PROFILE_PATH ANSIBLE_UV_MARKER ANSIBLE_VENV_PATH ANSIBLE_SWITCH_BIN ANSIBLE_ADOC_BIN; do
    eval "var_value=\${$var_name}"
    user_can_write_target_path "$var_value" || fail "$var_name path must be writable by target user for SCOPE=user: $var_value"
  done

  if [ -n "$UV_BIN" ]; then
    user_can_execute_file "$UV_BIN" || fail "UV_BIN must be executable by target user for SCOPE=user: $UV_BIN"
  fi
}

run_as_install_user() {
  if [ "$(id -un)" = "$INSTALL_USER" ]; then
    ( cd "$INSTALL_HOME" && "$@" )
  elif [ "$(id -u)" -eq 0 ] && command -v runuser >/dev/null 2>&1; then
    ( cd "$INSTALL_HOME" && runuser -u "$INSTALL_USER" -- env HOME="$INSTALL_HOME" USER="$INSTALL_USER" LOGNAME="$INSTALL_USER" "$@" )
  elif [ "$(id -u)" -eq 0 ] && command -v sudo >/dev/null 2>&1; then
    ( cd "$INSTALL_HOME" && sudo -u "$INSTALL_USER" env HOME="$INSTALL_HOME" USER="$INSTALL_USER" LOGNAME="$INSTALL_USER" "$@" )
  else
    fail "cannot run command as $INSTALL_USER; run as that user or install runuser/sudo"
  fi
}

run_python_payload_as_install_user() {
  run_as_install_user env PYTHONDONTWRITEBYTECODE=1 "$@"
}

run_uv_as_install_user() {
  if [ -n "$UV_PYTHON_INSTALL_DIR" ]; then
    run_as_install_user env UV_PYTHON_INSTALL_DIR="$UV_PYTHON_INSTALL_DIR" "$UV_BIN" --no-config "$@"
  else
    run_as_install_user "$UV_BIN" --no-config "$@"
  fi
}

runtime_python_is_shared() {
  [ "$SCOPE" = "system" ] || return 0
  [ -x "$ANSIBLE_VENV_PATH/bin/python" ] || return 1
  python_target="$(readlink -f "$ANSIBLE_VENV_PATH/bin/python" 2>/dev/null || true)"
  [ -n "$python_target" ] || return 1
  case "$python_target" in
    "$ANSIBLE_HOME"/*|"$UV_PYTHON_INSTALL_DIR"/*|/usr/*|/bin/*) return 0 ;;
    *) return 1 ;;
  esac
}

owner_group() {
  printf '%s:%s' "$INSTALL_USER" "$INSTALL_GROUP"
}

ensure_user_and_group() {
  if [ "$(id -u)" -ne 0 ]; then
    [ "$(id -un)" = "$INSTALL_USER" ] || fail "non-root users can only install for themselves; got INSTALL_USER=$INSTALL_USER"
    return 0
  fi

  if ! getent group "$INSTALL_GROUP" >/dev/null 2>&1; then
    log "Creating group $INSTALL_GROUP"
    if [ "$SCOPE" = "system" ]; then groupadd --system "$INSTALL_GROUP"; else groupadd "$INSTALL_GROUP"; fi
  fi

  if ! id "$INSTALL_USER" >/dev/null 2>&1; then
    log "Creating user $INSTALL_USER"
    useradd -m -g "$INSTALL_GROUP" "$INSTALL_USER"
  elif [ "$SCOPE" = "system" ] && [ "$INSTALL_USER" != "root" ]; then
    log "Adding $INSTALL_USER to $INSTALL_GROUP group"
    usermod -aG "$INSTALL_GROUP" "$INSTALL_USER"
  fi
}

is_ansible_uv_installation() {
  [ -f "$ANSIBLE_UV_MARKER" ] && return 0
  [ -d "$ANSIBLE_APPS_DIR" ] && [ -x "$ANSIBLE_SWITCH_BIN" ] && return 0
  if [ "$ANSIBLE_LINK_ETC" = "1" ]; then
    [ -r /etc/profile.d/ansible.sh ] && grep -q 'ANSIBLE_UV_INSTALLER=1' /etc/profile.d/ansible.sh && return 0
  fi
  return 1
}

detect_foreign_ansible_installation() {
  # User-scope installs are intentionally isolated from /etc and system paths.
  # A system-scope ansible-uv install may already be active in PATH; do not
  # treat that as a conflict when installing an independent user runtime.
  [ "$SCOPE" = "user" ] && return 0

  if is_ansible_uv_installation; then
    log "This is an ansible-uv managed installation; continuing and upgrading runtime if needed"
    return 0
  fi

  reasons=""

  if [ "$SCOPE" = "system" ] && command -v rpm >/dev/null 2>&1; then
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
    ""|"$ANSIBLE_HOME"/current/bin/ansible|"$ANSIBLE_APPS_DIR"/*/bin/ansible) ;;
    *)
      reasons="${reasons}
- Existing ansible command detected outside ansible-uv: ${ansible_path}"
      ;;
  esac

  if [ "$ANSIBLE_LINK_ETC" = "1" ]; then
    if [ -r /etc/profile.d/ansible.sh ] && ! grep -q 'ANSIBLE_UV_INSTALLER=1' /etc/profile.d/ansible.sh; then
      reasons="${reasons}
- Existing /etc/profile.d/ansible.sh without ansible-uv marker detected. This may come from ansible.bitbull.ch or another installer."
    fi

    if [ -e /etc/ansible ] && [ ! -L /etc/ansible ] && [ ! -f "$ANSIBLE_UV_MARKER" ]; then
      reasons="${reasons}
- Existing /etc/ansible directory detected. This may be from RPM, ansible.bitbull.ch, pip, or manual installation."
    fi
  fi

  if [ -n "$reasons" ]; then
    cat >&2 <<EOF_CONFLICT
[ansible-installer] ERROR: Foreign Ansible installation detected.

This installer intentionally stops instead of mixing ansible-uv with another
Ansible installation method such as RPM, ansible.bitbull.ch, pip, or a manual
/usr/local installation.
${reasons}

Please remove or migrate the existing Ansible installation first, then rerun:
  curl -L ansible-uv.bitbull.ch | sudo -n sh

If this host is already managed by ansible-uv, make sure ${ANSIBLE_UV_MARKER}
exists or the selected profile script contains ANSIBLE_UV_INSTALLER=1.
EOF_CONFLICT
    exit 1
  fi
}

install_repo_file() {
  src="$1"
  dest="$2"
  mode="$3"
  tmp="${dest}.tmp.$$"
  dir="$(dirname "$dest")"
  if [ "$(id -u)" -eq 0 ]; then
    case "$SCOPE:$dir" in
      system:/etc/profile.d) install -d -o root -g root -m 0755 "$dir" ;;
      system:/usr/local/bin) install -d -o root -g root -m 0755 "$dir" ;;
      system:*) install -d -o root -g "$INSTALL_GROUP" -m 0750 "$dir" ;;
      user:*) install -d -o "$INSTALL_USER" -g "$INSTALL_GROUP" -m 0750 "$dir" ;;
    esac
  else
    mkdir -p "$dir"
  fi
  curl -fsSL "$RAW_BASE/$src" -o "$tmp"
  chmod "$mode" "$tmp"
  if [ "$(id -u)" -eq 0 ]; then
    if [ "$SCOPE" = "system" ]; then
      chown "root:$INSTALL_GROUP" "$tmp"
    else
      chown "$(owner_group)" "$tmp"
    fi
  fi
  mv -f "$tmp" "$dest"
}

sed_replacement_escape() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

render_profile_defaults() {
  escaped_python_version="$(sed_replacement_escape "$PYTHON_VERSION")"
  escaped_ansible_version="$(sed_replacement_escape "$ANSIBLE_VERSION")"
  escaped_ansible_home="$(sed_replacement_escape "$ANSIBLE_HOME")"
  escaped_ansible_bin_dir="$(sed_replacement_escape "$ANSIBLE_BIN_DIR")"
  escaped_ansible_profile_path="$(sed_replacement_escape "$ANSIBLE_PROFILE_PATH")"
  escaped_ansible_switch_bin="$(sed_replacement_escape "$ANSIBLE_SWITCH_BIN")"
  sed -i \
    -e "s|@PYTHON_VERSION@|${escaped_python_version}|g" \
    -e "s|@ANSIBLE_VERSION@|${escaped_ansible_version}|g" \
    -e "s|@ANSIBLE_HOME@|${escaped_ansible_home}|g" \
    -e "s|@ANSIBLE_BIN_DIR@|${escaped_ansible_bin_dir}|g" \
    -e "s|@ANSIBLE_PROFILE_PATH@|${escaped_ansible_profile_path}|g" \
    -e "s|@ANSIBLE_SWITCH_BIN@|${escaped_ansible_switch_bin}|g" \
    "$ANSIBLE_PROFILE_PATH"
}

install_user_shell_activation() {
  [ "$SCOPE" = "user" ] || return 0

  ANSIBLE_UV_BASHRC_MARKER_BEGIN="# >>> ansible-uv user activation >>>"
  ANSIBLE_UV_BASHRC_MARKER_END="# <<< ansible-uv user activation <<<"
  bashrc_path="${INSTALL_HOME}/.bashrc"
  tmp_bashrc="$(mktemp "${INSTALL_HOME}/.bashrc.ansible-uv.XXXXXX")"

  log "Installing userspace shell activation to $bashrc_path"
  if [ -f "$bashrc_path" ]; then
    awk -v begin="$ANSIBLE_UV_BASHRC_MARKER_BEGIN" -v end="$ANSIBLE_UV_BASHRC_MARKER_END" '
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      skip != 1 { print }
    ' "$bashrc_path" > "$tmp_bashrc"
  else
    : > "$tmp_bashrc"
  fi

  cat >> "$tmp_bashrc" <<EOF_BASHRC

$ANSIBLE_UV_BASHRC_MARKER_BEGIN
# Managed by joe-speedboat/ansible.installer. Re-run the installer to update.
ANSIBLE_HOME="$ANSIBLE_HOME"
ANSIBLE_BIN_DIR="$ANSIBLE_BIN_DIR"
ANSIBLE_PROFILE_PATH="$ANSIBLE_PROFILE_PATH"
ANSIBLE_SWITCH_BIN="$ANSIBLE_SWITCH_BIN"
export ANSIBLE_HOME ANSIBLE_BIN_DIR ANSIBLE_PROFILE_PATH ANSIBLE_SWITCH_BIN
unset PYTHON_VERSION ANSIBLE_VERSION ANSIBLE_CORE_VERSION ANSIBLE_RUNTIME ANSIBLE_VENV_PATH VIRTUAL_ENV ANSIBLE_CONFIG
if [ -r "\$ANSIBLE_PROFILE_PATH" ]; then
  source "\$ANSIBLE_PROFILE_PATH"
fi
$ANSIBLE_UV_BASHRC_MARKER_END
EOF_BASHRC

  if [ "$(id -u)" -eq 0 ]; then
    chown "$(owner_group)" "$tmp_bashrc"
  fi
  chmod 0640 "$tmp_bashrc"
  mv -f "$tmp_bashrc" "${INSTALL_HOME}/.bashrc"
  if [ "$(id -u)" -eq 0 ]; then
    chown "$(owner_group)" "${INSTALL_HOME}/.bashrc"
  fi
  chmod 0640 "${INSTALL_HOME}/.bashrc"
}

install_uv_fallback_with_python() {
  dest_dir="$1"
  command -v python3 >/dev/null 2>&1 || fail "python3 is required to install uv without tar"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) uv_target="uv-x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) uv_target="uv-aarch64-unknown-linux-gnu" ;;
    *) fail "unsupported architecture for uv fallback installer: $arch" ;;
  esac
  tmp_dir="$(mktemp -d)"
  archive="$tmp_dir/uv.tar.gz"
  curl -fsSL "https://github.com/astral-sh/uv/releases/latest/download/${uv_target}.tar.gz" -o "$archive"
  python3 - "$archive" "$tmp_dir" "$dest_dir" "$uv_target" <<'PYUV'
import os
import shutil
import sys
import tarfile

archive, tmp_dir, dest_dir, uv_target = sys.argv[1:]
os.makedirs(dest_dir, exist_ok=True)
with tarfile.open(archive, "r:gz") as tf:
    tf.extractall(tmp_dir, filter="data")
for name in ("uv", "uvx"):
    src = os.path.join(tmp_dir, uv_target, name)
    if os.path.exists(src):
        dst = os.path.join(dest_dir, name)
        shutil.copy2(src, dst)
        os.chmod(dst, 0o750)
PYUV
  rm -rf "$tmp_dir"
}

install_uv_to() {
  dest_dir="$1"
  mkdir -p "$dest_dir"
  if command -v tar >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$dest_dir" sh
  else
    log "tar is missing; installing uv with Python tarfile fallback"
    install_uv_fallback_with_python "$dest_dir"
  fi
}

[ -r /etc/os-release ] || fail "missing /etc/os-release"
# shellcheck disable=SC1091
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *rhel*|*fedora*|*centos*|*rocky*|*almalinux*|*ol*) ;;
  *) fail "unsupported OS: ID=${ID:-unknown} ID_LIKE=${ID_LIKE:-unknown}" ;;
esac

ensure_user_and_group
validate_user_scope_paths
detect_foreign_ansible_installation

if [ "$SCOPE" = "system" ] || [ "$ANSIBLE_INSTALL_OS_PACKAGES" = "1" ]; then
  [ "$(id -u)" -eq 0 ] || fail "root is required to install OS packages"
  command -v dnf >/dev/null 2>&1 || fail "dnf is required"
  log "Installing required OS packages"
  dnf install -y curl ca-certificates tar gzip bash-completion python3 python3-devel gcc openssl-devel libffi-devel less util-linux
else
  command -v curl >/dev/null 2>&1 || fail "curl is required"
fi

log "Creating Ansible tree at $ANSIBLE_HOME for $INSTALL_USER:$INSTALL_GROUP"
if [ "$SCOPE" = "system" ]; then
  if [ "$ANSIBLE_BIN_DIR" = "/usr/local/bin" ]; then
    install -d -o root -g root -m 0755 "$ANSIBLE_BIN_DIR"
  else
    install -d -o root -g "$INSTALL_GROUP" -m 0750 "$ANSIBLE_BIN_DIR"
  fi
else
  install -d -m 0750 "$ANSIBLE_BIN_DIR"
fi
install -d -m 0750 \
  "$ANSIBLE_HOME" \
  "$ANSIBLE_APPS_DIR" \
  "$ANSIBLE_HOME/inventory" \
  "$ANSIBLE_HOME/logs" \
  "$ANSIBLE_HOME/tmp" \
  "$ANSIBLE_HOME/playbooks" \
  "$ANSIBLE_HOME/projects" \
  "$ANSIBLE_HOME/roles"
if [ -n "$UV_PYTHON_INSTALL_DIR" ]; then
  install -d -m 0750 "$UV_PYTHON_INSTALL_DIR"
fi
if [ "$(id -u)" -eq 0 ]; then
  chown -R "$(owner_group)" "$ANSIBLE_HOME"
fi

if [ -z "$UV_BIN" ]; then
  if [ "$SCOPE" = "user" ]; then
    for candidate in /usr/local/bin/uv /usr/bin/uv "$ANSIBLE_BIN_DIR/uv"; do
      if [ -x "$candidate" ] && user_can_execute_file "$candidate"; then UV_BIN="$candidate"; break; fi
    done
  else
    for candidate in "$ANSIBLE_BIN_DIR/uv" /usr/local/bin/uv /usr/bin/uv "$ANSIBLE_HOME/apps/bin/uv" "$HOME/.local/bin/uv"; do
      if [ -x "$candidate" ]; then UV_BIN="$candidate"; break; fi
    done
  fi
fi
if [ -z "$UV_BIN" ]; then
  if [ "$SCOPE" = "system" ]; then
    log "Installing uv into /usr/local/bin"
    install_uv_to /usr/local/bin
    if [ "$(id -u)" -eq 0 ]; then chown root:"$INSTALL_GROUP" /usr/local/bin/uv /usr/local/bin/uvx 2>/dev/null || true; chmod 0755 /usr/local/bin/uv /usr/local/bin/uvx 2>/dev/null || true; fi
    UV_BIN=/usr/local/bin/uv
  else
    log "Installing uv into $ANSIBLE_BIN_DIR"
    install_uv_fallback_with_python "$ANSIBLE_BIN_DIR"
    if [ "$(id -u)" -eq 0 ]; then chown -R "$(owner_group)" "$ANSIBLE_BIN_DIR"; fi
    UV_BIN="$ANSIBLE_BIN_DIR/uv"
  fi
fi
[ -x "$UV_BIN" ] || fail "uv not executable at $UV_BIN"

if [ -x "$ANSIBLE_VENV_PATH/bin/python" ] && runtime_python_is_shared; then
  log "Reusing existing uv runtime at $ANSIBLE_VENV_PATH"
else
  if [ -e "$ANSIBLE_VENV_PATH" ]; then
    log "Removing uv runtime with non-shared or unusable Python at $ANSIBLE_VENV_PATH"
    rm -rf "$ANSIBLE_VENV_PATH"
  fi
  log "Creating uv runtime at $ANSIBLE_VENV_PATH"
  run_uv_as_install_user venv --python "$PYTHON_VERSION" "$ANSIBLE_VENV_PATH"
fi

log "Installing/upgrading Python packages: ${ANSIBLE_PIP_PACKAGES}"
# Reruns use the equivalent of: uv pip install --upgrade ${ANSIBLE_PIP_PACKAGES}
# shellcheck disable=SC2086 # intentional word splitting: package specs are a whitespace-separated list.
run_uv_as_install_user pip install --upgrade --python "$ANSIBLE_VENV_PATH/bin/python" $ANSIBLE_PIP_PACKAGES

log "Updating active runtime symlink"
ln -sfn "$ANSIBLE_VENV_PATH" "$ANSIBLE_HOME/current.tmp"
mv -Tf "$ANSIBLE_HOME/current.tmp" "$ANSIBLE_HOME/current"

if [ ! -e "$ANSIBLE_HOME/ansible.cfg" ]; then
  log "Creating minimal ansible.cfg"
  cat > "$ANSIBLE_HOME/ansible.cfg" <<CFG
[defaults]
inventory=${ANSIBLE_HOME}/inventory
roles_path=${ANSIBLE_HOME}/roles
log_path=${ANSIBLE_HOME}/logs/ansible.log
host_key_checking=True
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

log "Installing profile integration to $ANSIBLE_PROFILE_PATH"
install_repo_file "ansible/files/etc/profile.d/ansible.sh" "$ANSIBLE_PROFILE_PATH" 0750
render_profile_defaults

log "Installing ansible-local-switch to $ANSIBLE_SWITCH_BIN"
install_repo_file "ansible/files/usr/local/bin/ansible-local-switch" "$ANSIBLE_SWITCH_BIN" 0750
if [ "$SCOPE" = "system" ]; then rm -f /usr/local/sbin/ansible-local-switch; fi

log "Installing adoc helper to $ANSIBLE_ADOC_BIN"
install_repo_file "ansible/files/usr/local/bin/adoc" "$ANSIBLE_ADOC_BIN" 0750

install_user_shell_activation

if [ "$ANSIBLE_LINK_ETC" = "1" ]; then
  [ "$(id -u)" -eq 0 ] || fail "ANSIBLE_LINK_ETC=1 requires root"
  if [ "$ANSIBLE_PROFILE_PATH" != /etc/profile.d/ansible.sh ]; then
    log "Linking /etc/profile.d/ansible.sh to $ANSIBLE_PROFILE_PATH"
    ln -sfn "$ANSIBLE_PROFILE_PATH" /etc/profile.d/ansible.sh
  fi
  if [ -d /etc/bash_completion.d ]; then
    log "Installing argcomplete hook"
    install -o root -g "$INSTALL_GROUP" -m 0640 /dev/null /etc/bash_completion.d/ansible
    "$ANSIBLE_VENV_PATH/bin/register-python-argcomplete" ansible > /etc/bash_completion.d/ansible || true
    chown "root:$INSTALL_GROUP" /etc/bash_completion.d/ansible
    chmod 0640 /etc/bash_completion.d/ansible
  fi
  if [ ! -e /etc/ansible ]; then
    ln -s "$ANSIBLE_HOME" /etc/ansible
  fi
  if [ -L /etc/ansible ]; then
    chown -h "$INSTALL_USER:$INSTALL_GROUP" /etc/ansible
  fi
fi

log "Marking installation as ansible-uv managed"
cat > "$ANSIBLE_UV_MARKER" <<EOF_MARKER
ANSIBLE_UV_INSTALLER=1
SCOPE=$SCOPE
INSTALL_USER=$INSTALL_USER
INSTALL_GROUP=$INSTALL_GROUP
ANSIBLE_HOME=$ANSIBLE_HOME
ANSIBLE_APPS_DIR=$ANSIBLE_APPS_DIR
ANSIBLE_BIN_DIR=$ANSIBLE_BIN_DIR
ANSIBLE_PROFILE_PATH=$ANSIBLE_PROFILE_PATH
PYTHON_VERSION=$PYTHON_VERSION
ANSIBLE_VERSION=$ANSIBLE_VERSION
ANSIBLE_RUNTIME=$ANSIBLE_RUNTIME
UV_PYTHON_INSTALL_DIR=$UV_PYTHON_INSTALL_DIR
RAW_BASE=$RAW_BASE
EOF_MARKER

log "Applying ownership and permissions"
log "Removing Python bytecode caches from managed runtimes"
find "$ANSIBLE_APPS_DIR" -type d -name __pycache__ -prune -exec rm -rf {} +
if [ "$(id -u)" -eq 0 ]; then
  chown -R "$(owner_group)" "$ANSIBLE_HOME"
  find "$ANSIBLE_HOME" -type l -exec chown -h "$(owner_group)" {} +
fi
find "$ANSIBLE_HOME" -type d -exec chmod 0750 {} +
find "$ANSIBLE_HOME" -type d -exec chmod g-s {} +
find "$ANSIBLE_HOME" -type f -exec chmod 0640 {} +
find "$ANSIBLE_APPS_DIR" -path '*/bin/*' -type f -exec chmod 0750 {} +
chmod 0750 "$ANSIBLE_PROFILE_PATH" "$ANSIBLE_SWITCH_BIN" "$ANSIBLE_ADOC_BIN" 2>/dev/null || true

log "Done. Active runtime: $ANSIBLE_RUNTIME"
run_python_payload_as_install_user "$ANSIBLE_VENV_PATH/bin/ansible" --version | sed -n '1,8p'
printf '\nActivate in the current shell with:\n  source %s\n' "$ANSIBLE_PROFILE_PATH"
