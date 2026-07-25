output "instance_public_ip" {
  description = "Public IP address of the deployed SyncWrite EC2 instance"
  value       = aws_eip.syncwrite_eip.public_ip
}

output "ssh_connection_command" {
  description = "Command to connect to the EC2 instance via SSH"
  value       = "ssh -i ${var.public_key_path} ubuntu@${aws_eip.syncwrite_eip.public_ip}"
}

output "app_url" {
  description = "Public HTTP web URL for the deployed application"
  value       = "http://${aws_eip.syncwrite_eip.public_ip}"
}
