# Ansible Server Hardening and Compliance

[![Ansible CI](https://github.com/tvero1011/ansible-server-hardening/actions/workflows/ansible-ci.yml/badge.svg)](https://github.com/tvero1011/ansible-server-hardening/actions/workflows/ansible-ci.yml)

Ansible automation that hardens Ubuntu servers, checks them against a security baseline, and detects SSH configuration drift. A Terraform configuration builds the AWS environment the playbooks run against. The whole workflow (Terraform apply, Ansible hardening, compliance check, Nginx deployment, Terraform destroy) has been run end to end on AWS.

## Status

| Part | Status |
|------|--------|
| Ansible hardening, compliance, and drift checks | Run and tested on two Ubuntu 24.04 Multipass VMs |
| Ansible on AWS | Run against two EC2 instances: ping, hardening, compliance, and Nginx deployment all succeeded with no failed tasks |
| Terraform / AWS | `terraform apply` created 17 resources in `ap-southeast-1`; the environment was then removed with `terraform destroy`, so **no AWS resources are currently running** |
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

Terraform creates the network and instances. Ansible configures the servers. `db-01` has no public address, so Ansible reaches it through `web-01` with SSH `ProxyJump`. The Terraform output `ansible_inventory` prints a ready-to-use inventory that already contains this setting.

## What the Ansible role does

| Area | Implementation |
|------|----------------|
| SSH | Drop-in config validated with `sshd -t`; root login and password authentication disabled, public-key authentication enabled |
| Admin user | `sysadmin` account in the `sudo` group with the control node's public key; passwordless sudo is enabled by default as a lab setting (`server_hardening_admin_passwordless_sudo`) |
| Firewall | UFW with incoming denied by default; SSH allowed; HTTP and HTTPS allowed on the `web` group only (controlled by `server_hardening_ufw_allow_http` and `server_hardening_ufw_allow_https`, set in `group_vars/`) |
| Fail2ban | SSH jail enabled and running |
| Updates | `unattended-upgrades` configured |
| Auditing | `auditd` rules watching `/etc/passwd`, `/etc/shadow`, `/etc/ssh/sshd_config`, and `/etc/ssh/sshd_config.d/` |

**Compliance check** (`compliance.yml`): asserts the effective SSH settings (read with `sshd -T`, not from the config file), UFW status and default policies, Fail2ban, auto-update config, and `auditd`. It fails if any check fails.

**Drift check** (`drift_check.yml`): compares the effective SSH port, root login, password authentication, and public-key authentication with the expected policy. It reports each setting and fails on a mismatch. It does not fix anything. I tested it with a deliberately mismatched expected value, so it shows mismatch detection, not detection of an unauthorized change on a live server.

Other playbooks: `verify.yml` and `monitor.yml` (SSH service state and disk usage), `deploy_nginx.yml` (Nginx on the web group), `test.yml` (reachability).

## Quick start (local VMs)

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

## Deploying on AWS

**Cost warning:** this creates billable resources. The NAT gateway and the Elastic IPs are charged by the hour while they exist, so destroy the environment when you finish.

Prerequisites: Terraform, AWS credentials configured on the machine running it, and the Ansible setup from the quick start.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars:
#   admin_cidr = your public IP with /32  (curl https://checkip.amazonaws.com)
#   public_key = contents of ~/.ssh/id_ed25519.pub
terraform init
terraform plan
terraform apply
terraform output -raw ansible_inventory > ../inventory.aws.ini
cd ..

ansible all -i inventory.aws.ini -m ping
ansible-playbook -i inventory.aws.ini playbooks/hardening.yml
ansible-playbook -i inventory.aws.ini playbooks/compliance.yml
ansible-playbook -i inventory.aws.ini playbooks/deploy_nginx.yml

# when finished
terraform -chdir=terraform destroy
```

`terraform.tfvars`, Terraform state, and the generated `inventory.aws.ini` must not be committed (see `.gitignore`).

### What Terraform creates

A VPC with a public and a private subnet, an internet gateway, a NAT gateway for the private subnet, route tables, two security groups, an SSH key pair, an Elastic IP for `web-01`, and two Ubuntu 24.04 EC2 instances (`t3.micro`, encrypted 8 GB root volumes, IMDSv2 required). SSH to the web server is limited to one administrator address (`admin_cidr`, which must be a `/32`). The default region is `ap-southeast-1`. The database server accepts SSH only from the web server's security group.

CI also runs the offline checks:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

`validate` only checks syntax and internal consistency. It does not contact AWS.

## CI and evidence

The workflow in `.github/workflows/ansible-ci.yml` runs on pushes, pull requests, and manual dispatch. It runs `ansible-lint`, syntax-checks every playbook in `playbooks/`, and runs the Terraform format check, backend-free init, and validate. It does not connect to any servers.

Screenshots are in [`docs/proof/`](docs/proof/).

**Local lab:** connectivity, a hardening run with `changed=0` and no failures, a compliance run, the drift check failing on a deliberate mismatch, and the passing CI runs.

**AWS run:**

| Step | Screenshot |
|------|------------|
| `terraform apply`: 17 resources added, with the generated inventory | `05-terraform-apply.png` |
| Ansible ping to `web-01` and `db-01` (the latter through the jump host) | `06-aws-ansible-ping.png` |
| Hardening run: no failed or unreachable hosts | `07-aws-hardening.png` |
| Compliance run: all checks passed, `failed=0` | `08-aws-compliance.png` |
| EC2 console: both instances running | `09-aws-console-ec2.png` |
| Nginx deployment and the page served by `web-01` | `10-aws-nginx.png` |

## Known limitations

- **Passwordless sudo:** the `sysadmin` account gets passwordless sudo because it is a key-only account in a lab. For a production server, set `server_hardening_admin_passwordless_sudo: false` and manage sudo access another way.
- **No TLS:** the Nginx page is served over HTTP on port 80. HTTPS is open in the firewall, but no certificate is configured.
- **Cost:** the NAT gateway makes the private subnet usable for package updates, but it is billed hourly. It is the main cost of this setup, so destroy the environment after use.
- **Static inventory for the local lab:** `inventory.ini` holds the lab IPs. For AWS, the inventory comes from the Terraform output but is still copied into a file by hand.
- **Drift check on AWS:** I ran the drift check on the local VMs, not on the AWS instances.
- **No integration tests:** CI checks code quality only. There are no tests against live servers, no Terraform security scanning, and no remote Terraform state.

## Next steps

1. Add TLS to the Nginx role (for example with a certificate from Let's Encrypt).
2. Add Terraform security scanning and role tests (for example `checkov` and Molecule).
3. Store Terraform state remotely (S3 with locking) instead of locally.
4. Run the drift check and a second hardening run (to confirm `changed=0`) on AWS and add the screenshots.
5. Replace the NAT gateway with a cheaper option for lab use, such as a VPC endpoint or an on-demand NAT instance.

## Author

[@tvero1011](https://github.com/tvero1011)
