#!/usr/bin/env bash
#
# Sync the static site + music + playlist to S3 and invalidate the CloudFront
# cache. Terraform owns only the infrastructure; *all* bucket contents are
# uploaded here. Reads the bucket name and distribution id from Terraform
# outputs, so run `terraform apply` at least once first.
#
# Usage:
#   scripts/deploy.sh            # regenerate playlist, upload site + music + playlist
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"

source $ROOT/.env

command -v aws >/dev/null || { echo "aws CLI not found. Install it first." >&2; exit 1; }

BUCKET="$(terraform -chdir="$TF_DIR" output -raw s3_bucket)"
DIST_ID="$(terraform -chdir="$TF_DIR" output -raw cloudfront_distribution_id)"

echo "Bucket:       $BUCKET"
echo "Distribution: $DIST_ID"

# 1. Regenerate playlist.json from the local music files.
"$ROOT/scripts/gen-playlist.sh"

# 2. Upload mp3s (long cache — audio rarely changes once uploaded).
echo "Uploading music…"
aws s3 sync "$ROOT/music/" "s3://$BUCKET/music/" \
  --exclude ".*" --content-type "audio/mpeg" \
  --cache-control "public, max-age=86400"

# 3. Upload the static site assets (small — re-uploaded every deploy).
echo "Uploading site assets…"
aws s3 cp "$ROOT/site/index.html" "s3://$BUCKET/index.html" --content-type "text/html"  --cache-control "no-cache"
aws s3 cp "$ROOT/site/app.js"     "s3://$BUCKET/app.js"     --content-type "application/javascript"
aws s3 cp "$ROOT/site/style.css"  "s3://$BUCKET/style.css"  --content-type "text/css"

# 4. Upload the playlist (no cache — it changes whenever tracks change).
echo "Uploading playlist…"
aws s3 cp "$ROOT/site/playlist.json" "s3://$BUCKET/playlist.json" \
  --content-type "application/json" --cache-control "no-cache"

# 5. Invalidate CloudFront so changes appear immediately.
echo "Invalidating CloudFront (/*)…"
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*" >/dev/null

echo "Done. Open the CloudFront URL:"
terraform -chdir="$TF_DIR" output -raw cloudfront_url; echo
