###########################
# S3 Bucket (private)
###########################

resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project_name}-${var.env}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-${var.env}"
    Environment = var.env
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

###########################
# CloudFront OAI
###########################

resource "aws_cloudfront_origin_access_identity" "frontend" {
  comment = "OAI for ${var.project_name}-${var.env}"
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowCloudFrontRead",
        Effect = "Allow",
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.frontend.iam_arn
        },
        Action   = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
}

###########################
# CloudFront Distribution
###########################

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"

  # 🔹 Origin for static frontend (S3)
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "s3-frontend"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.frontend.cloudfront_access_identity_path
    }
  }

  # 🔹 Origin for backend (EC2 with Nginx)
  origin {
    domain_name = "ec2-${replace(aws_eip.backend_eip.public_ip, ".", "-")}.${var.region}.compute.amazonaws.com"
    origin_id   = "ec2-backend"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]

      # ⏳ Increase timeouts
      origin_read_timeout      = 60   # default 30
      origin_keepalive_timeout = 10   # default 5

    }
  }

  # Default: serve static files
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-frontend"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  ###########################
  # Backend Behaviors (base + wildcard for each API)
  ###########################

  # VoiceAuth
 ordered_cache_behavior {
    path_pattern     = "/voiceauth/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ec2-backend"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies { forward = "all" }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  # STT
  ordered_cache_behavior {
    path_pattern     = "/stt/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ec2-backend"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies { forward = "all" }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  # TTS
  ordered_cache_behavior {
    path_pattern     = "/tts/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ec2-backend"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies { forward = "all" }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  # LLM
  ordered_cache_behavior {
    path_pattern     = "/llm/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ec2-backend"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies { forward = "all" }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  ###########################

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.env}-cf"
    Environment = var.env
  }
}

###########################
# Frontend Runtime Config
###########################

resource "local_file" "frontend_config" {
  filename = "${path.module}/../banking-assistant/public/config.json"

  content = jsonencode({
    STT_URL        = "https://${aws_cloudfront_distribution.frontend.domain_name}/stt"
    TTS_URL        = "https://${aws_cloudfront_distribution.frontend.domain_name}/tts"
    LLM_URL        = "https://${aws_cloudfront_distribution.frontend.domain_name}/llm"
    VOICE_AUTH_URL = "https://${aws_cloudfront_distribution.frontend.domain_name}/voiceauth"
    SESSION_ID     = uuid()
  })
}

###########################
# Frontend Build & Deploy
###########################
resource "null_resource" "frontend_deploy" {
  depends_on = [
    local_file.frontend_config,
    aws_s3_bucket.frontend,
    aws_cloudfront_distribution.frontend
  ]

  triggers = {
    always_run = timestamp()
    config_hash = sha256(local_file.frontend_config.content)
    build_hash  = filesha256("${path.module}/../banking-assistant/package.json")
  }

provisioner "local-exec" {
  command = <<EOT
    set -e
    cd ${path.module}/../banking-assistant

    # Clean and rebuild
    rm -rf dist node_modules package-lock.json
    npm cache clean --force
    npm install --legacy-peer-deps
    npm run build

    # Ensure runtime config.json is included in dist/
    cp public/config.json dist/config.json
  EOT
}

  provisioner "local-exec" {
      command = <<EOT
    aws s3 rm s3://${aws_s3_bucket.frontend.bucket} --recursive || true
    aws s3 sync ${path.module}/../banking-assistant/dist s3://${aws_s3_bucket.frontend.bucket} --delete
  EOT
  }

  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.frontend.id} --paths '/*'"
  }
}
