
#1 to create VPC

#2 to create private/public subnets under the VPC
  # 2.1 public subnets --> ALB
  # 2.2 private subnets --> ECS
  # 2.3 private subnets --> RDS
  # 2.4 public(or private) subnets --> EC2
   # 2.3.1 to create private subnet in each AZ for RDS
   # 2.3.2 to create one subnet group including all private subnets
   # 2.3.3 later to attach this subnet group to RDS
    # then the RDS can be connected from multi AZs through multi subnets

#3 to create internet gateway and attach it to VPC
  #(if resources in the VPC need internet connection)
  #3.1 to create internet gateway
  #3.2 to create route table for internet gateway
  #3.3 to associate public subnet(s) to route table
  #3.4 ! to assign public Ip so that EC2/ECS can connect internet
    # Internet Gateway alone is not enough for Internet connection

  #(if EC2/ECS in the VPC can't connect to the internet due to security reason)
  #==============================================================
  # EC2: 
    # to create AMI with necessary updates and installs
    # otherwise, the target group health check failed on EC2
    # as the health check is based on APP on EC2

    # for patching, to use patched AMI from Systems Manager
    # once AMI changes, it will trigger the instance refresh in ASG
    # to use NAT gateway is also an option, but needs to pay
  #==============================================================
  # ECS:
    # to deploy ECS in private subnets
    # If we use Fargate Type, no worries to manage EC2 patching
  #==============================================================
  # ALB:
    # ALB will be in public subnets
  #==============================================================

#4 to create NAT gateway
  #4.1 to create EIP(s), these EIP(s) are prepared for resources in private subnets
    # later these EIPs will be associated to NAT gateways
  #4.2 to create NAT gateway in public subnets for each AZ for high availability
  #4.3 to create (private) route tables for private subnets
    # the route tables will route traffic to NAT gateways
  #4.4 to associate private subnets to private route table

#5 to create security group 
  #5.1 to add inbound rules
  #5.2 to attach SG to target EC2/ECS(after EC2 is created)

#===========================================================
#1 below is to create VPC for the project:
resource "aws_vpc" "web-vpc" {
 cidr_block           = "${lookup(var.cidr_ab, var.environment)}.0.0/16"
 instance_tenancy     = "default"
 enable_dns_support   = true
 enable_dns_hostnames = true
tags = {
   Name = "${local.prefix}-vpc"
 }
}

#============================================================
#2 below is to create public/private subnets for each AZ
#the values of cidr and available zones can be 
#obtained from local variables dynamically
#subnet 1: xxx.xx.10.0/24 in 1a for t2
#subnet 2: xxx.xx.11.0/24 in 1b for t2
#subnet 3: xxx.xx.100.0/24 in 1c for t3
#============================================================
# 2.1 public subnets --> ALB

resource "aws_subnet" "public_subnets" {
  count = "${length(local.az_for_fargate)}"
  # the reason I choose AZs that support fargate is that 
  # not all AZs supporting Fargate
  # ALB from non-supporting AZ won't be able to direct requests to ECS at all
  vpc_id = "${aws_vpc.web_vpc.id}"
  cidr_block = "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_public_subnets+count.index}.0/24"
  availability_zone = "${local.az_for_fargate[count.index]}"
  #map_public_ip_on_launch = true
  tags ={
    Name = "${local.prefix}-Public"
  }
  depends_on = [
    aws_vpc.web_vpc
  ]
}
#============================================================
# 2.2 private subnets --> ECS
# to create private subnets for fargate
resource "aws_subnet" "private_subnets_for_fargate" {
  count = "${length(local.az_for_fargate)}"
  
  vpc_id = "${aws_vpc.web_vpc.id}"
  cidr_block = "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_private_subnets+count.index}.0/24"
  availability_zone = "${local.az_for_fargate[count.index]}"
  #map_public_ip_on_launch = true
  tags ={
    Name = "${local.prefix}-Private-fargate"
  }
  depends_on = [
    aws_vpc.web_vpc
  ]
}
#============================================================
# 2.3 private subnets --> RDS
# RDS in this project is enabled multi-az
# 2.3.1 private subnets will be created in each AZ for RDS
resource "aws_subnet" "private_subnets_for_rds" {
  count = "${length(local.availability_zones)}"
  
  vpc_id = "${aws_vpc.web_vpc.id}"
  cidr_block = "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_database_subnets+count.index}.0/24"
  availability_zone = "${local.availability_zones[count.index]}"
  #map_public_ip_on_launch = true
  tags ={
    Name = "${local.prefix}-Private-rds"
  }
  depends_on = [
    aws_vpc.web_vpc
  ]
}
# there is one more step: RDS(or AWS Data Warehouse -- Redshift) requires a subnet group 
# 2.3.2 below is to include those newly created subnets into one group:
# this group will be attached to RDS later
resource "aws_db_subnet_group" "rds" {
 name       = "${local.prefix}-subnetgroup-rds"
 subnet_ids = local.private_database_subnets
  tags = {
    environment = "dev"
    Name = "${local.prefix}-subnetgroup-rds"
 }
}
#============================================================
# 2.4 public(or private) subnets --> EC2
#(if we choose t2.micro as primary, then t3.micro as secondary)
# to create subnets for primary first
# EC2 is deployed in public/private subnets according to requirements
# below is just an example, in this project, ECS is applied
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
  # get all subnets for EC2
  all_subnets = concat(aws_subnet.public_subnets_for_primary[*].id,aws_subnet.public_subnets_for_secondary[*].id)
}
output "all_subnets" {
  value=local.all_subnets
}
#============================================================
# up until now, we have created 
# 2 public subnets --> later for nat gateway/internet gateway/alb
# 2 private subnets --> later for ecs(fargate)
# 3 private subnets --> later for database(mySql)
locals {
  # get all subnets 
  public_subnets=concat(aws_subnet.public_subnets[*].id)
  private_subnets=concat(aws_subnet.private_subnets_for_fargate[*].id)
  private_database_subnets=concat(aws_subnet.private_subnets_for_rds[*].id)
  all_private_subnets = concat(aws_subnet.private_subnets_for_fargate[*].id,aws_subnet.private_subnets_for_rds[*].id)
}
/*
output "public_subnets" {
  value=local.public_subnets
}

output "private_subnets_database" {
  value=local.private_database_subnets
}

output "private_subnets_fargate" {
  value=local.private_subnets
}
*/
#============================================================
#3.1 below is to create internet gateway for VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.web-vpc.id}"

  tags = {
    Name = "${local.prefix}-igw"
  }
}
#============================================================
#3.2 below is to create router for VPC
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
  #route {
    #ipv6_cidr_block        = "::/0"
    #egress_only_gateway_id = aws_egress_only_internet_gateway.example.id
  #}
  tags = {
    Name = "${local.prefix}-router-igw"
  }
}
#3.3 to associate the public subnets to the 2nd router for internet connection
resource "aws_route_table_association" "public-subnets-route-to-internet" {
  count = "${length(local.public_subnets)}"

  subnet_id      = "${element(aws_subnet.public_subnets.*.id, count.index)}"
  route_table_id = aws_route_table.router-igw.id
}
#===========================================================
#4 to create NAT gateway
# if we choose computation systems (lambda in the vpc, ec2, ecs) with private subnets
# we can use NAT for internet connection (or VPC Endpoints which will be discussed later with ECS)
# NAT gateway is charged by hour, it's wise to used it only when needed
# or we can compare the usage of NAT Gateway with VPC Endpoints and decide which to use according to cost
# in this project, I applied VPC Endpoints, below is just for reference
#4.1 before creating NAT, eip(s) should be specified
# each AZ need one NAT gateway to connect to internet
# each NAT gateway need creating in one public subnet
/* 
resource "aws_eip" "nat_gateway" {
  count=length(local.public_subnets)
  domain = "vpc"
  depends_on                = [
    aws_internet_gateway.igw
  ]
}
output "eip_for_private_subnets" {
  value = aws_eip.nat_gateway[*].public_ip
}
#4.2 below is to create one NAT gateway per AZ
# as ECS fargate does not support all AZ,
# here, we need to create
resource "aws_nat_gateway" "main" {
  count=length(local.public_subnets)
  allocation_id = element(aws_eip.nat_gateway.*.id, count.index)
  subnet_id     = element(local.public_subnets[*],count.index)
  #each public subnet has one NAT gateway

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.igw]
  tags = {
    Name="${local.prefix}-nat"
  }
}
*/
#============================================================
#4.3 below is to create a (private) route table for private subnets
   #this private route table is to connect nat gateway
   # the nat gateway is assigned with a public EIP

  #its different from the web-route,
  #which connects to internet gateway directly

# each private subnet has one route table

# resource "aws_route_table" "nat_gateway" {
#   count = length(local.private_subnets)
#   vpc_id = "${aws_vpc.web_vpc.id}"
#   tags = {
#     Name="${local.prefix}-router-nat"
#   }
# }

#each route table needs one nat gateway associated
# resource "aws_route" "nat_gateway" {
#   count = length(local.private_subnets)
#   route_table_id = element(aws_route_table.nat_gateway.*.id,count.index)
#   destination_cidr_block = "0.0.0.0/0"
#   nat_gateway_id = element(aws_nat_gateway.main.*.id, count.index)
# }

#============================================================
#4.4 below is to associate private subnets to the private route table
# For ECS:
resource "aws_route_table" "private_fargate" {
  count = length(local.private_subnets)
  vpc_id = "${aws_vpc.web_vpc.id}"
  tags = {
    Name="${local.prefix}-router-ecs"
  }
}
resource "aws_route_table_association" "private_fargate" {
  count = length(local.private_subnets)
  subnet_id      = element(local.private_subnets.*, count.index)
  route_table_id = element(aws_route_table.nat_gateway.*.id, count.index)
}

# For RDS:
# below is to create 3 route table for 3 private subnets for rds
resource "aws_route_table" "rds" {
  count = length(local.private_database_subnets)
  vpc_id = "${aws_vpc.web_vpc.id}"
  tags = {
    Name="${local.prefix}-router-rds"
  }
}
# below is to associate private subnets to the private route table
resource "aws_route_table_association" "private_rds" {
  count = length(local.private_database_subnets)
  subnet_id      = element(local.private_database_subnets.*, count.index)
  route_table_id = element(aws_route_table.rds.*.id, count.index)
}
# Note: 
# if we need RDS publicly accessible in development environment,
# please make sure 
# aaa)RDS has a subnet group with public subnets
# the aws subnets become public when they are associated with route tables which are connected to internet gateway
# we can't apply NAT gateway for 2 reasons. RDS' public access doesnot go in this way. 
# NAT gateway is one way direction only.  
# bbb) RDS security group accepts connection from your IP address (check "what is my IP" online)
# ccc) if the security group is created by us ,not by aws, there is no default outbound rule in the security group
# which means, the traffic coming from RDS can't reach us, do add or check the outbound rule in SG
# ddd) modify RDS, and set it as 'public accessible'
# eee) download/install a database tool online. build the connection using the parameters in RDS aws console.  
# The database tools are so many. MySql Workbench is recommended by AWS for MySql database. 
#===========================================================
#5 below is to create security group for EC2 (just as an example):
# before we create our own EC2/ASG, there is one more step to complete
# when we create VPC, a default ACL and a default SG are created
# ACL controls all inbound/outbound rules for the subnets
# SG controls all in/out rules for specific resource(s) within VPC
# the default ACL and SG allows 0.0.0.0/0 from and to anywhere in the internet
# this is not for production environment
# below is to create 2 SGs for EC2
#======================================================================
/*
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
# the inbound rule can't be added in ALB.tf file 

# to open port 443 for HTTPs
# if we only allow ALB to connect to EC2, there is no need for Port 443
# ALB will securely connect to EC2 in the target group by port 80
# below is just for testing
resource "aws_security_group_rule" "production_web_server" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.yourownIP]

  security_group_id =aws_security_group.ec2_security_group_public.id

}
*/
# Security Group Creation for ECS/ALB/Lambda will be shared in their respective .tf files.