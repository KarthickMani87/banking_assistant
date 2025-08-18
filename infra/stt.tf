# ---------- ECR Repo ----------
resource "aws_ecr_repository" "stt" {
  name = "stt-backend"
}

# ---------- ECS Task ----------
resource "aws_ecs_task_definition" "stt" {
  family                   = "stt-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "stt-backend"
      image     = "${aws_ecr_repository.stt.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PORT", value = "8000" },
        { name = "WHISPER_MODEL", value = "tiny.en" },
        { name = "WHISPER_COMPUTE_TYPE", value = "float32" },
        { name = "CORS_ALLOW_ORIGINS", value = "https://${aws_cloudfront_distribution.frontend.domain_name}" },
      ]
    }
  ])
}

# ---------- ECS Service ----------
resource "aws_ecs_service" "stt" {
  name            = "stt-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.stt.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.ecs_service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.stt.arn
    container_name   = "stt"
    container_port   = 8080
  }
}

# ---------- Target Group ----------
resource "aws_lb_target_group" "stt" {
  name        = "stt-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path = "/healthz"
  }
}

# ---------- Listener Rule ----------
resource "aws_lb_listener_rule" "stt" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stt.arn
  }

  condition {
    path_pattern {
      values = ["/stt/*"]
    }
  }
}
