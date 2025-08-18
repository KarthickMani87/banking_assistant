#######################
# Networking
#######################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "bank-vpc" }
}

locals {
  availability_zones = ["ap-southeast-2a", "ap-southeast-2b"]
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "bank-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10)
  availability_zone = local.availability_zones[count.index]
  tags = { Name = "bank-private-${count.index}" }
}

# Internet Gateway + routing for ALB
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "bank-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#######################
# Security Groups
#######################
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id
  name   = "alb-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_service" {
  vpc_id = aws_vpc.main.id
  name   = "ecs-service-sg"

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#######################
# ECS Cluster
#######################
resource "aws_ecs_cluster" "main" {
  name = "bank-cluster"
}

#######################
# ECS Task Execution Role
#######################
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach AWS-managed policy (ECR + CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Extra inline policy (Secrets Manager + KMS)
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "ecs-execution-secrets"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ],
        Resource = "*"
      }
    ]
  })
}

#######################
# RDS Postgres
#######################
resource "aws_db_subnet_group" "banking" {
  name       = "banking-db-subnet"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "banking" {
  identifier              = "banking-db"
  allocated_storage       = 20
  engine                  = "postgres"
  engine_version          = "15.14"
  instance_class          = "db.t3.micro" # free tier
  db_name                 = "bankdb"
  username                = "bankuser"
  password                = var.db_password
  skip_final_snapshot     = true
  vpc_security_group_ids  = [aws_security_group.ecs_service.id]
  db_subnet_group_name    = aws_db_subnet_group.banking.name
  publicly_accessible     = false
}

#######################
# Secrets
#######################
resource "aws_secretsmanager_secret" "jwt" {
  name = "jwt-key"
}

resource "aws_secretsmanager_secret_version" "jwt_value" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = var.jwt_key
}

resource "aws_secretsmanager_secret" "voiceauth" {
  name = "voice-auth-key"
}

resource "aws_secretsmanager_secret_version" "voiceauth_value" {
  secret_id     = aws_secretsmanager_secret.voiceauth.id
  secret_string = var.voice_auth_secret
}
