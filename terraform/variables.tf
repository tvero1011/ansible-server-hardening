variable "aws_region" {
  description = "AWS region for the infrastructure"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Name prefix for project resources"
  type        = string
  default     = "ansible-hardening"
}

variable "admin_cidr" {
  description = "Public IP address allowed to SSH into the web server, in CIDR notation"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && can(regex("/32$", var.admin_cidr))
    error_message = "Use a single public IPv4 address in /32 CIDR notation, such as 203.0.113.10/32."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "public_key" {
  description = "SSH public key (contents of id_ed25519.pub) installed on both instances"
  type        = string
}
