# To apply cloudfront in front of ALB and ECS

# Cloudfront ----------------> S3
# Cloudfront --------> ALB --> ECS (Auto Scaling)

# In this project, 
# ECS only accept requests from ALB
  # who only accept requests from Cloudfront
    # who only accept requests by registered domain name

# when we use cloudfront in front of EC2, ECS or ALB,
# we need them to be public!
# this is different when we use s3 as cf origin where s3 can be private

#1 below is to create Cloudfront distribution for ALB.
# creating Cloudfront distribution :
# Note: the domain_name for alb must be the same as the certificate for alb's https listener
# if we choose alb's domain name in the cloudfront console (like 12345.amazonaws.com)
# the browser will generate risk warnings telling us cloudfront is connecting a risky alb
# To solve the problem, we need to create certificate for the alb's domain name (like 12345.amazonaws.com)
# however, the domain name ending with .amazonaws.com can't be a valid domain name for ACM
# So you need to create a subdomain name for alb using your own domain name, like alb.example.com
# and create the cert and add to https listener

resource "aws_cloudfront_distribution" "alb" {
  origin {
    domain_name = local.domain_name_alb
    origin_id   = local.domain_name_alb
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
    # in order that alb only accept cloudfront
    # we need to add headers to requests from cloudfront
    custom_header {
      name     = "${local.cf_custom_header}"
      value    = "${local.cf_custom_header_value}"
    }
  }

  enabled             = true
  aliases             = [local.domain_name_cf]
  
  # this alternate domain name or CNAME is a must
  # when we wish to use R53 to provide service for example.com, or
  # *.example.com.
  # meanwhile create a R53 record to let r53 to route request to cloudfront
  # the aliases in cloudfront should be the same as record name in r53
  # if we set "*.example.com", then, all url like ab.example.com,
  # www.example.com will all get to cloudfront and then backend origin
  web_acl_id = aws_wafv2_web_acl.example.arn
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = local.domain_name_alb
    viewer_protocol_policy = "redirect-to-https"
      forwarded_values {
        query_string = false

      cookies {
        forward = "none"
      }
    }
  }
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = local.geo_restriction
    }
  }
  tags = {
    Name                     = "${local.prefix}-cloudfront-alb"
    Environment              = "Dev"
  }
  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.cf.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }

}
output "cloudfront_domain_name_for_alb" {
  value = aws_cloudfront_distribution.alb.domain_name
}
# to create a r53 record for cf
resource "aws_route53_record" "cf_alb" {
  zone_id = data.aws_route53_zone.example.zone_id
  name    = "${local.domain_name_cf}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.alb.domain_name
    zone_id                = aws_cloudfront_distribution.alb.hosted_zone_id
    evaluate_target_health = false
  }
}


