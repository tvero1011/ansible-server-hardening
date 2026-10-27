# Ansible Server Hardening and Compliance

[![Ansible CI](https://github.com/tvero1011/ansible-server-hardening/actions/workflows/ansible-ci.yml/badge.svg)](https://github.com/tvero1011/ansible-server-hardening/actions/workflows/ansible-ci.yml)

Ansible automation that hardens Ubuntu servers, checks them against a security baseline, and detects SSH configuration drift. A Terraform configuration builds the AWS environment the playbooks can run against. The full workflow (Terraform apply, Ansible hardening, compliance check, Nginx deployment, Terraform destroy) was run end to end on AWS as a temporary lab.

## Status

| Part | Status |
|------|--------|
| Ansible hardening, compliance, and drift checks | Run and tested on two Ubuntu 24.04 Multipass VMs, including a second hardening run with `changed=0` |
| Ansible on AWS | Run once against two EC2 instances: ping, hardening, compliance, and Nginx deployment all completed with `failed=0` |
| Terraform / AWS | `terraform apply` created 17 resources in `ap-southeast-1`; the environment was then removed with `terraform destroy`, so **no AWS resources are running** |
| GitHub Actions CI | `ansible-lint`, playbook syntax checks, `terraform fmt`, `terraform validate` |

## Architecture

**Local lab**

```text
        Ansible control node
                |
              SSH
         +------+------+
         |             |
      web-01         db-01
   (Ubuntu 24.04) (Ubuntu 24.04)
```

**AWS environment (Terraform)**

```text
                 Internet
                     |
            Internet Gateway
                     |
 +------------- VPC 10.20.0.0/16 -------------+
 |                                            |
 |  Public subnet 10.20.1.0/24                |
 |    web-01 (EC2, Elastic IP)  NAT gateway   |
 |    SSH from one admin /32, HTTP, HTTPS     |
 |                    |                       |
 |             SSH from web-01 only           |
 |                    |                       |
 |  Private subnet 10.20.2.0/24               |
 |    db-01 (EC2, no public IP)               |
 |    outbound traffic via the NAT gateway    |
 +--------------------------------------------+
```

Terraform creates the network and the instances. Ansible configures the servers. `db-01` has no public address, so Ansible reaches it through `web-01` using SSH `ProxyJump`. The Terraform output `ansible_inventory` prints a ready-to-use inventory that already contains this setting.

## Repository layout

```text
.
├── .github/workflows/ansible-ci.yml   CI: lint, syntax checks, Terraform fmt and validate
├── ansible.cfg                        Inventory path, host key checking on
├── inventory.ini                      Local lab inventory
├── group_vars/
│   ├── all/vault.yml                  Ansible Vault encrypted variables
│   ├── web.yml                        Opens HTTP and HTTPS on web servers
│   └── db.yml                         Keeps HTTP and HTTPS closed on database servers
├── playbooks/                         hardening, compliance, drift_check, verify,
│                                      monitor, deploy_nginx, test
├── roles/
│   ├── server_hardening/              users, ssh, firewall, fail2ban, updates, auditd
│   └── nginx_web/                     Nginx and a small index page
├── terraform/                         AWS infrastructure
└── docs/proof/                        Screenshots of local and AWS runs
```

## What the Ansible role does

| Area | Implementation |
|------|----------------|
| Admin user | `sysadmin` account in the `sudo` group with the control node's public key. A sudoers drop-in validated with `visudo -cf` grants passwordless sudo by default, as a lab setting (`server_hardening_admin_passwordless_sudo`) |
| SSH | Drop-in config at `/etc/ssh/sshd_config.d/00-ansible-hardening.conf`, validated with `sshd -t`; root login and password authentication disabled, public-key authentication enabled |
| Firewall | UFW with incoming denied by default; SSH allowed; HTTP and HTTPS allowed on the `web` group only (`server_hardening_ufw_allow_http` and `server_hardening_ufw_allow_https`, set in `group_vars/`) |
| Fail2ban | SSH jail (systemd backend): 5 attempts in 10 minutes, 10-minute ban |
| Updates | `unattended-upgrades` installed and configured |
| Auditing | `auditd` rules watching `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config`, and `/etc/ssh/sshd_config.d/` |

Tasks run in a deliberate order: the admin user and key first, then SSH, then the firewall, so a run does not lock itself out. Handlers reload SSH, restart Fail2ban, and load audit rules once at the end of the play.

### Compliance check

`compliance.yml` asserts the effective SSH settings (read with `sshd -T`, not from the config file), UFW status and default policies, Fail2ban, the automatic update configuration, and `auditd`. It fails if any check fails.

### Drift check

`drift_check.yml` compares the effective SSH port, root login, password authentication, and public-key authentication with the expected policy. It reports each setting as compliant or drifted and fails on a mismatch. It does not fix anything. It was tested with a deliberately mismatched expected value, so it demonstrates mismatch detection, not detection of an unauthorized change on a live server.

### Other playbooks

- `verify.yml`: reports SSH service state.
- `monitor.yml`: reports SSH service state and root filesystem usage, warning at 80 percent.
- `deploy_nginx.yml`: deploys Nginx on the `web` group.
- `test.yml`: checks reachability.

## Quick start (local VMs)

You need an Ansible control node, SSH access to the servers, the Vault password for `group_vars/all/vault.yml`, and an SSH public key at `~/.ssh/id_ed25519.pub` (the role installs it for `sysadmin`). Host key checking is on, so connect to each server once so its key is in `known_hosts`.

```bash
git clone https://github.com/tvero1011/ansible-server-hardening.git
cd ansible-server-hardening
python3 -m venv .venv && source .venv/bin/activate
python -m pip install ansible-core ansible-lint
ansible-galaxy collection install ansible.posix community.general
# edit inventory.ini: replace the lab IP addresses and ansible_user with your own
ansible all -m ping --ask-vault-pass
ansible-playbook playbooks/hardening.yml --ask-vault-pass
ansible-playbook playbooks/compliance.yml --ask-vault-pass
ansible-playbook playbooks/drift_check.yml --ask-vault-pass
```

To avoid typing the Vault password each time, save it in a file outside the repository (for example `~/.vault_pass`, mode `600`) and set `ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass`.

Run the hardening playbook a second time to check repeatability; a second run should report `changed=0`. SSH and firewall changes can lock you out, so confirm you have another way in before applying them to a server you care about.

## Deploying on AWS

**Cost warning:** this creates billable resources. The NAT gateway and the public IPv4 addresses are charged by the hour while they exist, so destroy the environment when you finish.

Prerequisites: Terraform 1.5 or newer, AWS credentials configured on the machine running it (this project was run with an IAM Identity Center profile and `aws sso login`), and the Ansible setup from the quick start.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars:
#   admin_cidr = your public IP with /32   (curl https://checkip.amazonaws.com)
#   public_key = contents of ~/.ssh/id_ed25519.pub
terraform init
terraform plan
terraform apply
terraform output -raw ansible_inventory > ../inventory.aws.ini
cd ..

# host key checking is on: connect once to accept each server's key
ssh ubuntu@WEB_PUBLIC_IP exit
ssh -J ubuntu@WEB_PUBLIC_IP ubuntu@DB_PRIVATE_IP exit

ansible all -i inventory.aws.ini -m ping
ansible-playbook -i inventory.aws.ini playbooks/hardening.yml
ansible-playbook -i inventory.aws.ini playbooks/compliance.yml
ansible-playbook -i inventory.aws.ini playbooks/deploy_nginx.yml

# when finished
terraform -chdir=terraform destroy
```

`terraform.tfvars`, Terraform state, and the generated `inventory.aws.ini` must not be committed (see `.gitignore`).

### What Terraform creates

17 resources: a VPC, a public and a private subnet, an internet gateway, a NAT gateway with its Elastic IP, a public and a private route table with their associations, two security groups, an SSH key pair, an Elastic IP for `web-01`, and two Ubuntu 24.04 EC2 instances (`t3.micro`, encrypted 8 GB gp3 root volumes, IMDSv2 required).

- SSH to the web server is limited to one administrator address (`admin_cidr`, which must be a `/32`); HTTP and HTTPS are open to the internet.
- The database server accepts SSH only from the web server's security group and has no public IP.
- The default region is `ap-southeast-1`.

### Terraform checks in CI

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

`validate` only checks syntax and internal consistency. It does not contact AWS.

## CI

The workflow in `.github/workflows/ansible-ci.yml` runs on pushes, pull requests, and manual dispatch. It runs `ansible-lint` on all playbooks and roles, syntax-checks every playbook in `playbooks/`, and runs the Terraform format check, backend-free init, and validate. It does not connect to any servers or to AWS, so it checks code quality, not that the controls work on a live host.

## Evidence

Screenshots are in [`docs/proof/`](docs/proof/).

**Local lab**

| Step | Screenshot |
|------|------------|
| Ansible ping to `web-01` and `db-01` | `00-ansible-connectivity.png` |
| Second hardening run: `changed=0`, `failed=0` | `01-hardening-success.png` |
| Compliance run: `failed=0` | `02-compliance-success.png` |
| Drift check failing on a deliberate mismatch | `03-ssh-drift-detection.png` |
| Passing GitHub Actions runs | `04-github-actions-ci.png` |

**AWS run**

| Step | Screenshot |
|------|------------|
| `terraform apply`: 17 resources added, with the generated inventory | `05-terraform-apply.png` |
| Ansible ping to `web-01` and `db-01` (the latter through the jump host) | `06-aws-ansible-ping.png` |
| First hardening run: `failed=0`, `unreachable=0` (`db-01` changed=13, `web-01` changed=15) | `07-aws-hardening.png` |
| Compliance run: `ok=12`, `changed=0`, `failed=0` on both hosts | `08-aws-compliance.png` |
| EC2 console: both instances running | `09-aws-console-ec2.png` |
| Nginx deployment and the page served by `web-01` | `10-aws-nginx.png` |

## Known limitations

- **No TLS:** the Nginx page is served over HTTP on port 80. HTTPS is open in the firewall and security group, but no certificate is configured.
- **Passwordless sudo:** the `sysadmin` account gets passwordless sudo because it is a key-only account in a lab. For a production server, set `server_hardening_admin_passwordless_sudo: false` and manage sudo access another way.
- **Idempotency and drift on AWS:** the `changed=0` re-run and the drift check were done on the local lab, not on the AWS instances. The AWS run shows a first hardening run only.
- **Compliance and drift coverage:** the compliance playbook is a focused baseline, not a standard such as CIS, and does not check the admin user, the HTTP and HTTPS rules, or the audit rules. The drift check covers four SSH settings and only reports.
- **Terraform state and layout:** state is local, the environment uses a single availability zone, there are no VPC flow logs, and outbound traffic is open on both security groups.
- **Cost:** the NAT gateway makes the private subnet usable for package updates, but it is billed hourly. It is the main cost of this setup, so destroy the environment after use.
- **Inventory:** `inventory.ini` holds the lab IPs. For AWS, the inventory comes from the Terraform output but is saved to a file by hand.
- **Logging:** Fail2ban and `auditd` record events but do not alert anyone.
- **No integration tests:** CI checks code quality only. There are no tests against live servers, no Terraform security scanning, and no remote Terraform state.

## Next steps

1. Add TLS to the Nginx role (for example with a certificate from Let's Encrypt).
2. Repeat hardening and the drift check on a fresh AWS deployment to show `changed=0` and drift detection there.
3. Add Terraform security scanning and role tests (for example `checkov` and Molecule).
4. Store Terraform state remotely (S3 with locking) and spread the environment across two availability zones.
5. Extend the compliance and drift checks to UFW, services, and audit rules, with an opt-in remediation run.
6. Replace the NAT gateway with a cheaper option for lab use, such as a NAT instance.

## Author

[@tvero1011](https://github.com/tvero1011)
