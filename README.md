# Ansible Server Hardening and Compliance

[![Ansible CI](https://github.com/tvero1011/ansible-server-hardening/actions/workflows/ansible-ci.yml/badge.svg)](https://github.com/tvero1011/ansible-server-hardening/actions/workflows/ansible-ci.yml)

Ansible automation that hardens Ubuntu servers, checks them against a security baseline, and detects SSH configuration drift. The repo also contains a Terraform configuration for a proposed AWS environment, with both validated in CI.

## Status

| Part | Status |
|------|--------|
| Ansible hardening, compliance, and drift checks | Run and tested on two Ubuntu 24.04 Multipass VMs |
| GitHub Actions CI | Passing: `ansible-lint`, playbook syntax checks, `terraform fmt`, `terraform validate` |
| Terraform / AWS | **Validated only.** `terraform plan` and `apply` have not been run, and no AWS resources exist |

## Architecture

**Local lab (implemented and tested)**

```text
        Ansible control node
                |
              SSH
         +------+------+
         |             |
      web-01         db-01
   (Ubuntu 24.04) (Ubuntu 24.04)
```

**Proposed AWS design (not deployed)**

```text
                 Internet
                     |
            Internet Gateway
                     |
 +------------- VPC 10.20.0.0/16 -------------+
 |                                            |
 |  Public subnet 10.20.1.0/24                |
 |    web-01 (EC2)                            |
 |    SSH from one admin /32, HTTP, HTTPS     |
 |                    |                       |
 |             SSH from web-01 only           |
 |                    |                       |
 |  Private subnet 10.20.2.0/24               |
 |    db-01 (EC2, no public IP)               |
 +--------------------------------------------+
```

Terraform would create the AWS network and instances. Ansible configures the servers. Only the Ansible side has been run.

## What the Ansible role does

| Area | Implementation |
|------|----------------|
| SSH | Drop-in config validated with `sshd -t`; root login and password authentication disabled, public-key authentication enabled |
| Admin user | `sysadmin` account in the `sudo` group with the control node's public key |
| Firewall | UFW with incoming denied by default; SSH allowed; HTTPS allowed on the `web` group only |
| Fail2ban | SSH jail enabled and running |
| Updates | `unattended-upgrades` configured |
| Auditing | `auditd` rules watching `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config`, and `/etc/ssh/sshd_config.d/` |

**Compliance check** (`compliance.yml`): asserts the effective SSH settings (read with `sshd -T`, not from the config file), UFW status and default policies, Fail2ban, auto-update config, and `auditd`. It fails if any check fails.

**Drift check** (`drift_check.yml`): compares the effective SSH port, root login, password authentication, and public-key authentication with the expected policy. It reports each setting and fails on a mismatch. It does not fix anything. I tested it with a deliberately mismatched expected value, so it shows mismatch detection, not detection of an unauthorized change on a live server.

Other playbooks: `verify.yml` and `monitor.yml` (SSH service state and disk usage), `deploy_nginx.yml` (Nginx on the web group), `test.yml` (reachability).

## Quick start

You need an Ansible control node, SSH access to the servers, the Vault password for `group_vars/all/vault.yml`, and an SSH public key at `~/.ssh/id_ed25519.pub` (the role installs it for `sysadmin`). Host key checking is on, so the servers' keys must be in `known_hosts`.

```bash
git clone https://github.com/tvero1011/ansible-server-hardening.git
cd ansible-server-hardening
python3 -m venv .venv && source .venv/bin/activate
python -m pip install ansible-core ansible-lint
ansible-galaxy collection install ansible.posix community.general
# edit inventory.ini: replace the lab IP addresses with your own
ansible all -m ping --ask-vault-pass
ansible-playbook playbooks/hardening.yml --ask-vault-pass
ansible-playbook playbooks/compliance.yml --ask-vault-pass
ansible-playbook playbooks/drift_check.yml --ask-vault-pass
```

Run the hardening playbook a second time to check repeatability; a second run should report `changed=0`. SSH and firewall changes can lock you out, so confirm you have another way in before applying them to a server you care about.

## Terraform (proposed, not applied)

`terraform/` defines a VPC with a public and a private subnet, an internet gateway, two security groups, and two Ubuntu 24.04 EC2 instances (`t3.micro`, encrypted 8 GB root volumes, IMDSv2 required). SSH to the web server is limited to one administrator address (`admin_cidr`, which must be a `/32`). The default region is `ap-southeast-1`.

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

`validate` only checks syntax and internal consistency. It does not contact AWS, so it does not show that a plan or deployment would succeed. Applying this configuration would create billable resources.

## CI and evidence

The workflow in `.github/workflows/ansible-ci.yml` runs on pushes, pull requests, and manual dispatch. It runs `ansible-lint`, syntax-checks every playbook in `playbooks/`, and runs the Terraform format check, backend-free init, and validate. It does not connect to the lab servers.

Screenshots are in [`docs/proof/`](docs/proof/): connectivity, a hardening run with `changed=0` and no failures, a compliance run, the drift check failing on a deliberate mismatch, and the passing CI runs.

## Known limitations

- **Firewall and Nginx:** UFW allows SSH and (on web servers) port 443, but the Nginx role serves HTTP on port 80, so that page is blocked from outside. Open port 80 or add TLS.
- **`sysadmin` sudo:** the account is created without a password, so `sudo` will not work for it until a password or passwordless sudo rule is set up.
- **Terraform key pair:** the instances have no `key_name`, so SSH to them is not possible as written.
- **Terraform private subnet:** it has no NAT gateway or internet route, so `db-01` could not install packages, and the inventory has no jump-host setup.
- **Static inventory:** `inventory.ini` holds the lab IPs and is not generated from Terraform.
- **No integration tests:** CI checks code quality only. There are no tests against live servers, no Terraform security scanning, and no remote Terraform state.

## Next steps

1. Fix the Terraform gaps (key pair, outbound access for `db-01`) and run `terraform plan`.
2. Resolve the Nginx/UFW port mismatch and the `sysadmin` sudo setup.
3. Generate the Ansible inventory from Terraform outputs.
4. Add Terraform security scanning and role tests (for example `checkov` and Molecule).

## Author

[@tvero1011](https://github.com/tvero1011)
