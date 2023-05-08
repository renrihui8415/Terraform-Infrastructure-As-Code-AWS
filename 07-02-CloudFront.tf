locals {
  s3_origin_id="S3-${local.bucket_name_for_web}"
}

#1 to create Cloudfront
  #1.1 to create OAC(Origin Access Control)
  #1.2 to create cloudfront

# below is to create OAC
# Note: OAC is the successor of OAI
# Both can be used in cloudfront up until now
resource "aws_cloudfront_origin_access_control" "example" {
  name                              = "${local.prefix}-cloudfront-oac"
  description                       = "no comment"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  # always , never, no-override
  signing_protocol                  = "sigv4"
}
# below is to create Cloudfront distribution

resource "aws_cloudfront_distribution" "example" {
  origin {
    domain_name              = aws_s3_bucket.example.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.example.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "tf"

  aliases = ["${local.domain_name}"]
  # this alternate domain name or CNAME is a must,
  # when we wish to use R53 to provide service for your domain.
  # Note: the aliases in cloudfront should be the same as record name in r53
  # if we set "*.example.com", then, all url like ab.example.com,
  # www.example.com will all get to cloudfront

  web_acl_id = aws_wafv2_web_acl.example.arn
default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      #restriction_type = "none"
      restriction_type = "whitelist"
      locations        = ["US", "CA"]
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.issued.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }

  tags = {
    Name                     = "${local.prefix}-cloudfront-web-bucket"
    Environment              = "Dev"
  }
}
output "cloudfront_domain_name_for_web" {
  value = aws_cloudfront_distribution.example.domain_name
}

