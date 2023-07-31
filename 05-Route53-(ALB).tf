# this file can be omitted if we choose to manually set up 
# the certicate and Route hosted zone
# to use terraform setup, means everytime we "terraform apply" or "terraform destroy"
# certificate/hosted zone change accordingly.
# it's not friendly for testing as the process takes time...

# Route53 provides DNS SERVICE
# route 53 will translate your domain name --> ip: like 54.3.18.30
# this ip will be returned from route 53 to browsers
# browers use this ip to connect to web server
# AWS provides alias, which means Route 53 can forward request to ALB's domain name 

#1 to register a domain (with AWS Route 53 or not)
#2 to setup Hosted Zone @ Route53
#3 to setup NS(Name Server) if we registered a domain name outside of AWS
# !! if registered domain with R53, need to update domain ns with new hosted zone
#4 to test the domain name in the terminal
#5 to create a record in the hosted zone
#=============================================================

#2 to Create Hosted Zone (public)
#public hosted zone faces the internet
#private hosted zone faces router within one enterprise
resource "aws_route53_zone" "example" {
  name = "${local.domain_name}"
  force_destroy = true
  tags = {
    Environment = "dev"
    Name="${local.prefix}-r53-hostedzone"
  }
}
#=============================================================
#3 to update domain's name servers with the newly created hosted zone
resource "aws_route53domains_registered_domain" "update_domain_ns" {
  depends_on = [
    aws_route53_zone.web-voir
  ]
  domain_name = aws_route53_zone.example.name

  dynamic "name_server" {
    for_each = toset(aws_route53_zone.example.name_servers)
    content {
      name = name_server.value
    }
  }
}
#=============================================================
#4 to test the domain name 
# $ dig your/domain/name @8.8.8.8
#=============================================================

#5 to create a record under a hosted zone
# when we create a record:
# there are various r53 policies to choose:
# simple routing, weighted, geolocation, latency, failover, Ip-based,Multivalue answer routing policy

#Note: 
# the Public IP associated to EC2 is changing constantly
# we need to apply for a fixed IP in the console of EIP
# and attached this fixed IP to EC2.
# as we use alb in this project, so we make r53 to route to ALB
# instead of EC2
resource "aws_route53_record" "example" {
  zone_id = aws_route53_zone.example.zone_id
  name="${local.domain_name}"
  type    = "A"
  # ttl is omitted as ttl will be 60 in this situation
  # the client side will cache the queried ip for 60 seconds
  # the more frequently we use R53 as a 'translator':)
  # the less the ttl is, and the more we need to pay. 
  # carefully set the ttl so that the DNS won't be queried too often
  alias {
    name                   = aws_lb.example.dns_name
    zone_id                = aws_lb.example.zone_id
    evaluate_target_health = true
  }
}
