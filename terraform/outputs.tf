output "vpc_id" {
  description = "ID of the project VPC"
  value       = aws_vpc.main.id
}

output "web_instance_id" {
  description = "EC2 instance ID of the web server"
  value       = aws_instance.web.id
}

output "web_public_ip" {
  description = "Public IP address of the web server"
  value       = aws_eip.web.public_ip
}

output "db_instance_id" {
  description = "EC2 instance ID of the database server"
  value       = aws_instance.db.id
}

output "db_private_ip" {
  description = "Private IP address of the database server"
  value       = aws_instance.db.private_ip
}

output "ansible_inventory" {
  description = "Ready-to-paste inventory.ini for the AWS environment (db-01 is reached through web-01)"
  value       = <<-EOT
    [web]
    web-01 ansible_host=${aws_eip.web.public_ip}

    [db]
    db-01 ansible_host=${aws_instance.db.private_ip}

    [db:vars]
    ansible_ssh_common_args='-o ProxyJump=ubuntu@${aws_eip.web.public_ip}'

    [all:vars]
    ansible_user=ubuntu
  EOT
}
