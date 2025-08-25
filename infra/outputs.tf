# ec2.tf remains the same as you pasted (with Nginx config at the bottom)

###########################
# outputs.tf
###########################

output "backend_urls" {
  value = {
    chatstack = "http://${aws_eip.backend_eip.public_ip}/llm"
    stt       = "http://${aws_eip.backend_eip.public_ip}/stt"
    tts       = "http://${aws_eip.backend_eip.public_ip}/tts"
    voiceauth = "http://${aws_eip.backend_eip.public_ip}/voiceauth"
  }
}

output "ssh_command" {
  value = "ssh -i ${var.private_key_path} ec2-user@${aws_eip.backend_eip.public_ip}"
}


output "cloudfront_domain" {
  value = aws_cloudfront_distribution.frontend.domain_name
}

output "aws_region" {
  value = var.region
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
