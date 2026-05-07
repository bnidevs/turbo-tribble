# =============================================================================
# Static Website Infrastructure
# S3 (public static hosting) → CloudFront → Route 53 + ACM
# =============================================================================
#
# PREREQUISITES:
#   - The domain_name variable must be a domain you own.
#   - After applying, you must update your domain registrar's nameservers
#     to the ones output by the Route 53 hosted zone (see outputs).
#   - ACM DNS validation will not complete until the hosted zone is
#     authoritative for the domain (i.e., nameservers are pointed).
#
# USAGE:
#   terraform init
#   terraform plan -var="domain_name=example.com"
#   terraform apply -var="domain_name=example.com"
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

# ACM certificates for CloudFront MUST be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "The root domain name (e.g., example.com)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the S3 bucket and other regional resources"
  type        = string
  default     = "us-east-1"
}

variable "index_document" {
  description = "The index document for the S3 static website"
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "The error document for the S3 static website"
  type        = string
  default     = "error.html"
}

# -----------------------------------------------------------------------------
# S3 Bucket — Public Static Website Hosting
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "website" {
  bucket = var.domain_name
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = var.index_document
  }

  error_document {
    key = var.error_document
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  depends_on = [aws_s3_bucket_public_access_block.website]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Route 53 Hosted Zone
# -----------------------------------------------------------------------------

resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# -----------------------------------------------------------------------------
# ACM Certificate (us-east-1, required for CloudFront)
# -----------------------------------------------------------------------------

resource "aws_acm_certificate" "website" {
  provider = aws.us_east_1

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.website.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "website" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.website.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# -----------------------------------------------------------------------------
# CloudFront Distribution
# -----------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.index_document
  aliases             = [var.domain_name]
  price_class         = "PriceClass_100"

  origin {
    # Use the S3 website endpoint, NOT the REST endpoint
    domain_name = aws_s3_bucket_website_configuration.website.website_endpoint
    origin_id   = "S3WebsiteOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3WebsiteOrigin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.website.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_acm_certificate_validation.website]
}

# -----------------------------------------------------------------------------
# Route 53 A Record → CloudFront
# -----------------------------------------------------------------------------

resource "aws_route53_record" "website_a" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "nameservers" {
  description = "Update your domain registrar with these nameservers"
  value       = aws_route53_zone.main.name_servers
}

output "cloudfront_distribution_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (needed for cache invalidation)"
  value       = aws_cloudfront_distribution.website.id
}

output "s3_website_endpoint" {
  description = "S3 static website endpoint (publicly accessible — this bypasses CloudFront)"
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "website_url" {
  description = "The live website URL"
  value       = "https://${var.domain_name}"
}
