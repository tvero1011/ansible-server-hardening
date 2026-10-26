
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
  value       = aws_instance.web.public_ip
}

output "db_instance_id" {
  description = "EC2 instance ID of the database server"
  value       = aws_instance.db.id
}

output "db_private_ip" {
  description = "Private IP address of the database server"
  value       = aws_instance.db.private_ip
}
