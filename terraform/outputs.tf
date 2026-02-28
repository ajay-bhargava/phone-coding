output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.phone_coding.id
}

output "public_ip" {
  description = "Public IP address"
  value       = aws_instance.phone_coding.public_ip
}

output "public_dns" {
  description = "Public DNS name"
  value       = aws_instance.phone_coding.public_dns
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh ubuntu@${aws_instance.phone_coding.public_ip}"
}

output "mosh_command" {
  description = "Mosh command to connect"
  value       = "mosh ubuntu@${aws_instance.phone_coding.public_ip}"
}

output "ttyd_url" {
  description = "Web terminal URL"
  value       = "http://${aws_instance.phone_coding.public_ip}:8080"
}
