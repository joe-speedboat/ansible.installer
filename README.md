# Ansible Installer

uv-based local Ansible control-node installer for Rocky/RHEL-like systems.

## One-liner

Canonical GitHub URL:

```bash
curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo sh
```

Bitbull DNS alias:

```bash
curl -L ansible-uv.bitbull.ch | sudo sh
```

When already running as root, for example in a fresh lab VM root shell:

```bash
curl -L ansible-uv.bitbull.ch | sh
```

The DNS alias points to the same installer script for a shorter copy/paste command. The installer pulls payload files from this repository only. The `adoc` helper is vendored under `ansible/files/adoc` and installed as `/usr/local/bin/adoc`.

## Defaults

- `PYTHON_VERSION=3.12`
- `ANSIBLE_VERSION=13.4.0`
- `ANSIBLE_HOME=/opt/ansible`
- runtime path: `/opt/ansible/apps/${PYTHON_VERSION}_${ANSIBLE_VERSION}`
- active runtime: `/opt/ansible/current`

`ANSIBLE_CORE_VERSION` is accepted as a legacy input alias, but the installer installs the Ansible community package (`ansible==${ANSIBLE_VERSION}`), not `ansible-core==13.x`.

## Examples

Install default runtime via GitHub:

```bash
curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo sh
```

Install default runtime via Bitbull DNS alias:

```bash
curl -L ansible-uv.bitbull.ch | sudo sh
```

Install a second runtime with explicit Python and Ansible versions:

```bash
curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo env PYTHON_VERSION=3.12 ANSIBLE_VERSION=11.3.0 sh
```

`PYTHON_VERSION` is optional because it defaults to `3.12`, but it is supported as an installer input and should be provided when documenting/reproducing a specific runtime.

Switch only the current shell:

```bash
source /etc/profile.d/ansible.sh
ansible-local-switch 3.12_11.3.0
```

Switch the permanent default:

```bash
source /etc/profile.d/ansible.sh
ansible-local-switch --permanent 3.12_13.4.0
```

## Installed layout

- `/opt/ansible`: shared workspace
- `/opt/ansible/apps/<python>_<ansible>`: uv-managed runtime
- `/opt/ansible/current`: symlink to active runtime
- `/opt/ansible/inventory`: inventory directory with localhost seed
- `/opt/ansible/logs`: log directory
- `/opt/ansible/playbooks`: playbook directory
- `/opt/ansible/projects`: project directory
- `/opt/ansible/roles`: role directory
- `/opt/ansible/ansible.cfg`: minimal config, created only if absent
- `/etc/profile.d/ansible.sh`: shell activation and runtime switch function
- `/usr/local/sbin/ansible-local-switch`: privileged persistent switch helper
- `/usr/local/bin/ansible-local-switch`: PATH symlink
- `/usr/local/bin/adoc`: ansible-doc convenience helper
- `/etc/ansible -> /opt/ansible`: compatibility symlink

## Validation

```bash
source /etc/profile.d/ansible.sh
ansible --version
ansible localhost -m ping
ansible-local-switch --list
adoc copy | sed -n '1,12p'
```
