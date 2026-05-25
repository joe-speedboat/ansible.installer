#!/bin/bash
# ansible-uv managed shell integration. Installed by joe-speedboat/ansible.installer.
ANSIBLE_UV_INSTALLER=1
export ANSIBLE_UV_INSTALLER

export ANSIBLE_HOME="${ANSIBLE_HOME:-/opt/ansible}"
export PYTHON_VERSION="${PYTHON_VERSION:-@PYTHON_VERSION@}"
export ANSIBLE_VERSION="${ANSIBLE_VERSION:-${ANSIBLE_CORE_VERSION:-@ANSIBLE_VERSION@}}"
# Compatibility for older shells/scripts that still inspect ANSIBLE_CORE_VERSION.
export ANSIBLE_CORE_VERSION="${ANSIBLE_CORE_VERSION:-${ANSIBLE_VERSION}}"
export ANSIBLE_RUNTIME="${ANSIBLE_RUNTIME:-${PYTHON_VERSION}_${ANSIBLE_VERSION}}"

_ansible_user_overrides_venv=0
if [[ -r "$HOME/.ansible.sh" ]]; then
  if grep -Eq '^[[:space:]]*(export[[:space:]]+)?ANSIBLE_VENV_PATH=' "$HOME/.ansible.sh"; then
    _ansible_user_overrides_venv=1
  fi
  source "$HOME/.ansible.sh"
fi

export ANSIBLE_VERSION="${ANSIBLE_VERSION:-${ANSIBLE_CORE_VERSION:-@ANSIBLE_VERSION@}}"
export ANSIBLE_CORE_VERSION="${ANSIBLE_CORE_VERSION:-${ANSIBLE_VERSION}}"
export ANSIBLE_RUNTIME="${ANSIBLE_RUNTIME:-${PYTHON_VERSION}_${ANSIBLE_VERSION}}"
if [[ "$_ansible_user_overrides_venv" -eq 1 && -n "${ANSIBLE_VENV_PATH:-}" ]]; then
  export ANSIBLE_VENV_PATH
else
  export ANSIBLE_VENV_PATH="${ANSIBLE_HOME}/apps/${ANSIBLE_RUNTIME}"
fi
unset _ansible_user_overrides_venv

if [[ -n "${VIRTUAL_ENV:-}" ]]; then
  _ansible_new_path=""
  IFS=':' read -r -a _ansible_path_parts <<< "$PATH"
  for _ansible_path_part in "${_ansible_path_parts[@]}"; do
    if [[ "$_ansible_path_part" != "${VIRTUAL_ENV}/bin" ]]; then
      if [[ -z "$_ansible_new_path" ]]; then
        _ansible_new_path="$_ansible_path_part"
      else
        _ansible_new_path="${_ansible_new_path}:${_ansible_path_part}"
      fi
    fi
  done
  export PATH="$_ansible_new_path"
  unset _ansible_new_path _ansible_path_part _ansible_path_parts
fi

export VIRTUAL_ENV="$ANSIBLE_VENV_PATH"
export VIRTUAL_ENV_DISABLE_PROMPT=1
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-${HOME}/.ansible/tmp}"
mkdir -p "$ANSIBLE_LOCAL_TEMP"
export ANSIBLE_LOG_PATH="${ANSIBLE_LOG_PATH:-${HOME}/.ansible/ansible.log}"
mkdir -p "$(dirname "$ANSIBLE_LOG_PATH")"

alias cda='cd $ANSIBLE_HOME'
alias via='ansible-vault edit'

if [[ -r "$ANSIBLE_VENV_PATH/bin/activate" ]]; then
  source "$ANSIBLE_VENV_PATH/bin/activate"
fi

umask 0007
export PS1="(${ANSIBLE_RUNTIME})[\u@\h \W]\$ "

ansible-local-switch() {
  local _ansible_permanent=0
  local _ansible_runtime=""
  local _arg

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    command /usr/local/bin/ansible-local-switch --help
    return $?
  fi
  if [[ "${1:-}" == "--list" ]]; then
    command /usr/local/bin/ansible-local-switch --list
    return $?
  fi

  while [[ $# -gt 0 ]]; do
    _arg="$1"
    case "$_arg" in
      --permanent) _ansible_permanent=1 ;;
      --*) command /usr/local/bin/ansible-local-switch --help; return 2 ;;
      *)
        if [[ -n "$_ansible_runtime" ]]; then
          echo "Only one runtime may be specified." >&2
          command /usr/local/bin/ansible-local-switch --help >&2
          return 2
        fi
        _ansible_runtime="$_arg"
        ;;
    esac
    shift
  done

  if [[ -z "$_ansible_runtime" ]]; then
    command /usr/local/bin/ansible-local-switch --help >&2
    return 2
  fi
  case "$_ansible_runtime" in
    *_*) ;;
    *) echo "Runtime must look like <python-version>_<ansible-version>" >&2; return 2 ;;
  esac
  if [[ ! -x "${ANSIBLE_HOME}/apps/${_ansible_runtime}/bin/ansible" ]]; then
    echo "Runtime does not exist or has no ansible: ${ANSIBLE_HOME}/apps/${_ansible_runtime}" >&2
    return 1
  fi

  if [[ "$_ansible_permanent" -eq 1 ]]; then
    local _ansible_switch_status=0
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      command /usr/local/bin/ansible-local-switch --permanent "$_ansible_runtime" || _ansible_switch_status=$?
    else
      sudo /usr/local/bin/ansible-local-switch --permanent "$_ansible_runtime" || _ansible_switch_status=$?
    fi
    [[ "$_ansible_switch_status" -eq 0 ]] || return "$_ansible_switch_status"
    unset PYTHON_VERSION ANSIBLE_VERSION ANSIBLE_CORE_VERSION ANSIBLE_RUNTIME ANSIBLE_VENV_PATH VIRTUAL_ENV
  else
    export PYTHON_VERSION="${_ansible_runtime%%_*}"
    export ANSIBLE_VERSION="${_ansible_runtime#*_}"
    export ANSIBLE_CORE_VERSION="$ANSIBLE_VERSION"
    export ANSIBLE_RUNTIME="$_ansible_runtime"
    unset ANSIBLE_VENV_PATH VIRTUAL_ENV
    echo "Switched current shell to $_ansible_runtime"
    echo "Use: ansible-local-switch --permanent $_ansible_runtime  # to change the default"
  fi

  source /etc/profile.d/ansible.sh
}

if [[ "$USER" == "root" ]]; then
  echo "WARNING: Using Ansible as root is not recommended. Use an unprivileged user in the ansible group instead."
fi
