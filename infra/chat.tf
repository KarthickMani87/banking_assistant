# ---------- ECR Repos ----------
resource "aws_ecr_repository" "ollama" {
  name = "ollama"
}

resource "aws_ecr_repository" "llm_backend" {
  name = "llm-backend"
}

# ---------- ECS Task: Ollama ----------
resource "aws_ecs_task_definition" "ollama" {
  family                   = "ollama"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "2048"
  memory                   = "4096"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "ollama"
      image     = "${aws_ecr_repository.ollama.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 11434
          hostPort      = 11434
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "MODEL_NAME", value = "qwen2.5:3b-instruct" },
      ]
    }
  ])
}

# ---------- ECS Task: llm-backend ----------
resource "aws_ecs_task_definition" "llm_backend" {
  family                   = "llm-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "llm-backend"
      image     = "${aws_ecr_repository.llm_backend.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PGUSER", value = "bankuser" },
        { name = "PGPASSWORD", value = var.db_password },
        { name = "PGDATABASE", value = "bankdb" },
        { name = "PGHOST", value = aws_db_instance.banking.address },
        { name = "PGPORT", value = "5432" },
        { name = "JWT_SECRET", value = aws_secretsmanager_secret_version.jwt_value.secret_string },
        { name = "OLLAMA_BASE_URL", value = "http://ollama:11434" },
        { name = "MODEL_NAME", value = "qwen2.5:3b-instruct" },
        { name = "TEMPERATURE", value = "0.3" },
        { name = "NUM_CTX", value = "4096" },
        { name = "CORS_ORIGINS", value = "https://${aws_cloudfront_distribution.frontend.domain_name}" },
      ]
    }
  ])
}

# ---------- ECS Services ----------
resource "aws_ecs_service" "ollama" {
  name            = "ollama"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ollama.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.ecs_service.id]
    assign_public_ip = true
  }
}

resource "aws_ecs_service" "llm_backend" {
  name            = "llm-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.llm_backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.ecs_service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.llm_backend.arn
    container_name   = "llm-backend"
    container_port   = 5000
  }

  depends_on = [aws_lb_listener.http]
}

# ---------- Target Group ----------
resource "aws_lb_target_group" "llm_backend" {
  name        = "llm-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path = "/docs"
  }
}

# ---------- Listener Rule ----------
resource "aws_lb_listener_rule" "llm_backend" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.llm_backend.arn
  }

  condition {
    path_pattern {
      values = ["/chat/*"]
    }
  }
}
