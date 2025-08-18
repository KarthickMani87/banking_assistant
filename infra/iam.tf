
data "aws_iam_policy_document" "terraform_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:*",
      "ecs:*",
      "ecr:*",
      "iam:*",
      "s3:*",
      "cloudfront:*",
      "secretsmanager:*",
      "rds:*",
      "logs:*",
      "elasticloadbalancing:*",
      "sts:GetCallerIdentity",
      "ec2:DescribeAvailabilityZones"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_full_access" {
  name        = "TerraformFullInfraAccess"
  description = "Broad permissions for Terraform infra provisioning"
  policy      = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "ecs:*",
        "ecr:*",
        "secretsmanager:*",
        "cloudfront:*",
        "iam:*",
        "s3:*"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_iam_user_policy_attachment" "terraform_user_attach" {
  user       = "intelligent_document_answer"
  policy_arn = aws_iam_policy.terraform_full_access.arn
}


resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-frontend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_s3" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_cloudfront" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudFrontFullAccess"
}

