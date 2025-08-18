output "chat_url" {
  value = "http://${aws_lb.main.dns_name}/chat"
}

output "stt_url" {
  value = "http://${aws_lb.main.dns_name}/stt"
}

output "tts_url" {
  value = "http://${aws_lb.main.dns_name}/tts"
}

output "voice_auth_url" {
  value = "http://${aws_lb.main.dns_name}/voice-login"
}

output "rds_endpoint" {
  value = aws_db_instance.banking.endpoint
}

output "frontend_url" {
  value = "http://${aws_s3_bucket.frontend.bucket_regional_domain_name}"
}

output "whoami" {
  value = data.aws_caller_identity.current.arn
}