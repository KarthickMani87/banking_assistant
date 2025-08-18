# ========== TTS Backend ==========
resource "aws_ecs_task_definition" "tts" {
  family                   = "tts-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"

  # Use the existing ecsTaskExecutionRole (imported)
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "tts-backend"
      image     = "${aws_ecr_repository.tts.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "CORS_ORIGINS"
          value = "https://${aws_cloudfront_distribution.frontend.domain_name}"
        },
        {
          name  = "MODEL_NAME"
          value = "tts_models/en/ljspeech/tacotron2-DDC_ph"
        },
        {
          name  = "AUDIO_FORMAT"
          value = "mp3"
        },
        {
          name  = "DEVICE"
          value = "cpu"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "tts" {
  name            = "tts-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.tts.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.ecs_service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tts.arn
    container_name   = "tts"
    container_port   = 8080
  }
}

resource "aws_lb_target_group" "tts" {
  name     = "tts-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/healthz"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

resource "aws_lb_listener_rule" "tts" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 40 # 🔥 bumped from 30 to 40 so it's unique

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tts.arn
  }

  condition {
    path_pattern {
      values = ["/tts*"]
    }
  }
}

# Optional ECR repo (build & push your image here)
resource "aws_ecr_repository" "tts" {
  name = "tts-backend"
}
