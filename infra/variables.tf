variable "region" {
  description = "AWS region"
  default     = "ap-southeast-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.large"
}

variable "key_name" {
  description = "Name of the EC2 key pair"
  default     = ""
}

variable "private_key_path" {
  description = "Path to your private key (.pem)"
  default     = ""
}

variable "project_name" {
  description = "Name of the project/solution"
  default     = "chatbot-frontend"
}

variable "env" {
  description = "Deployment environment"
  default     = "dev"
}

variable "account_id" {
  description = "AWS Account ID where ECR repositories are located"
  type        = string
}

