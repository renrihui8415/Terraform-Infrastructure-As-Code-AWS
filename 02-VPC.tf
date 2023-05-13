
#1 to create VPC
#2 to create subnets under the VPC
#3 (if we need EC2s have internet connection)
  #to create internet gateway and attach it to VPC

  # if not, we'd better create AMI with necessary updates and installs
      # otherwise, the target group health check failed on EC2
      # as the health check is based on APP on EC2

      # for patching, to use patched AMI from Systems Manager
      # once AMI changes, it will trigger the instance refresh in ASG
      # to use NAT gateway is also an option, but needs to pay

#4 to create router
  #4.1 to route to internet gateway
  #4.2 to associate subnet(s) to router
  #4.3 ! to assign public Ip so that EC2 can visit internet
       # internet gateway is not enough for internet connection!!
#5 to create security group 
  #5.1 to add inbound rules
  #5.2 to attach SG to target EC2(after EC2 is created)
#6 !!(question) if ACL is created before VPC is fully ready
  # the terraform-apply will have a bug telling subnets confliction?

#===========================================================
#1 below is to create VPC for ec2:
resource "aws_vpc" "web-ec2" {
 cidr_block           = "${lookup(var.cidr_ab, var.environment)}.0.0/16"
 instance_tenancy     = "default"
 enable_dns_support   = true
 enable_dns_hostnames = true
tags = {
   Name = "${local.prefix}-ec2"
 }
}

#============================================================
#2 below is to create subnets 
#the values of cidr and available zones can be 
#obtained from local variables dynamically
#subnet 1: xxx.xx.10.0/24 in 1a for t2
#subnet 2: xxx.xx.11.0/24 in 1b for t2
#subnet 3: xxx.xx.100.0/24 in 1c for t3
#============================================================
# to create subnets for t2 first
resource "aws_subnet" "public_subnets_for_primary" {
  count = "${length(data.aws_ec2_instance_type_offerings.primary-instance.locations)}"
  
  vpc_id = "${aws_vpc.web-ec2.id}"
  cidr_block = "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_public_subnets+count.index}.0/24"
  availability_zone = "${data.aws_ec2_instance_type_offerings.primary-instance.locations[count.index]}"
  #map_public_ip_on_launch = true
  tags ={
    Name = "${local.prefix}-PublicSubnets-forprimary"
  }
  depends_on = [
    aws_vpc.web-ec2
  ]
}
# next is to create subnets for t3
resource "aws_subnet" "public_subnets_for_secondary" {
  count = "${length(local.az_that_support_t3_only)}"
  
  vpc_id = "${aws_vpc.web-ec2.id}"
  cidr_block = "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_public_subnets_2+count.index}.0/24"
  availability_zone = "${local.az_that_support_t3_only[count.index]}"
  #map_public_ip_on_launch = true
  tags ={
    Name = "${local.prefix}-PublicSubnets-forsecondary"
  }

  depends_on = [
    aws_vpc.web-ec2
  ]
}
locals {
  # get all subnets 
  all_subnets = concat(aws_subnet.public_subnets_for_primary[*].id,aws_subnet.public_subnets_for_secondary[*].id)
}
output "all_subnets" {
  value=local.all_subnets
}
#============================================================
#3 below is to create internet gateway for VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.web-ec2.id}"

  tags = {
    Name = "${local.prefix}-igw-ec2"
  }
}
#============================================================
#4 below is to create router for VPC
#when we create a VPC, a default router will be created 
#the default router will connect and route all subnets under this VPC automatically
#the default router will route xxx.xx.0.0/16 --> local
#============================================================
# we need to create a 2nd router so that 0.0.0.0/0 --> internet gateway
resource "aws_route_table" "router-igw" {
  vpc_id = "${aws_vpc.web-ec2.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.prefix}-router-igw-ec2"
  }
}
#to associate the public subnets to the 2nd router for internet connection
resource "aws_route_table_association" "public-subnets-route-to-internet" {
  count = "${length(data.aws_ec2_instance_type_offerings.primary-instance.locations)}"

  subnet_id      = "${element(aws_subnet.public_subnets_for_primary.*.id, count.index)}"
  route_table_id = aws_route_table.router-igw.id
}
resource "aws_route_table_association" "public-subnets-route-to-internet-2" {
  count = "${length(aws_subnet.public_subnets_for_secondary)}"

  subnet_id      = "${element(aws_subnet.public_subnets_for_secondary.*.id, count.index)}"
  route_table_id = aws_route_table.router-igw.id
}
#===========================================================
#5 below is to create security group for ec2:
# before we create our own EC2/ASG, there is one more step to complete
# when we create VPC, a default ACL and a default SG are created
# ACL controls all inbound/outbound rules for the subnets
# SG controls all in/out rules for specific resource(s) within VPC
# the default ACL and SG allows 0.0.0.0/0 from and to anywhere in the internet
# this is not for production environment
# below is to create 2 SGs for EC2
#======================================================================
#the default SG will only maintain for SSH access
resource "aws_default_security_group" "ec2_security_group_ssh" {
 vpc_id     = "${aws_vpc.web-ec2.id}"
  
  lifecycle {
    create_before_destroy = true
  }
tags = {
   Name = "${local.prefix}-securitygroup-ec2-ssh"
 }
depends_on = [
   aws_vpc.web-ec2
 ]
}
# to add port 22 into SG
resource "aws_security_group_rule" "inbound-rules-22" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       =[var.myownIP]

  security_group_id = aws_default_security_group.ec2_security_group_ssh.id
}

#other inbound/outbound rules will be added in another SG 
resource "aws_security_group" "ec2_security_group_public" {
  vpc_id      = "${aws_vpc.web-ec2.id}"
  name        = "${local.prefix}-securitygroup-ec2-public"
  description = "Allow connection to public EC2s"
  lifecycle {
    create_before_destroy = true
  }
tags = {
   Name = "${local.prefix}-securitygroup-ec2-public"
 }
depends_on = [
   aws_vpc.web-ec2
 ]
}

resource "aws_security_group_rule" "outbound-rules" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       =["0.0.0.0/0"]

  security_group_id = aws_security_group.ec2_security_group_public.id
}
# to open port 80 for HTTP for ALB only
# the inbound rule will be done in the next .tf file 

# to open port 443 for HTTPs
#if we only allow ALB to connect to EC2, there is no need for Port 443
# ALB will securely connect to EC2 in the target group by port 80
#below is just for testing
resource "aws_security_group_rule" "production_web_server" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.yourownIP]

  security_group_id =aws_security_group.ec2_security_group_public.id

}
