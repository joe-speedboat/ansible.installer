from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETUP = ROOT / "ansible" / "ansible_setup.sh"
ADOC = ROOT / "ansible" / "files" / "usr" / "local" / "bin" / "adoc"
PROFILE = ROOT / "ansible" / "files" / "etc" / "profile.d" / "ansible.sh"
SWITCH = ROOT / "ansible" / "files" / "usr" / "local" / "sbin" / "ansible-local-switch"
README = ROOT / "README.md"


def test_installer_files_exist():
    assert SETUP.exists(), "ansible/ansible_setup.sh must exist for curl | sh one-liner"
    assert ADOC.exists(), "adoc must be vendored under ansible/files/usr/local/bin"
    assert PROFILE.exists(), "profile script must be outsourced under ansible/files/etc/profile.d"
    assert SWITCH.exists(), "switch helper must be outsourced under ansible/files/usr/local/sbin"


def test_one_liner_documented():
    text = README.read_text()
    assert "curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo sh" in text


def test_installer_uses_single_repo_for_payload_files():
    text = SETUP.read_text()
    assert "RAW_BASE" in text
    assert "joe-speedboat/ansible.installer" in text
    assert "linux.scripts" not in text, "payload files must come from ansible.installer, not another repo"
    assert "ansible/files/usr/local/bin/adoc" in text
    assert "ansible/files/etc/profile.d/ansible.sh" in text
    assert "ansible/files/usr/local/sbin/ansible-local-switch" in text


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


def test_outsourced_shell_files_have_markers():
    assert "ANSIBLE_UV_INSTALLER=1" in PROFILE.read_text()
    assert "ansible-local-switch" in SWITCH.read_text()
