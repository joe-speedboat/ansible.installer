from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETUP = ROOT / "ansible" / "ansible_setup.sh"
ADOC = ROOT / "ansible" / "files" / "adoc"
README = ROOT / "README.md"


def test_installer_files_exist():
    assert SETUP.exists(), "ansible/ansible_setup.sh must exist for curl | sh one-liner"
    assert ADOC.exists(), "ansible/files/adoc must be vendored in this repo"


def test_one_liner_documented():
    text = README.read_text()
    assert "curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo sh" in text


def test_installer_uses_single_repo_for_payload_files():
    text = SETUP.read_text()
    assert "RAW_BASE" in text
    assert "joe-speedboat/ansible.installer" in text
    assert "linux.scripts" not in text, "payload files must come from ansible.installer, not another repo"
    assert "ansible/files/adoc" in text


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
