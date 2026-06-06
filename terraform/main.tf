terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  site_dir = "${path.module}/../site"

  # Map file extensions to content types so the browser interprets assets correctly.
  content_types = {
    html = "text/html"
    js   = "application/javascript"
    css  = "text/css"
    json = "application/json"
    mp3  = "audio/mpeg"
    png  = "image/png"
    jpg  = "image/jpeg"
    svg  = "image/svg+xml"
    ico  = "image/x-icon"
  }
}

# ---------------------------------------------------------------------------
# S3 bucket — private origin for the static site + music + playlist.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "site" {
  bucket = var.project_name
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Allow CloudFront (via Origin Access Control) to read objects — and nobody else.
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipalRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
        }
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# Static site assets (everything under ../site). Music mp3s are uploaded
# separately with deploy.sh so re-applying Terraform stays fast.
# ---------------------------------------------------------------------------
resource "aws_s3_object" "site_assets" {
  for_each = fileset(local.site_dir, "**/*")

  bucket       = aws_s3_bucket.site.id
  key          = each.value
  source       = "${local.site_dir}/${each.value}"
  etag         = filemd5("${local.site_dir}/${each.value}")
  content_type = lookup(local.content_types, lower(regex("[^.]*$", each.value)), "application/octet-stream")
}

# ---------------------------------------------------------------------------
# CloudFront Origin Access Control — modern replacement for OAI.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------------------------------------
# Basic Auth at the edge via a CloudFront Function (no Lambda needed).
# ---------------------------------------------------------------------------
resource "aws_cloudfront_function" "basic_auth" {
  name    = "${var.project_name}-basic-auth"
  runtime = "cloudfront-js-2.0"
  comment = "HTTP Basic Auth gate for ${var.project_name}"
  publish = true
  code = templatefile("${path.module}/basic_auth.js.tftpl", {
    auth_b64 = base64encode("${var.basic_auth_user}:${var.basic_auth_password}")
    realm    = var.basic_auth_realm
  })
}

# ---------------------------------------------------------------------------
# CloudFront distribution.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"
  comment             = var.project_name
  price_class         = var.price_class

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.site.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.site.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Managed "CachingOptimized" policy.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.basic_auth.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
