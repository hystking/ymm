variable "project_name" {
  description = "Name prefix for all resources and the S3 bucket."
  type        = string
  default     = "ymm-music-player"
}

variable "aws_region" {
  description = "AWS region for the S3 bucket. CloudFront itself is global."
  type        = string
  default     = "ap-northeast-1"
}

variable "basic_auth_user" {
  description = "Username for Basic Auth at the CloudFront edge."
  type        = string
  default     = "admin"
}

variable "basic_auth_password" {
  description = "Password for Basic Auth. Pass via TF_VAR_basic_auth_password or -var; never commit it."
  type        = string
  sensitive   = true
}

variable "basic_auth_realm" {
  description = "Realm shown in the browser's Basic Auth prompt."
  type        = string
  default     = "ymm music player"
}

variable "price_class" {
  description = "CloudFront price class (PriceClass_100 is cheapest: US/EU edges)."
  type        = string
  default     = "PriceClass_200"
}
