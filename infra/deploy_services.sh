#!/usr/bin/env bash
set -euo pipefail

# usage:
#   ./push-services.sh dev                -> builds all services
#   ./push-services.sh dev voiceauth push -> builds only these services

ENVIRONMENT=${1:-dev}
shift || true   # remove the first arg (environment), keep the rest

# AWS Info
#$(terraform output -raw aws_region)
AWS_REGION="ap-southeast-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URL="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Define services + paths
declare -A SERVICES=(
  ["llm-backend"]="../chat-stack/backend"
  ["voiceauth"]="../voiceAuth"
  ["stt"]="../stt-backend"
  ["tts"]="../tts-backend"
  ["push"]="../push-backend"
)

# Decide which services to build
if [[ $# -gt 0 ]]; then
  SERVICES_TO_BUILD=("$@")
else
  SERVICES_TO_BUILD=("${!SERVICES[@]}")
fi

# Login to ECR
echo "🔑 Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_URL"

# Build & push selected services
for SERVICE in "${SERVICES_TO_BUILD[@]}"; do
  CONTEXT_DIR="${SERVICES[$SERVICE]:-}"
  if [[ -z "$CONTEXT_DIR" ]]; then
    echo "❌ Unknown service: $SERVICE"
    exit 1
  fi

  IMAGE="$ECR_URL/$SERVICE:latest"

  echo "------------------------------------------------------"
  echo "🐳 Building and pushing $SERVICE"
  echo "Context: $CONTEXT_DIR"
  echo "Image:   $IMAGE"
  echo "------------------------------------------------------"

  # Create repo if missing
  aws ecr describe-repositories \
    --repository-names "$SERVICE" \
    --region "$AWS_REGION" >/dev/null 2>&1 || \
  aws ecr create-repository \
    --repository-name "$SERVICE" \
    --region "$AWS_REGION"

  docker build --no-cache -t "$IMAGE" "$CONTEXT_DIR"
  docker push "$IMAGE"
done

echo "✅ Done! Images are built and pushed to ECR (tagged as :latest)."
