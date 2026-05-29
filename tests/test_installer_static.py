from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETUP = ROOT / "ansible" / "ansible_setup.sh"
ADOC = ROOT / "ansible" / "files" / "usr" / "local" / "bin" / "adoc"
PROFILE = ROOT / "ansible" / "files" / "etc" / "profile.d" / "ansible.sh"
SWITCH = ROOT / "ansible" / "files" / "usr" / "local" / "bin" / "ansible-local-switch"
README = ROOT / "README.md"


def test_installer_files_exist():
    assert SETUP.exists(), "ansible/ansible_setup.sh must exist for curl | sh one-liner"
    assert ADOC.exists(), "adoc must be vendored under ansible/files/usr/local/bin"
    assert PROFILE.exists(), "profile script must be outsourced under ansible/files/etc/profile.d"
    assert SWITCH.exists(), "switch helper must be outsourced under ansible/files/usr/local/bin"


def test_one_liner_documented():
    text = README.read_text()
    marker = "curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo -n sh"
    assert marker in text
    assert text.count(marker) == 1


def test_readme_has_unattended_userspace_examples():
    text = README.read_text()
    assert "Userspace install for the current login user, without sudo" in text
    assert 'curl -fsSL https://ansible-uv.bitbull.ch | env SCOPE=user ANSIBLE_HOME="$HOME/ansible" sh' in text
    assert "Use sudo only when root must create/install for another user" in text
    assert "sudo -n true" in text
    assert "sudo -n env" in text
    assert "Kickstart" in text
    assert "runs as root; do not use sudo" in text
    assert "No sudo privileges available" in text


def test_readme_documents_supported_variables_with_examples():
    text = README.read_text()
    required = [
        "PYTHON_VERSION=3.12",
        "ANSIBLE_VERSION=13.4.0",
        "SCOPE=system",
        "SCOPE=user",
        "INSTALL_USER=devel",
        "INSTALL_GROUP=devel",
        "ANSIBLE_CORE_VERSION=",
        "ANSIBLE_HOME=/opt/ansible",
        "ANSIBLE_HOME=/home/devel/ansible",
        "ANSIBLE_RUNTIME=3.12_13.4.0",
        "ANSIBLE_VENV_PATH=/opt/ansible/apps/3.12_13.4.0",
        "ANSIBLE_LOCAL_TEMP=$HOME/.ansible/tmp",
        "ANSIBLE_LOG_PATH=$HOME/.ansible/ansible.log",
        "ANSIBLE_LINK_ETC=0",
        "RAW_BASE=",
        "UV_BIN=/usr/local/bin/uv",
    ]
    for marker in required:
        assert marker in text
    assert "SCOPE=user INSTALL_USER=devel INSTALL_GROUP=devel ANSIBLE_HOME=/home/devel/ansible ANSIBLE_LINK_ETC=1" not in text
    assert "SCOPE=user` intentionally refuses `ANSIBLE_LINK_ETC=1" in text


def test_installer_uses_single_repo_for_payload_files():
    text = SETUP.read_text()
    assert "RAW_BASE" in text
    assert "joe-speedboat/ansible.installer" in text
    assert "linux.scripts" not in text, "payload files must come from ansible.installer, not another repo"
    assert "ansible/files/usr/local/bin/adoc" in text
    assert "ansible/files/etc/profile.d/ansible.sh" in text
    assert "ansible/files/usr/local/bin/ansible-local-switch" in text
    assert "ansible/files/usr/local/sbin/ansible-local-switch" not in text


def test_switch_helper_installs_to_bin_with_requested_owner_and_mode():
    text = SETUP.read_text()
    assert 'ANSIBLE_SWITCH_BIN="${ANSIBLE_SWITCH_BIN:-${ANSIBLE_BIN_DIR}/ansible-local-switch}"' in text
    assert 'install_repo_file "ansible/files/usr/local/bin/ansible-local-switch" "$ANSIBLE_SWITCH_BIN" 0750' in text
    assert "ln -sfn /usr/local/sbin/ansible-local-switch /usr/local/bin/ansible-local-switch" not in text
    assert 'rm -f /usr/local/sbin/ansible-local-switch' in text


def test_all_installed_ansible_payloads_are_root_ansible_without_other_access():
    text = SETUP.read_text()
    assert 'install_repo_file "ansible/files/etc/profile.d/ansible.sh" "$ANSIBLE_PROFILE_PATH" 0750' in text
    assert 'install_repo_file "ansible/files/usr/local/bin/adoc" "$ANSIBLE_ADOC_BIN" 0750' in text
    assert 'install -o root -g "$INSTALL_GROUP" -m 0640 /dev/null /etc/bash_completion.d/ansible' in text
    assert 'chown "root:$INSTALL_GROUP" /etc/bash_completion.d/ansible' in text
    assert 'chown -h "$INSTALL_USER:$INSTALL_GROUP" /etc/ansible' in text
    assert 'find "$ANSIBLE_HOME" -type f -exec chmod 0640 {} +' in text
    assert 'find "$ANSIBLE_APPS_DIR" -path \'*/bin/*\' -type f -exec chmod 0750 {} +' in text
    forbidden = [
        ' /etc/profile.d/ansible.sh 0644 root:root',
        ' /usr/local/bin/adoc 0755 root:root',
    ]
    for marker in forbidden:
        assert marker not in text


def test_opt_ansible_tree_is_root_ansible_and_750():
    text = SETUP.read_text()
    assert 'chown -R "$(owner_group)" "$ANSIBLE_HOME"' in text
    assert 'find "$ANSIBLE_HOME" -type l -exec chown -h "$(owner_group)" {} +' in text
    assert 'find "$ANSIBLE_HOME" -type d -exec chmod 0750 {} +' in text
    assert 'find "$ANSIBLE_HOME" -type d -exec chmod g-s {} +' in text
    assert 'find "$ANSIBLE_HOME" -type f -exec chmod 0640 {} +' in text
    assert 'chmod 0750 "$ANSIBLE_PROFILE_PATH" "$ANSIBLE_SWITCH_BIN" "$ANSIBLE_ADOC_BIN"' in text


def test_template_rendering_escapes_sed_replacement_values():
    setup_text = SETUP.read_text()
    switch_text = SWITCH.read_text()
    assert "sed_replacement_escape" in setup_text
    assert "escaped_ansible_home" in setup_text
    assert "escaped_ansible_profile_path" in setup_text
    assert "sed_replacement_escape" in switch_text
    assert "escaped_ansible_version" in switch_text


def test_installer_contains_target_architecture_markers():
    text = SETUP.read_text()
    required = [
        "/opt/ansible/apps",
        "/opt/ansible/current",
        "/etc/profile.d/ansible.sh",
        "ansible-local-switch",
        "ANSIBLE_VERSION",
        "uv pip install",
        "ansible==${ANSIBLE_VERSION}",
        "argcomplete",
        "/etc/ansible",
    ]
    for marker in required:
        assert marker in text


def test_installer_supports_user_scope_without_forced_system_paths():
    text = SETUP.read_text()
    required = [
        "SCOPE=",
        "INSTALL_USER=",
        "INSTALL_GROUP=",
        "ANSIBLE_LINK_ETC=",
        "ANSIBLE_APPS_DIR=",
        "ANSIBLE_BIN_DIR=",
        "ANSIBLE_PROFILE_PATH=",
        "${ANSIBLE_HOME}/apps/profile.d/ansible.sh",
        "${ANSIBLE_HOME}/apps/bin",
        "${ANSIBLE_HOME}/apps/.ansible-uv-installer",
        "run_as_install_user",
    ]
    for marker in required:
        assert marker in text


def test_user_scope_is_strictly_userspace_and_rejects_system_targets():
    text = SETUP.read_text()
    assert 'SCOPE=user does not support ANSIBLE_LINK_ETC=1' in text
    assert 'SCOPE=user does not support ANSIBLE_INSTALL_OS_PACKAGES=1' in text
    assert 'validate_user_scope_paths' in text
    assert 'path must be writable by target user for SCOPE=user' in text
    assert 'UV_BIN must be executable by target user for SCOPE=user' in text
    assert 'path must stay inside user home for SCOPE=user' not in text
    assert 'UV_BIN must stay inside user home for SCOPE=user' not in text
    assert '( cd "$INSTALL_HOME" && runuser -u "$INSTALL_USER"' in text
    assert '( cd "$INSTALL_HOME" && sudo -u "$INSTALL_USER"' in text
    assert 'install_uv_fallback_with_python "$ANSIBLE_BIN_DIR"' in text
    assert 'UV_INSTALL_DIR="$ANSIBLE_BIN_DIR"' not in text


def test_user_scope_ignores_ambient_system_profile_defaults_from_previous_install():
    text = SETUP.read_text()
    assert 'A previous system-scope install may have been sourced' in text
    assert '[ "${ANSIBLE_HOME:-}" = "/opt/ansible" ] && unset ANSIBLE_HOME' in text
    assert '[ "${ANSIBLE_BIN_DIR:-}" = "/usr/local/bin" ] && unset ANSIBLE_BIN_DIR' in text
    assert '[ "${ANSIBLE_PROFILE_PATH:-}" = "/etc/profile.d/ansible.sh" ] && unset ANSIBLE_PROFILE_PATH' in text
    assert 'case "${ANSIBLE_LOCAL_TEMP:-}" in /root/.ansible/tmp|/opt/ansible/tmp) unset ANSIBLE_LOCAL_TEMP ;; esac' in text
    assert 'case "${ANSIBLE_LOG_PATH:-}" in /root/.ansible/ansible.log|/opt/ansible/logs/ansible.log) unset ANSIBLE_LOG_PATH ;; esac' in text
    assert 'Explicit non-system overrides such as' in text


def test_system_scope_keeps_shared_bin_directory_traversable_for_later_user_installs():
    text = SETUP.read_text()
    assert 'if [ "$ANSIBLE_BIN_DIR" = "/usr/local/bin" ]; then' in text
    assert 'install -d -o root -g root -m 0755 "$ANSIBLE_BIN_DIR"' in text
    assert 'else\n  install -d -m 0750 "$ANSIBLE_BIN_DIR"\nfi\ninstall -d -m 0750' in text
    assert 'chmod 0755 /usr/local/bin/uv /usr/local/bin/uvx' in text


def test_user_scope_reuses_system_uv_when_executable_then_falls_back_to_user_uv():
    text = SETUP.read_text()
    assert 'for candidate in /usr/local/bin/uv /usr/bin/uv "$ANSIBLE_BIN_DIR/uv"; do' in text
    user_scope_block = text.split('if [ "$SCOPE" = "user" ]; then', 1)[1].split('  else', 1)[0]
    assert '/usr/local/bin/uv' in user_scope_block
    assert '/usr/bin/uv' in user_scope_block
    assert 'user_can_execute_file "$candidate"' in user_scope_block
    assert 'chmod 0755 /usr/local/bin/uv /usr/local/bin/uvx' in text
    assert 'Installing uv into $ANSIBLE_BIN_DIR' in text


def test_user_scope_allows_existing_system_ansible_uv_installation_in_path():
    text = SETUP.read_text()
    assert 'detect_foreign_ansible_installation' in text
    assert '[ "$SCOPE" = "user" ] && return 0' in text


def test_profile_and_switch_are_path_parameterized_for_userspace():
    profile_text = PROFILE.read_text()
    switch_text = SWITCH.read_text()
    assert "ANSIBLE_BIN_DIR" in profile_text
    assert "ANSIBLE_SWITCH_BIN" in profile_text
    assert "ANSIBLE_PROFILE_PATH" in profile_text
    assert "source \"$ANSIBLE_PROFILE_PATH\"" in profile_text
    assert "command \"$ANSIBLE_SWITCH_BIN\"" in profile_text
    assert "PROFILE=\"${ANSIBLE_PROFILE_PATH:-/etc/profile.d/ansible.sh}\"" in switch_text
    assert "ANSIBLE_BIN_DIR=\"${ANSIBLE_BIN_DIR:-/usr/local/bin}\"" in switch_text
    assert "Run: source $PROFILE" in switch_text


def test_adoc_is_patched_for_per_user_tmp_file():
    text = ADOC.read_text()
    assert "/tmp/.adoc.tmp" not in text
    assert ".adoc.${UID:-$(id -u)}.tmp" in text


def test_installer_stops_for_foreign_ansible_installations():
    text = SETUP.read_text()
    assert "detect_foreign_ansible_installation" in text
    assert "rpm -q ansible ansible-core" in text
    assert "python3 -m pip show ansible ansible-core" in text
    assert "ansible.bitbull.ch" in text
    assert "Foreign Ansible installation detected" in text


def test_installer_marks_and_allows_ansible_uv_reruns():
    text = SETUP.read_text()
    assert "ANSIBLE_UV_MARKER" in text
    assert ".ansible-uv-installer" in text
    assert "uv pip install --upgrade" in text
    assert "This is an ansible-uv managed installation; continuing" in text


def test_profile_shell_function_uses_installed_switch_path():
    text = PROFILE.read_text()
    assert "ANSIBLE_UV_INSTALLER=1" in text
    assert 'command "$ANSIBLE_SWITCH_BIN"' in text
    assert "sudo /usr/local/bin/ansible-local-switch" not in text
    assert "/usr/local/sbin/ansible-local-switch" not in text


def test_profile_uses_per_user_ansible_local_temp():
    text = PROFILE.read_text()
    assert 'export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-${ANSIBLE_HOME}/ansible.cfg}"' in text
    assert 'export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-${HOME}/.ansible/tmp}"' in text
    assert 'mkdir -p "$ANSIBLE_LOCAL_TEMP"' in text


def test_profile_uses_per_user_ansible_log_path():
    text = PROFILE.read_text()
    assert 'export ANSIBLE_LOG_PATH="${ANSIBLE_LOG_PATH:-${HOME}/.ansible/ansible.log}"' in text
    assert 'mkdir -p "$(dirname "$ANSIBLE_LOG_PATH")"' in text


def test_outsourced_shell_files_have_markers():
    assert "ANSIBLE_UV_INSTALLER=1" in PROFILE.read_text()
    switch_text = SWITCH.read_text()
    assert "ansible-local-switch" in switch_text
    assert '[ -x "$runtime_dir/bin/ansible" ] || continue' in switch_text
