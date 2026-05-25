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
    assert "curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo sh" in text
    assert text.count("curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo sh") == 1


def test_readme_documents_supported_variables_with_examples():
    text = README.read_text()
    required = [
        "PYTHON_VERSION=3.12",
        "ANSIBLE_VERSION=13.4.0",
        "ANSIBLE_CORE_VERSION=",
        "ANSIBLE_HOME=/opt/ansible",
        "ANSIBLE_RUNTIME=3.12_13.4.0",
        "ANSIBLE_VENV_PATH=/opt/ansible/apps/3.12_13.4.0",
        "ANSIBLE_LOCAL_TEMP=$HOME/.ansible/tmp",
        "ANSIBLE_LOG_PATH=$HOME/.ansible/ansible.log",
        "RAW_BASE=",
        "UV_BIN=/usr/local/bin/uv",
    ]
    for marker in required:
        assert marker in text


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
    assert 'install_repo_file "ansible/files/usr/local/bin/ansible-local-switch" /usr/local/bin/ansible-local-switch 0750 root:ansible' in text
    assert "ln -sfn /usr/local/sbin/ansible-local-switch /usr/local/bin/ansible-local-switch" not in text
    assert 'rm -f /usr/local/sbin/ansible-local-switch' in text


def test_all_installed_ansible_payloads_are_root_ansible_without_other_access():
    text = SETUP.read_text()
    assert 'install_repo_file "ansible/files/etc/profile.d/ansible.sh" /etc/profile.d/ansible.sh 0750 root:ansible' in text
    assert 'install_repo_file "ansible/files/usr/local/bin/adoc" /usr/local/bin/adoc 0750 root:ansible' in text
    assert 'install -o root -g ansible -m 0640 /dev/null /etc/bash_completion.d/ansible' in text
    assert 'chown -h root:ansible /etc/ansible' in text
    assert 'chmod 0750 /usr/local/bin/ansible-local-switch /usr/local/bin/adoc /etc/profile.d/ansible.sh' in text
    forbidden = [
        ' /etc/profile.d/ansible.sh 0644 root:root',
        ' /usr/local/bin/adoc 0755 root:root',
    ]
    for marker in forbidden:
        assert marker not in text


def test_opt_ansible_tree_is_root_ansible_and_750():
    text = SETUP.read_text()
    assert 'chown -R root:ansible "$ANSIBLE_HOME"' in text
    assert 'find "$ANSIBLE_HOME" -type l -exec chown -h root:ansible {} +' in text
    assert 'find "$ANSIBLE_HOME" -type d -exec chmod 0750 {} +' in text
    assert 'find "$ANSIBLE_HOME" -type d -exec chmod g-s {} +' in text
    assert 'find "$ANSIBLE_HOME" -type f -exec chmod 0750 {} +' in text


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
    assert "command /usr/local/bin/ansible-local-switch" in text
    assert "sudo /usr/local/bin/ansible-local-switch" in text
    assert "/usr/local/sbin/ansible-local-switch" not in text


def test_profile_uses_per_user_ansible_local_temp():
    text = PROFILE.read_text()
    assert 'export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-${HOME}/.ansible/tmp}"' in text
    assert 'mkdir -p "$ANSIBLE_LOCAL_TEMP"' in text


def test_profile_uses_per_user_ansible_log_path():
    text = PROFILE.read_text()
    assert 'export ANSIBLE_LOG_PATH="${ANSIBLE_LOG_PATH:-${HOME}/.ansible/ansible.log}"' in text
    assert 'mkdir -p "$(dirname "$ANSIBLE_LOG_PATH")"' in text


def test_outsourced_shell_files_have_markers():
    assert "ANSIBLE_UV_INSTALLER=1" in PROFILE.read_text()
    assert "ansible-local-switch" in SWITCH.read_text()
