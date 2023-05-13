locals {
  s3_origin_id="S3-${local.bucket_name_for_web}"
  alb_origin_id="ALB-${local.domain_name_alb}"
  group_origin_id="${local.prefix}-origin-group"
}
# when we use cloudfront in front of EC2 or ALB,
# we need them to be public!
# this is different when we use s3_origin where s3 can be private

#1 to create Cloudfront distribution for origin group (ALB + S3).
#2 to create Route53 for Cloudfront alternate domain names

# Note: the domain_name for alb must be the same as the certificate for alb's https listener
# if we choose alb's DNS name in the console (like 12345.amazonaws.com)
# the browser will generate risk warnings telling us cloudfront is connecting a risky alb
# To solve the problem, we need to create certificate for the alb's domain name 
# however, the domain name ending with .amazonaws.com can't be a valid domain name for ACM
# So you need to create a subdomain name for alb using your own domain name, like alb.voirlemonde.link
# and create the cert and add it to https listener

#1 below is to create OAC
# when we have s3 as cf origin, access to s3 can be restricted 
# with OAC 
resource "aws_cloudfront_origin_access_control" "example" {
 
  name                              = "${local.prefix}-cloudfront-oac"
  description                       = "OAC of s3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  # always , never, no-override
  signing_protocol                  = "sigv4"
}
# below is to create cf, put S3 and ALB into one origin group
# and attach the group to cf
resource "aws_cloudfront_distribution" "example" {
   #retain_on_delete                  = true
  origin_group {
    origin_id = local.group_origin_id

    failover_criteria {
      status_codes = [400,403, 404,416, 500, 502,503,504]
    }

    member {
      origin_id = local.s3_origin_id
    }

    member {
      origin_id = local.alb_origin_id
    }
  }
  origin {
    domain_name              = aws_s3_bucket.example.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.example.id
    origin_id                = local.s3_origin_id
  }

  origin {
    domain_name = local.domain_name_alb
    # When ALB is created, AWS assigned a DNS name automatically for ALB
    # the format is like "1234.elb.amazonaws.com"
    # If we wish to use HTTPS between cloudfront and alb, we need to create a certificate 
    # for ALB's listener on 443 (Https).
    # DNS names ending with "elb.amazonaws.com" are invalid domain names for ACM (certificate)
    # The solution is to use a subdomain name like alb.example.com, use this domain name in the certificate
    # Assign the certificate in the ALB's listener
    # Don't forget to create a Rout53 record so that alb.example.com can point to elb.amazonaws.com.
    origin_id   = local.alb_origin_id
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
    # in order that alb only forward request from cf
    # we need to add headers to requests from cf
    custom_header {
      name     = "${local.cf_custom_header}"
      value    = "${local.cf_custom_header_value}"
    }
  }

  enabled             = true
  aliases             = [local.domain_name_cf,local.domain_name_cf_s3]
  
  # the aliases (alternate domain name or CNAME) is a must because we doesn't wish the internet users
  # access cloudfront by its DNS name (DNS name is automatically created by aws and its format is 
  # 12234.cloudfront.net). 
  # Use subdomain of your.example.com to be aliases,
  # meanwhile create a R53 record so that all requests from subdomain.example.com can be forwarded to 
  # 2334.cloudfront.net.
 
  web_acl_id = aws_wafv2_web_acl.example.arn
  
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = local.alb_origin_id
    # default behavior is the last behavior the cloudfront will refer to
    # the target_origin is the origin (can be s3, alb, api and so on) the request will be forwarded to
    viewer_protocol_policy = "redirect-to-https"
      forwarded_values {
        query_string = false

      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress = true
  }
  # Cache behavior with precedence 0
  # the order matters. the first non-default behavior has the most priority
  ordered_cache_behavior {
    path_pattern     = "/images/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    
  }
  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.alb_origin_id
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    
  }
  # we can restrict the access to cloudfront by locations.
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = local.geo_restriction
    }
  }
  #default_root_object = "index.html"
  tags = {
    Name                     = "${local.prefix}-cloudfront-origin-group"
    Environment              = "Dev"
  }
  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.cf.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }
  
}
output "cloudfront_domain_name_for_origin_group" {
  value = aws_cloudfront_distribution.example.domain_name
}
# to create a r53 record for aliases of cf
resource "aws_route53_record" "cf_alb" {
  zone_id = data.aws_route53_zone.web_voir.zone_id
  name    = "${local.domain_name_cf}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.example.domain_name
    zone_id                = aws_cloudfront_distribution.example.hosted_zone_id
    evaluate_target_health = false
  }
}
# to create a r53 record for aliases of cf
resource "aws_route53_record" "cf_s3" {
  zone_id = data.aws_route53_zone.web_voir.zone_id
  name    = "${local.domain_name_cf_s3}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.example.domain_name
    zone_id                = aws_cloudfront_distribution.example.hosted_zone_id
    evaluate_target_health = false
  }
}
