provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

###########################
# Networking (VPC + Subnet)
###########################

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "main-public-subnet"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

###########################
# Security Group
###########################

resource "aws_security_group" "backend_sg" {
  name   = "all-services-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8002
    to_port     = 8002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 🔹 allow HTTP traffic for Nginx reverse proxy
  ingress {
    from_port   = 80
    to_port     = 80
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

###########################
# IAM Role + Instance Profile
###########################

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-${var.env}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-${var.env}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

###########################
# Postgres SQL bucket
###########################
resource "aws_s3_bucket" "db_scripts" {
  bucket        = "${var.project_name}-${var.env}-${data.aws_caller_identity.current.account_id}-db"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-${var.env}-db-bucket"
    Environment = var.env
  }
}

# Upload schema.sql
resource "aws_s3_object" "schema" {
  bucket = aws_s3_bucket.db_scripts.bucket
  key    = "schema.sql"
  source = "${path.module}/../chat-stack/schema.sql"
  etag   = filemd5("${path.module}/../chat-stack/schema.sql")
}

# Upload seed.sql
resource "aws_s3_object" "seed" {
  bucket = aws_s3_bucket.db_scripts.bucket
  key    = "seed.sql"
  source = "${path.module}/../chat-stack/seed.sql"
  etag   = filemd5("${path.module}/../chat-stack/seed.sql")
}

###########################
# EC2 Instance
###########################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "backend" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.backend_sg.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data_replace_on_change = true

  user_data = <<-EOF
#!/bin/bash
set -e

# Update and install Docker + Compose
yum update -y
amazon-linux-extras install docker -y
service docker start
usermod -a -G docker ec2-user
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

REGION=${var.region}
ACCOUNT_ID=${var.account_id}
BUCKET="${var.project_name}-${var.env}-${data.aws_caller_identity.current.account_id}-db"

# Authenticate Docker to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Create shared docker network
docker network create backend-net || true

# 🔹 Ollama
docker run -d --name ollama --network backend-net -p 11434:11434 \
  -e OLLAMA_NO_GPU=1 \
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -v ollama-data:/root/.ollama \
  ollama/ollama:latest

until docker exec ollama ollama list >/dev/null 2>&1; do sleep 2; done
docker exec ollama ollama pull qwen2.5:3b-instruct

# 🔹 LLM Backend
docker run -d --name llm-backend --network backend-net -p 5000:5000 \
  -e OLLAMA_BASE_URL=http://ollama:11434 \
  $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/llm-backend:latest

# 🔹 VoiceAuth
docker run -d --name voiceauth --network backend-net -p 8002:8000 \
  $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/voiceauth:latest

# 🔹 STT
docker run -d --name stt --network backend-net -p 8000:8000 \
  $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/stt:latest

# 🔹 TTS
docker run -d --name tts --network backend-net -p 8001:8000 \
  $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/tts:latest

# 🔹 PostgreSQL
docker run -d --name postgres --network backend-net -p 5432:5432 \
  -e POSTGRES_USER=bankuser \
  -e POSTGRES_PASSWORD=bankpass \
  -e POSTGRES_DB=bankdb \
  -v pgdata:/var/lib/postgresql/data \
  postgres:15

# Wait for Postgres
until docker exec postgres pg_isready -U bankuser; do
  echo "⏳ Waiting for Postgres..."
  sleep 2
done

  # Download schema + seed from S3
  aws s3 cp s3://$BUCKET/schema.sql /tmp/schema.sql
  aws s3 cp s3://$BUCKET/seed.sql /tmp/seed.sql

  # Load schema + seed
  docker cp /tmp/schema.sql postgres:/schema.sql
  docker cp /tmp/seed.sql postgres:/seed.sql
  docker exec -i postgres psql -U bankuser -d bankdb -f /schema.sql
  docker exec -i postgres psql -U bankuser -d bankdb -f /seed.sql

  # 🔹 Install and configure Nginx
  amazon-linux-extras enable nginx1
  yum clean metadata
  yum install -y nginx
  systemctl enable nginx
  systemctl start nginx

  cat <<'EOL' > /etc/nginx/conf.d/backend.conf
  server {
    listen 80;

    location /voiceauth/ {
      proxy_pass http://127.0.0.1:8002/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /stt/ {
      proxy_pass http://127.0.0.1:8000/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /tts/ {
      proxy_pass http://127.0.0.1:8001/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /llm/ {
      proxy_pass http://127.0.0.1:5000/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }
  }
  EOL

  nginx -t && systemctl restart nginx
  EOF


  tags = {
    Name = "all-services-backend"
  }
}

# 🔹 New: allocate Elastic IP
resource "aws_eip" "backend_eip" {
  instance = aws_instance.backend.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.env}-backend-eip"
  }
}
