# ---------- ECR Repo ----------
resource "aws_ecr_repository" "voiceauth" {
  name = "voiceauth-backend"
}

# ---------- ECS Task ----------
resource "aws_ecs_task_definition" "voiceauth" {
  family                   = "voiceauth-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "voiceauth"
      image     = "${aws_ecr_repository.voiceauth.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "JWT_SECRET", value = var.jwt_key },
        { name = "CORS_ORIGINS", value = "https://${aws_cloudfront_distribution.frontend.domain_name}" }
      ]
    }
  ])
}

# ---------- Target Group ----------
resource "aws_lb_target_group" "voiceauth" {
  name        = "voiceauth-tg"
  port        = 9000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path = "/healthz"
  }
}

# ---------- ECS Service ----------
resource "aws_ecs_service" "voiceauth" {
  name            = "voiceauth-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.voiceauth.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.ecs_service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.voiceauth.arn
    container_name   = "voiceauth"
    container_port   = 8080
  }
}

# ---------- Listener Rule ----------
resource "aws_lb_listener_rule" "voiceauth" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.voiceauth.arn
  }

  condition {
    path_pattern {
      values = ["/voice-login", "/enroll/*"]
    }
  }
}

