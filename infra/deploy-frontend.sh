#!/bin/bash
set -e

cd ../banking-assistant

echo "👉 Installing dependencies..."
npm install

echo "👉 Building frontend with .env.production..."
npm run build -- --mode production

echo "👉 Syncing build to S3..."
aws s3 sync dist/ s3://$(terraform output -raw s3_bucket_name) --delete

echo "👉 Invalidating CloudFront cache..."
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"

echo "✅ Frontend deployed at: https://$(terraform output -raw cloudfront_domain)"

