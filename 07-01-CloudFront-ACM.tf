# below is the complete process creating certificates/ Rout53 hosted zone/ Route53 records
# as dicussed in the file "05-Route53-(ALB).tf", 
# it depends if we choose terraform to build these or we manually build in the AWS console.

#1 to create cert for CloudFront with ACM
  #1.1 to create cert and choose validation with DNS 
  #1.2 to create R53 hosted zone for the domain name if necessary,
    # note !! to update the name servers of domain name according to the 
    #records in the hosted zone
  #1.3 to create R53 record under the hosted zone
  #1.4 to validate the cert
#2 to test the domain name 
#3 after the cloudfront is built, create r53 record for cloudfront
#=============================================================
#1.1 below is to set up cert for CloudFront
#Note: to use the provider in us-east-1
#because cloudfront requires us-east-1 only
/*
resource "aws_acm_certificate" "cloudfront" {
  provider                     = "here is the provider in us-east-1"
  domain_name                  = local.domain_name
  subject_alternative_names    = ["*.${local.domain_name}"]
  validation_method            = "DNS"

  tags = {
    Name        = "${local.prefix}-acm-cloudfront"
    Environment = "dev"
  }

  lifecycle {
    create_before_destroy = true
  }
}
*/
#1.2 to Create Hosted Zone for the domain name (public)
#public hosted zone faces the internet
#private hosted zone faces router within one enterprise
/*
resource "aws_route53_zone" "example" {
  name = "${local.domain_name}"
  force_destroy = true
  tags = {
    Environment = "dev"
    Name="${local.prefix}-r53-hostedzone"
  }
}
*/
#=============================================================
# to update domain's name servers with the newly created hosted zone
/*
resource "aws_route53domains_registered_domain" "update_domain_ns" {
  depends_on = [
    data.aws_route53_zone.example
  ]
  domain_name = "${local.domain_name}"

  dynamic "name_server" {
    for_each = toset(data.aws_route53_zone.example.name_servers)
    content {
      name = name_server.value
    }
  }
}
*/
#=============================================================
#1.3 to create r53 record
/*
resource "aws_route53_record" "cert_validation" {
  allow_overwrite = true
  name =  tolist(aws_acm_certificate.cloudfront.domain_validation_options)[0].resource_record_name
  records = [tolist(aws_acm_certificate.cloudfront.domain_validation_options)[0].resource_record_value]
  type = tolist(aws_acm_certificate.cloudfront.domain_validation_options)[0].resource_record_type
  zone_id = aws_route53_zone.example.zone_id
  ttl = 60
}
*/
#1.4 to validate the certificate
/*
resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = "here is the provider in us-east-1"
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}
*/
#2 to test the domain name on MAC
# $ dig here.is.your.domain.name 

#3 below is to create r53 record for cloudfront
# Note:
# to validate a cert might take seconds, minutes or hours even.
# better to create cert and hosted zone manually in console and using data source
# to find them
data "aws_acm_certificate" "issued" {
  domain   = "${local.domain_name}"
  statuses = ["ISSUED"]
  provider = "here is the provider in us-east-1"
}
data "aws_route53_zone" "example" {
  name         = "${local.domain_name}"
  private_zone = false
}

resource "aws_route53_record" "example" {
  zone_id = data.aws_route53_zone.example.zone_id
  name    = "${local.domain_name_cf}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.example.domain_name
    zone_id                = aws_cloudfront_distribution.example.hosted_zone_id
    evaluate_target_health = false
  }
}