# Ansible Server Hardening and Compliance

[![Ansible CI](https://github.com/tvero1011/ansible-server-hardening/actions/workflows/ansible-ci.yml/badge.svg)](https://github.com/tvero1011/ansible-server-hardening/actions/workflows/ansible-ci.yml)

A Linux server security automation project built with Ansible. It applies baseline security controls, verifies compliance, detects SSH configuration drift, and validates the code with GitHub Actions.

## Project Goals

Manually securing multiple Linux servers leads to inconsistent settings and configuration drift. This project uses Ansible to apply repeatable security controls and then verify the resulting server state.

It demonstrates practical configuration management, Linux security, automation, and CI validation in a reproducible lab environment.

## Architecture

```text
              Ansible Control Node
              Ubuntu 24.04 + Ansible
                       |
            SSH / Ansible automation
                /              \
               v                v
        web-01 (Ubuntu)    db-01 (Ubuntu)
                \              /
                 \            /
              Compliance checks and
               SSH drift detection
                       |
                GitHub Actions CI
```

The lab uses three Ubuntu 24.04 virtual machines managed with Multipass: one control node and two managed servers, `web-01` (group `web`) and `db-01` (group `db`). The control node connects to the managed servers over SSH.

## Security Controls

| Area | Implementation |
|------|----------------|
| SSH hardening | Drop-in config (`/etc/ssh/sshd_config.d/00-ansible-hardening.conf`), validated with `sshd -t`: root login and password authentication disabled, public-key authentication enabled |
| User management | Dedicated administrative account (`sysadmin` by default) in the `sudo` group, with the control node's public key installed |
| Firewall | UFW enabled; incoming denied and outgoing allowed by default |
| Firewall rules | SSH allowed; HTTPS (443) allowed only when `server_hardening_ufw_allow_https` is true (set in `group_vars/web.yml`, off for `db`) |
| Intrusion prevention | Fail2ban SSH jail (configurable `maxretry`, `findtime`, `bantime`), service enabled and running |
| Security updates | `unattended-upgrades` installed; daily package-list updates and unattended upgrades enabled |
| System auditing | `auditd` rules watch `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config`, and `/etc/ssh/sshd_config.d/` |
| Compliance | Assertions on effective SSH settings (`sshd -T`), UFW status and default policies, Fail2ban, auto-update config, and `auditd` |
| Drift detection | Compares effective SSH `port`, `permitrootlogin`, `passwordauthentication`, and `pubkeyauthentication` against the expected policy |
| CI validation | GitHub Actions runs `ansible-lint` and playbook syntax checks |

All role behaviour is controlled by variables in `roles/server_hardening/defaults/main.yml`.

## Repository Structure

```text
.
├── .github/workflows/
│   └── ansible-ci.yml
├── docs/proof/                  # Execution evidence (screenshots)
├── group_vars/
│   ├── all/vault.yml            # Ansible Vault encrypted variables
│   ├── db.yml                   # HTTPS rule off for database servers
│   └── web.yml                  # HTTPS rule on for web servers
├── playbooks/
│   ├── hardening.yml            # Applies the server_hardening role
│   ├── compliance.yml           # Compliance assertions
│   ├── drift_check.yml          # SSH drift detection
│   ├── verify.yml               # Reports SSH service state
│   ├── monitor.yml              # SSH service and root disk usage checks
│   ├── deploy_nginx.yml         # Deploys Nginx to the web group
│   └── test.yml                 # Simple host reachability check
├── roles/
│   ├── server_hardening/
│   │   ├── defaults/
│   │   ├── handlers/
│   │   ├── tasks/               # users, ssh, firewall, fail2ban, updates, auditd
│   │   └── templates/
│   └── nginx_web/
│       ├── tasks/
│       └── templates/
├── ansible.cfg
├── inventory.ini
└── README.md
```

## Prerequisites

- A Linux Ansible control node with Python and `ansible-core`
- `ansible-lint`
- Ansible collections: `ansible.posix` and `community.general`
- Managed Ubuntu servers reachable over SSH (the inventory connects as `ubuntu`)
- An SSH key pair on the control node. The role installs `~/.ssh/id_ed25519.pub` for the administrative account, so that key must exist.
- The Ansible Vault password for `group_vars/all/vault.yml`
- Server host keys in `known_hosts`, because `ansible.cfg` sets `host_key_checking = True`

The lab was developed with Multipass VMs running Ubuntu 24.04.

## Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/tvero1011/ansible-server-hardening.git
   cd ansible-server-hardening
   ```

2. Create and activate a Python virtual environment:

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```

3. Install Ansible and the linter:

   ```bash
   python -m pip install ansible-core ansible-lint
   ```

4. Install the required collections:

   ```bash
   ansible-galaxy collection install ansible.posix community.general
   ```

5. Update `inventory.ini` with the IP addresses of your own servers. The checked-in addresses are private lab IPs.

6. Check the inventory:

   ```bash
   ansible-inventory -i inventory.ini --graph
   ```

7. Verify connectivity to the managed servers:

   ```bash
   ansible all -m ping --ask-vault-pass
   ```

## Usage

### 1. Apply server hardening

```bash
ansible-playbook playbooks/hardening.yml --ask-vault-pass
```

Applies the controls defined by the `server_hardening` role.

### 2. Verify compliance

```bash
ansible-playbook playbooks/compliance.yml --ask-vault-pass
```

Asserts the effective SSH configuration, UFW status and default policies, Fail2ban, automatic security updates, and `auditd`. The playbook fails if any check does not pass.

### 3. Detect SSH configuration drift

```bash
ansible-playbook playbooks/drift_check.yml --ask-vault-pass
```

Compares the effective SSH settings with the expected policy, reports each setting as `COMPLIANT` or `DRIFT DETECTED`, and **fails when a mismatch is found**. It reports drift only; it does not remediate it.

### 4. Verify services and monitor servers

```bash
ansible-playbook playbooks/verify.yml --ask-vault-pass
ansible-playbook playbooks/monitor.yml --ask-vault-pass
```

`verify.yml` reports the SSH service state. `monitor.yml` reports SSH service health and root filesystem usage, and warns at 80% or higher.

### 5. Deploy Nginx (optional)

```bash
ansible-playbook playbooks/deploy_nginx.yml --ask-vault-pass
```

Installs Nginx on the `web` group and deploys a simple homepage showing the server name.

### 6. Validate code quality

```bash
ansible-lint playbooks/ roles/

for playbook in playbooks/*.yml; do
  echo "Checking ${playbook}"
  ansible-playbook "${playbook}" --syntax-check || exit 1
done
```

## Continuous Integration

The workflow in `.github/workflows/ansible-ci.yml` runs on pushes, pull requests, and manual dispatch. It installs Ansible and the required collections, runs `ansible-lint` across `playbooks/` and all roles, and syntax-checks every `.yml` playbook in `playbooks/`.

CI validates code quality and playbook structure only. It does not connect to the private lab servers, and it does not prove that every security control works in a separate production environment.

## Security Notes

- Keep vault passwords, private SSH keys, and other credentials out of Git.
- Store sensitive variables in Ansible Vault and supply the password securely when prompted.
- Test hardening changes in a disposable environment before applying them to production.
- Confirm firewall rules and SSH access before applying changes to remote servers, to avoid locking yourself out.
- Review service availability and application requirements before enforcing a security baseline.

## Known Limitations

- The firewall opens SSH and, on web servers, port 443 only. The Nginx role serves its default HTTP site on port 80, so that page is not reachable from outside once UFW is enforced. Open port 80 or add TLS to match.
- The administrative account is created without a password, so `sudo` will not work for it until a password or a passwordless sudo rule is configured.

## Current Scope and Future Improvements

**Implemented in the current lab**

- Ansible-based Linux hardening
- SSH configuration verification and drift detection
- UFW, Fail2ban, automatic-update, and `auditd` checks
- GitHub Actions lint and syntax validation

**Potential future improvements**

- Terraform-managed AWS infrastructure
- Automated inventory generation for cloud instances
- More comprehensive compliance checks and drift remediation
- Additional integration tests and documented execution evidence

## Evidence

Execution evidence is kept in [`docs/proof/`](docs/proof/). It currently contains the Ansible connectivity check (`00-ansible-connectivity.png`).

## Author

GitHub: [@tvero1011](https://github.com/tvero1011)
