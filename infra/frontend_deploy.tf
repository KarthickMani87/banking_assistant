resource "aws_s3_object" "frontend" {
  for_each = fileset("${path.module}/../frontend/dist", "**")

  bucket = var.frontend_bucket_name
  key    = each.value
  source = "${path.module}/../frontend/dist/${each.value}"
  etag   = filemd5("${path.module}/../frontend/dist/${each.value}")
}

resource "null_resource" "invalidate_cloudfront" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.frontend.id} --paths '/*'"
  }
}

