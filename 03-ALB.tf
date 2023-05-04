#1 to create instance target group
#2 to create SG (security group) for ALB
#3 to create ALB
#4 to make sure the sg of EC2 allows request from ALB
#5 #!! be careful when to create cross zone ALB (mapping subnets)
#====================================================
#to create the target group for the ELB-->ALB
resource "aws_lb_target_group" "alb-web_ec2s" {
  name     = "${local.prefix}-target-group-alb"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.web-ec2.id
  #=========================================================
  #below comments can be skipped if the whole project won't be broken into smaller sections in future.
  #after you finish all files for all AWS resources in this website project
  #you may break the whole project into smaller sections 
  #like VPC, ALB, ASG... these sections are built in order.
  #in the 'variables' file in every smaller section, you would use locals to 
  #find the id from the previous section using the filter VPC tag:Name.
  #for example, the vpc_id can only be known after the terraform build it,
  #however, to build ALB in the next section, the vpc_id is needed.
  #fortunately, we are allowed to name the VPC when we build it.
  #so, to get the vpc_id, we use vpc_name to find the id.
  #=========================================================
  target_type           = "instance"
  lifecycle {
   create_before_destroy=true 
  }
  health_check {
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 10
    matcher             = "200"  #200 means success
  }
  tags = {
    "Name"              = "${local.prefix}-target-group-alb"
  }
}

# Before creating ALB, a SG Specially for ALB should be created
# as we only need the sg to open port 80.
# The sg for EC2 instance has more inbound rules than port 80,
# hence, not safe to share SG betwwen ALB and EC2.
resource "aws_security_group" "lb_sg" {
  name        = "${local.prefix}-securitygroup-alb"
  description = "intended for alb"
  vpc_id      = aws_vpc.web-ec2.id
  ingress {
    description      = "Traffic to ALB"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = [var.yourownIP]
    # for testing, only your own IP is accepted
    # reason: security
  }
  ingress {
    description      = "Traffic to ALB"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = [var.yourownIP]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    #for SG built by AWS, there's default outbound rule
    #for SG built by AWS users, need to add outbound rule
  }
  tags = {
    "Name"           = "${local.prefix}-securitygroup-alb"
  }
}

resource "aws_lb" "alb-web_ec2s" {
  name                = "${local.prefix}-alb"
  #================================
  internal            = false
  #internal           = true
  # if we wish to add NLB in front of ALB, ALB has to be internal,
  # the NLB will need EIP on each EC2 
  # (not the dynamic Public IP associated to EC2 during launch time)
  # if not with NLB, ALB should be internet-face
  #================================
  load_balancer_type          = "application"
  ip_address_type             = "ipv4"
  security_groups             = [aws_security_group.lb_sg.id]
  subnets                     = local.all_subnets
  enable_deletion_protection  = false
  lifecycle {
    create_before_destroy     = true
  }
  tags = {
    Environment      = "dev"
    Name             = "${local.prefix}-alb"
  }
}
#====================================================
output "DNS-name-alb" {
  value              = aws_lb.alb-web_ec2s.dns_name
}
#====================================================
# create 2 listeners for HTTP and HTTPS
# redirect HTTP to HTTPS within HTTP listener
resource "aws_lb_listener" "redirect_http_to_https" {
  load_balancer_arn = aws_lb.alb-web_ec2s.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type   = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
# in order to create a https listener on the alb
# you need to create a certificate using AWS certificate manager
# (or you can import cert as well )
# to create and validate certificate usually need time
# I would recommend to use AWS console to create/manage the cert
# below method using terraform is commented out
#resource "aws_acm_certificate" "here is the resource name" {
  #domain_name       = "here is your domain name"
  #validation_method = "DNS"

  #tags = {
    #Environment = "dev"
  #}

  #lifecycle {
    #create_before_destroy = true
  #}
#}
# the newly created certificate needs validation
#resource "aws_acm_certificate_validation" "here is the resource name" {
  #certificate_arn         = aws_acm_certificate.xxx.arn
#}
# however, the above way may take seconds or longer, it depends...

# after the cert is created, build a Route53 hosted zone with the domain name
# go back to ACM and create r53 record with the pending cert
# if we choose email validation for the cert, make sure to 
# disable the privacy service for the contact emails of your domain name
# otherwise, you won't receive the aws validation email.
# if we choose DNS validation, make sure to choose 'create R53 record' in ACM console
# !!! to make sure the ns(four name servers) in the domain 
# !!! are the same as those in hosted zone in current use
# every time a new hosted zone created by terraform apply, the name servers change..

# after we get cert ready to use:
# find the cert's arn
data "aws_acm_certificate" "issued" {
  domain   = "${local.domain_name}"
  statuses = ["ISSUED"]
}
resource "aws_lb_listener" "https" {
  load_balancer_arn  = aws_lb.alb-web_ec2s.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn = data.aws_acm_certificate.issued.arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-web_ec2s.arn
  }
  lifecycle {
    create_before_destroy = true
  }
}
# after the lb is created, a DNS name will be provided
# through the DNS, we can connect to the website later when 
# ASG is created successfully with ALB's target group

# we can add more rules for the listener
# eg.Weighted Forward action, Fixed-response action
#resource "aws_lb_listener_rule" "fixed_response_action" {
  #listener_arn = aws_lb_listener.https.arn

  #action {
    #type = "fixed-response"

    #fixed_response {
      #content_type = "text/plain"
      #message_body = "HEALTHY"
      #status_code  = "200"
    #}
  #}

  #condition {
    #query_string {
      #key   = "health"
      #value = "check"
    #}

    #query_string {
      #value = "bar"
    #}
  #}
#}

# below is to add inbound/outbound rules so that EC2 and ALB
# can communicate with each other
resource "aws_security_group_rule" "alb_to_ec2" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  #=====================================================
  #if we add alb in front of EC2,
  #we won't let EC2 to be reachable by HTTP 
  #but only via the load balancer
  source_security_group_id =aws_security_group.lb_sg.id
  #=====================================================
  security_group_id = local.ec2_security_group_id
  depends_on = [
    aws_security_group.lb_sg
  ]
}

#sg of ec2 and sg of alb should be bond as together
resource "aws_security_group_rule" "ec2_to_alb" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  #=====================================================
  source_security_group_id =local.ec2_security_group_id 
  #=====================================================
  security_group_id = aws_security_group.lb_sg.id
  depends_on = [
    local.ec2_security_group_id
  ]
}
resource "aws_security_group_rule" "ec2_out_alb" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  #=====================================================
  source_security_group_id =aws_security_group.lb_sg.id  
  #=====================================================
  security_group_id = local.ec2_security_group_id
  depends_on = [
    aws_security_group.lb_sg
  ]
}

resource "aws_security_group_rule" "alb_out_ec2" {
  type            = "egress"
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  source_security_group_id = local.ec2_security_group_id
  security_group_id = aws_security_group.lb_sg.id
  depends_on = [
    local.ec2_security_group_id
  ] 
}