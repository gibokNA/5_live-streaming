output "server_public_ip" {
  description = "Jitsi 서버의 공인 IP (Elastic IP)"
  value       = aws_eip.jitsi_eip.public_ip
}

output "jitsi_url" {
  description = "화상회의 접속 URL"
  value       = "https://${aws_route53_record.jitsi_dns.name}"
}

output "ssh_command" {
  description = "서버 접속 명령어"
  value       = "ssh -i ${aws_instance.jitsi_server.key_name}.pem ubuntu@${aws_route53_record.jitsi_dns.name}"
}