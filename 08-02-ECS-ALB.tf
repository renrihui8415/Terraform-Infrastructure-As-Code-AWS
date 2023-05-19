#1 to create Target Group for ALB
#2 to create Security Group for ALB
  #2.1 to create SG for ALB
  #2.2 to bond SGs of ALB and ECS 
    # so that they allow connections to each other
#3 to create ALB
#4 to create listeners on ALB: 80 and 443
#5 to add Route53 record to allow requests to ALB with subdomain 
#6 to create Auto Scaling for ECS (in another file)
  #6.1 to auto scale by CPU
  #6.2 to auto scale by Memory
#============================================================
#1 below is to create target group for ALB
resource "aws_lb_target_group" "alb_ecs" {
  name        = "${local.prefix}-targetgroup"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  #Important: If your service's task definition uses the awsvpc network mode 
  #(required for the AWS Fargate launch type), 
  #you must choose IP as the target type. 
  #This is because tasks that use the awsvpc network mode are associated with an elastic network interface. 
  #These tasks aren't associated with an Amazon Elastic Compute Cloud (Amazon EC2) instance.
  vpc_id      = aws_vpc.web_vpc.id

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = local.tg_health_check_path
    unhealthy_threshold = "2"
  }

  tags = {
    Name        = "${local.prefix}-targetgroup"
    Environment = var.environment
  }
}
/*
One very important thing here is the attribute path within health_check. 
This is a route on the application that the Load Balancer will use 
to check the status of the application.
*/
#============================================================
#2.1 below is to create SG for ALB
# If we put cloudfront in front of ALB
# ALB should accept ips of CF only
# below is to get AWS managed prefix list for all cloudfront edge servers
# the list collects ip ranges of all cloudfront
# Using the ip_range.json downloaded from AWS website means we have to 
# update the ip ranges frequently, as the ip ranges for AWS cloudfront change with time.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  filter {
    name   = "prefix-list-name"
    values = ["com.amazonaws.global.cloudfront.origin-facing"]
  }
}

resource "aws_security_group" "alb" {
  name   = "${local.prefix}-sg-alb"
  description = "for alb-ecs"
  vpc_id = aws_vpc.web_vpc.id
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name        = "${local.prefix}-sg-alb"
    Environment = var.environment
  }
}
#Below is to open port 443 to cloudfront
#I use https between Cloudfront and ALB for security reason
#The "source" in security group is the id of cloudfront prefix list.
#Thanks to AWS, we don't need to add every single ip range of cloudfront worldwide
# and make too many security group rules....
resource "aws_security_group_rule" "cf_to_alb" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  #=====================================================
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  #=====================================================
  security_group_id = aws_security_group.alb.id
  depends_on = [
    aws_security_group.alb
  ]
}
#2.2 below is to add inbound/outbound rules so that ECS and ALB
# can communicate with each other
# port 80 is not safe , change to 443 in production environment with certificates for ECS
# I have concerns that resources in VPC can be attacked from outside.
# Someone may have different practices and apply port 80 between ALB and ECS.
# It did increase the burdon for ECS if it needs to encrypt/decode data.

resource "aws_security_group_rule" "ecs_to_alb" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  #=====================================================
  source_security_group_id =aws_security_group.ecs_service.id
  #=====================================================
  security_group_id = aws_security_group.alb.id
  depends_on = [
    aws_security_group.alb
  ]
}

resource "aws_security_group_rule" "alb_to_ecs" {
  type            = "ingress"
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id = aws_security_group.ecs_service.id
  depends_on = [
    aws_security_group.ecs_service
  ] 
}
#============================================================
#3 below is to create ALB
resource "aws_lb" "web_ecs" {
  name               = "${local.prefix}-alb-ecs"
  internal           = false
  load_balancer_type = "application"
  subnets            = local.public_subnets.*
  security_groups    = [aws_security_group.alb.id]

  enable_deletion_protection = false
  tags = {
    Name        = "${local.prefix}-alb-ecs"
    Environment = var.environment
  }
}
#============================================================
#4 below is to create listeners on ALB, 80 and 443
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_ecs.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "redirect"
    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }    
  }
}
data "aws_acm_certificate" "alb" {
  domain   = "${local.domain_name_alb}"
  statuses = ["ISSUED"]
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web_ecs.arn
  port              = 443
  protocol          = "HTTPS"
 
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.alb.arn

  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Request was not from Cloudfront."
      status_code  = "403"
    }
  }
  # default : all connection to alb is blocked 
  # unless the requests are from cloudfront
  # using custom headers
}

resource "aws_lb_listener_rule" "only_forward_from_cf" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_ecs.arn
  }
}
#============================================================
#5 to create Route53 record for ALB
# after the lb is created, a DNS name will be provided by AWS
# through the DNS, we can connect to the website
# But this DNS name provided for alb won't be used for internet users
# we will use a subdomain (like alb.your.domain.com) and create a record in r53
resource "aws_route53_record" "alb" {
  zone_id = data.aws_route53_zone.web_voir.zone_id
  name    = "${local.domain_name_alb}"
  type    = "A"
  #ttl is omitted as ttl will be 60 in this situation
  
  alias {
    name                   = aws_lb.web_ecs.dns_name
    zone_id                = aws_lb.web_ecs.zone_id
    evaluate_target_health = true
  }
}
# this subdomain will be used as cloudfront's origin domain name later
#============================================================










