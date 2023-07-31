#### VPC for ECS ####
# This file is to set up VPC for ECS

#1 to create VPC
#2 to create private/public subnets under the VPC
  # public subnets --> ALB
  # private subnets --> ECS
#3 to create internet gateway and attach it to VPC
  #==============================================================
  # in this project the ECS farget task will be in private subnets
  # there are practices to put ECS in the public subnets as well 
  # AWS proposed two methods to build ECS (in public or private subnets) in its
  # best-practice guide.

  # I prefer to put ECS in private subnets for security.
  # ALB will be in public subnets

  # an internet gateway makes sure services (ALB) in public subnets can connect to internet,
  # VPC Endpoints, other than NAT Gateway, are applied for ECS to connect other AWS public Services
  #==============================================================
  #3.1 to create internet gateway
  #3.2 to create route table for internet gateway
  #3.3 to associate public subnet(s) to route table
#4 to create NAT gateway (optional)
  #4.1 to create EIP(s), these EIP(s) are prepared for resources in private subnets
    # later these EIPs will be associated to NAT gateways
  #4.2 to create NAT gateway in public subnets
  #4.3 to create (private) route tables for private subnets
    # the route tables will route traffic to NAT gateways
  #4.4 to associate private subnets to private route table
#5 to create security group for ECS
  #5.1 to add inbound rules
    # as we apply ALB in front of ECS, two SGs will communicate with each other 
    # in Port:80 (Port:443 for production)
  #5.2 to attach SG to ECS

#1 Below is to create VPC for ECS:
resource "aws_vpc" "web_vpc" {
 cidr_block       = "${lookup(var.cidr_ab, var.environment)}.0.0/16"
 instance_tenancy = "default"
 enable_dns_support=true
 enable_dns_hostnames=true
tags = {
   Name = "${local.prefix}-vpc"
 }
}
#============================================================
#2 below is to create public/private subnets for each AZ
#the values of cidr and available zones can be 
#obtained from local variables dynamically
#public subnet 1:  xxx.xx.10.0/24  
#public subnet 2:  xxx.xx.11.0/24  

#private subnet 1: xxx.xx.30.0/24  
#private subnet 2: xxx.xx.31.0/24

#============================================================
# to create public subnets for ALB first
# Fargate is not supported for all AZs in AWS
# Public subnets for ALB will be created in those AZs that support Fargate
resource "aws_subnet" "public_subnets_for_fargate" {
  count = "${length(local.az_for_fargate)}"
  
  vpc_id = "${aws_vpc.web_vpc.id}"
  cidr_block = "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_public_subnets+count.index}.0/24"
  availability_zone = "${local.az_for_fargate[count.index]}"

  tags ={
    Name = "${local.prefix}-PublicSubnets-for-fargate"
  }
  depends_on = [
    aws_vpc.web_vpc
  ]
}

# to create private subnets for fargate
resource "aws_subnet" "private_subnets_for_fargate" {
  count = "${length(local.az_for_fargate)}"
  
  vpc_id = "${aws_vpc.web_vpc.id}"
  cidr_block = "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_private_subnets+count.index}.0/24"
  availability_zone = "${local.az_for_fargate[count.index]}"

  tags ={
    Name = "${local.prefix}-PrivateSubnets-for-fargate"
  }
  depends_on = [
    aws_vpc.web_vpc
  ]
}
#============================================================
# Up until now, we have created public and private subnets for target AZs
locals {
  # get all subnets 
  public_subnets=concat(aws_subnet.public_subnets_for_fargate[*].id)
  private_subnets=concat(aws_subnet.private_subnets_for_fargate[*].id)
  all_subnets = concat(aws_subnet.public_subnets_for_fargate[*].id,aws_subnet.private_subnets_for_fargate[*].id)
}
#output "all_subnets" {
  #value=local.all_subnets
#}
#============================================================
#3.1 below is to create internet gateway 
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.web_vpc.id}"

  tags = {
    Name = "${local.prefix}-igw"
  }
}
#============================================================
#3.2 below is to create router for internet gateway
#when we create a VPC, a default router will be created 
#the default router will connect and route all subnets under this VPC automatically
#the default router will route xxx.xx.0.0/16 --> local
#============================================================
# we need to create a 2nd router so that 0.0.0.0/0 --> internet gateway
resource "aws_route_table" "router-igw" {
  vpc_id = "${aws_vpc.web_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.prefix}-router-igw"
  }
}
#3.3 to associate the public subnets to the 2nd router for internet connection
resource "aws_route_table_association" "public-subnets-route-to-internet" {
  count = "${length(local.az_for_fargate)}"

  subnet_id      = "${element(aws_subnet.public_subnets_for_fargate.*.id, count.index)}"
  route_table_id = aws_route_table.router-igw.id
}
#===========================================================
#4 to create NAT gateway
# below about NAT Gateway is just for reference
#4.1 before creating NAT, EIP(s) should be specified
# each private subnet need one NAT gateway to connect internet
# each NAT gateway need creating in one public subnet

# resource "aws_eip" "nat_gateway" {
#   count=length(local.private_subnets)
#   vpc = true
#   depends_on                = [
#     aws_internet_gateway.igw
#   ]
# }
# output "eip_for_private_subnets" {
#   value = aws_eip.nat_gateway[*].public_ip
# }
# #4.2 below is to create NAT gateway
# resource "aws_nat_gateway" "main" {
#   count=length(local.private_subnets)
#   allocation_id = element(aws_eip.nat_gateway.*.id, count.index)
#   subnet_id     = element(local.public_subnets[*],count.index)
#   #each public subnet has one NAT gateway

#   # To ensure proper ordering, it is recommended to add an explicit dependency
#   # on the Internet Gateway for the VPC.
#   depends_on = [aws_internet_gateway.igw]
#   tags = {
#     Name="${local.prefix}-nat"
#   }
# }
# #============================================================
# #4.3 below is to create a (private) route table for private subnets
#    # this private route table is to connect nat gateway
#    # the nat gateway is assigned with a public EIP

#   # it's different from the web route,
#   # which connects to internet gateway directly
# 
# # each private subnet needs one route table
# resource "aws_route_table" "nat_gateway" {
#   count = length(local.private_subnets)
#   vpc_id = "${aws_vpc.web_vpc.id}"
#   tags = {
#     Name="${local.prefix}-router-nat"
#   }
# }
# #each route table needs one nat gateway
# resource "aws_route" "nat_gateway" {
#   count = length(local.private_subnets)
#   route_table_id = element(aws_route_table.nat_gateway.*.id,count.index)
#   destination_cidr_block = "0.0.0.0/0"
#   nat_gateway_id = element(aws_nat_gateway.main.*.id, count.index)
# }
#============================================================
#4.4 below is to associate private subnets to the private route table
resource "aws_route_table" "fargate" {
  count = length(local.private_subnets)
  vpc_id = "${aws_vpc.web_vpc.id}"
  tags = {
    Name="${local.prefix}-router-fargate"
  }
}
resource "aws_route_table_association" "private" {
  count = length(local.private_subnets)
  subnet_id      = element(local.private_subnets.*, count.index)
  route_table_id = element(aws_route_table.fargate.*.id, count.index)
}
#===========================================================
#5 below is to create security group for ECS:
# when we create VPC, a default ACL and a default SG are created
# ACL controls all inbound/outbound rules for the VPC
# SG controls all in/out rules for specific resource(s) within VPC
# the default ACL and SG allows 0.0.0.0/0 from and to anywhere in the internet
# this is not secure
# below is to create SG for ECS
#======================================================================
# about the inbound rules for SG:
# although ALB and ECS are in the VPC
# there is possibility that resources can be attacked 
# if the traffic among ALB and ECS is through port 80.
# So I decided to use port 443 later for production.
# If port 443 is applied, the coming problem is the CPU usage. 
# If the requests are in high volumn, the servers are busy with
# decryption/encryption. I will increase vCPU count to solve the problem.
# Security always comes at first.

resource "aws_security_group" "ecs_service" {
  name   = "${local.prefix}-sg-ecs-service"
  vpc_id = aws_vpc.web_vpc.id
 
  egress {
   protocol         = "-1"
   from_port        = 0
   to_port          = 0
   cidr_blocks      = ["0.0.0.0/0"]
   ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name="${local.prefix}-sg-ecs-service"
  }
}
