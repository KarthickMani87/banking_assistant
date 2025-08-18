variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy infra"
}

variable "jwt_key" {
  type        = string
  description = "JWT signing secret"
  sensitive   = true
}

variable "voice_auth_secret" {
  type        = string
  description = "Secret used in voice authentication module"
  sensitive   = true
}

variable "db_password" {
  type        = string
  description = "Password for Postgres DB"
  default     = "bankpass" # matches what you used in base.tf
}

variable "frontend_bucket_name" {
  description = "Name of the S3 bucket for the frontend"
  type        = string
}

variable "iam_user_name" {
  description = "IAM user name to attach policies to"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID where infra will be deployed"
  type        = string
}