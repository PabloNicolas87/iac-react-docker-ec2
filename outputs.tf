output "elastic_ip" {
  description = "Elastic IP address assigned to the EC2 instance"
  value       = aws_eip.app_eip.public_ip
}

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.app_server.id
}

output "app_url" {
  description = "Application public URL"
  value       = "http://${aws_eip.app_eip.public_ip}"
}
