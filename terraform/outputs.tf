output "cloudfront_url" {
  description = "Public URL of the music player (Basic Auth protected)."
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "Distribution ID — used by deploy.sh to invalidate the cache."
  value       = aws_cloudfront_distribution.cdn.id
}

output "s3_bucket" {
  description = "S3 bucket holding the site, music and playlist."
  value       = aws_s3_bucket.site.id
}

output "basic_auth_user" {
  description = "Configured Basic Auth username."
  value       = var.basic_auth_user
}
