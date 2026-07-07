# AGENT.md

Operational guide for AI agents and maintainers working on `joe-speedboat/ansible.installer`.

## Project purpose

This repository provides a small `uv`-based installer for local Ansible control-node runtimes on Rocky Linux, RHEL, AlmaLinux and compatible systems.

The installer is intentionally shell-based and supports two scopes:

- `SCOPE=system`: shared system runtime below `/opt/ansible` with profile integration in `/etc/profile.d/ansible.sh`.
- `SCOPE=user`: isolated userspace runtime below `${ANSIBLE_HOME}`, with installer-specific files below `${ANSIBLE_HOME}/apps`.

The main entrypoint is:

```text
ansible/ansible_setup.sh
```

The public install path is expected to be usable as:

```bash
curl -L ansible-uv.bitbull.ch | sudo -n sh
```

or directly from GitHub raw:

```bash
curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo -n sh
```

## Repository layout

```text
README.md
CHANGELOG.md
AGENT.md
ansible/ansible_setup.sh
ansible/files/etc/profile.d/ansible.sh
ansible/files/usr/local/bin/ansible-local-switch
ansible/files/usr/local/bin/adoc
tests/test_installer_static.py
```

The files below `ansible/files/` are repository payloads. System scope installs them to their traditional target paths. User scope installs the same payloads below the selected userspace `${ANSIBLE_HOME}/apps` layout.

## Design contract

Keep these properties intact:

1. **No mixed Ansible install methods.** The installer must stop before modifying a host with foreign RPM, pip, manual or legacy `ansible.bitbull.ch` Ansible installations unless the host is already marked as ansible-uv managed.
2. **Versioned runtimes.** Runtime paths use `${ANSIBLE_HOME}/apps/<python-version>_<ansible-version>`.
3. **Active runtime symlink.** `${ANSIBLE_HOME}/current` points at the active runtime.
4. **Ansible community package semantics.** `ANSIBLE_VERSION` refers to the PyPI `ansible` package, not `ansible-core`. The legacy `ANSIBLE_CORE_VERSION` input remains an alias for compatibility.
5. **System-scope Python accessibility.** System installs must not create virtualenv Python symlinks into root-private paths such as `/root/.local/share/uv`. Use `UV_PYTHON_INSTALL_DIR=/opt/ansible/apps/python` by default.
6. **Locked-down system files.** In system scope, Ansible payloads and the managed `/opt/ansible` tree must not be readable or executable by unrelated users. Normal target mode is `0750` for directories/executables and `0640` for regular data/config files.
7. **User scope stays userspace.** `SCOPE=user` must not modify `/etc`, `/usr/local/bin`, or `/opt` and must reject `ANSIBLE_LINK_ETC=1`.
8. **Safe reruns.** Rerunning on an ansible-uv managed host must reuse or repair the runtime and preserve existing operational config such as `${ANSIBLE_HOME}/ansible.cfg`.
9. **No Python bytecode permission drift.** Runtime/profile usage should set `PYTHONDONTWRITEBYTECODE=1`; reruns should remove `__pycache__` directories before final permission normalization.
10. **Controller-side Python package defaults.** The default `ANSIBLE_PIP_PACKAGES` list should keep common Ansible controller dependencies available: `ansible==${ANSIBLE_VERSION}`, `argcomplete`, `passlib`, `jmespath`, `netaddr`, and `dnspython`.
11. **Runtime package extension.** Interactive shells should expose `ansible-pip-install` as a safe wrapper around `uv pip install --upgrade --python "$ANSIBLE_VENV_PATH/bin/python"` so operators install extra packages into the active Ansible runtime, not into system Python.

## Implementation rules

- Keep `ansible/ansible_setup.sh` POSIX `sh` compatible.
- Keep `ansible/files/etc/profile.d/ansible.sh` Bash-aware but safe when sourced by POSIX `sh` through `/etc/profile.d`.
- Keep `ansible/files/usr/local/bin/ansible-local-switch` Bash-based and focused on persistent runtime switching.
- Do not introduce external payload dependencies from other repositories. Payload files should come from this repository through `RAW_BASE`.
- Do not use real internal hostnames, inventories, passwords, tokens or private URLs in public examples. Use `example.com`, placeholders, or public project URLs.
- If adding packages to `ANSIBLE_PIP_PACKAGES`, document why they are useful for controller-side Ansible usage and keep the list reasonably small.
- If changing install paths, update `README.md`, `AGENT.md`, and `tests/test_installer_static.py` together.

## Development checks

Run these before committing:

```bash
pytest tests/test_installer_static.py -q
sh -n ansible/ansible_setup.sh
bash -n ansible/files/etc/profile.d/ansible.sh
bash -n ansible/files/usr/local/bin/ansible-local-switch
bash -n ansible/files/usr/local/bin/adoc
git diff --check
```

Also scan public docs and examples before pushing:

```bash
grep -RInE 'sun\.bitbull\.ch|192\.168\.|password\s*=|BEGIN [A-Z ]*PRIVATE KEY|g[h]p_|github_[p]at_|to[k]en=|se[c]ret=' \
  -- README.md CHANGELOG.md AGENT.md ansible tests || true
```

Inspect matches and make sure no actual secret value is present.

## Lab validation

For release-level installer changes, static tests are not enough. Validate on a fresh Rocky/RHEL-like lab VM when possible.

Every behavior change must be validated against every affected combination, not
only the most obvious happy path. The goal is to make each impacted aspect fail
visibly during review if it regresses. Pick the matrix from the touched code and
document it in the PR or release notes before claiming the change is complete.

Common combinations to consider:

- `SCOPE=system` fresh install and rerun.
- `SCOPE=user` fresh install and rerun.
- Default runtime variables and explicit overrides such as `PYTHON_VERSION`,
  `ANSIBLE_VERSION`, `ANSIBLE_RUNTIME`, `ANSIBLE_HOME`, `UV_BIN`,
  `UV_PYTHON_INSTALL_DIR`, and `ANSIBLE_PIP_PACKAGES` when the change touches
  them.
- Clean host and ansible-uv managed host rerun paths.
- Foreign-install detection paths when conflict detection changes.
- Bash profile sourcing, POSIX `/etc/profile.d` sourcing, interactive aliases,
  `ansible-local-switch`, and `adoc` when shell integration changes.
- Permission scans and non-root usability when ownership, modes, bytecode, or
  runtime paths change.

For each tested combination, document the expected result before or alongside
the command. An agent must be able to compare actual output to the documented
expectation without guessing. Examples of useful expected results:

- installer exits successfully and prints `Done. Active runtime: <runtime>`
- rerun reuses the existing runtime and reports checked/up-to-date packages
- `ansible localhost -m ping` returns `SUCCESS` with `ping: pong`
- required Python imports succeed from the active runtime
- `ansible-local-switch --list` shows the installed runtime
- `adoc copy` opens documentation from the active runtime path
- permission scan prints no paths
- negative/conflict test stops before modifying the host and prints the expected
  error reason

Recommended local payload test:

```bash
scp -r ./ansible.installer root@host.example.com:/tmp/ansible.installer
ssh root@host.example.com 'rm -rf /tmp/ansible.installer/.git /tmp/ansible.installer/.pytest_cache /tmp/ansible.installer/tests/__pycache__'
ssh root@host.example.com 'RAW_BASE=file:///tmp/ansible.installer sh /tmp/ansible.installer/ansible/ansible_setup.sh'
ssh root@host.example.com 'RAW_BASE=file:///tmp/ansible.installer sh /tmp/ansible.installer/ansible/ansible_setup.sh'
```

Minimum runtime validation on the target:

```bash
source /etc/profile.d/ansible.sh
printf 'runtime=%s\n' "$ANSIBLE_RUNTIME"
ansible --version | sed -n '1,8p'
ansible localhost -m ping
python - <<'PY'
import passlib, jmespath, netaddr, dns
print('imports-ok', passlib.__version__, jmespath.__version__, netaddr.__version__, dns.__version__)
PY
ansible-local-switch --list
adoc copy | sed -n '1,8p'
find /opt/ansible -xdev ! -type l \( -not -group ansible -o -perm /007 \) -print
```

For public release validation after merge, test the exact public one-liner on a clean VM rather than only a local checkout copy.

## Release process

1. Update `CHANGELOG.md` with the target version and release notes.
2. Run the development checks.
3. Run lab validation for installer behavior changes.
4. Secret-scan public docs and examples.
5. Commit and push to a branch or fork.
6. Open or update a PR to `joe-speedboat/ansible.installer:main`.
7. Verify the PR is open and its `headRefOid` matches the pushed commit.
8. After merge, create the `vX.Y.Z` tag from the merged upstream `main` using an account with upstream write permission.
