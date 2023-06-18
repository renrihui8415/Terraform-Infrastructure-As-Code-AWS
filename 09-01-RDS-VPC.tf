
#### VPC #####
# This file gathered all resources to build VPC for my website.
# It added 'RDS' part comparing to 08-01-ECS-VPC.tf.
#### VPC #####

#1 to create VPC
#2 to create private/public subnets under the VPC
  # 2.1 public subnets --> (NAT Gateway), ALB
    # Note: NAT gateway is not inexpensive, I won't use it in the project.
    # the file will just include NAT as templates
  # 2.2 private subnets --> ECS (fargate)
  # 2.3 private subnets --> RDS (mySql)
   # 2.3.1 to create private subnet in each AZ for RDS
   # 2.3.2 to create one subnet group including all private subnets
   # 2.3.3 later to attach this subnet group to RDS
#3 to create internet gateway and attach it to VPC
  #==============================================================
  # in this project the ECS farget task will be in private subnets
  # though there are practices to put ECS in the public subnets as well 
  # alb will be in public subnets
  # as we use farget, no worries to manage EC2 patching
  # an internet gateway makes sure services in public subnets can connect to internet
  # a nat gateway makes sure service in private subnets can connect to internet
  #==============================================================
  #3.1 to create internet gateway
  #3.2 to create route table for internet gateway
  #3.3 to associate public subnet(s) to route table
  #3.4 ! to assign public Ip so that EC2 can connect internet
    # as this project will apply ECS on fargate, 3.4 is just for reference
#4 to create NAT gateway
  #4.1 to create EIP(s), these EIP(s) are prepared for resources in private subnets
    # later these EIPs will be associated to NAT gateways
  #4.2 to create NAT gateway in public subnets for each AZ for high availability
  #4.3 to create "private" route tables for private subnets
    # the route tables will route traffic to NAT gateways
  #4.4 to associate private subnets to "private" route table
#5 to create security group for RDS(in another file)
#==============================================================

#1 below is to create vpc for the project:
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
#public subnet 1:  xxx.xx.10.0/24 in AZ-1a 
#public subnet 2:  xxx.xx.11.0/24 in AZ-1b 

# for fargate:
#private subnet 1: xxx.xx.30.0/24 in AZ-1a 
#private subnet 2: xxx.xx.31.0/24 in AZ-1b 

# for database:
#private subnet 1: xxx.xx.50.0/24 in AZ-1a 
#private subnet 2: xxx.xx.51.0/24 in AZ-1b 
#(private subnet 3: xxx.xx.52.0/24 in AZ-1d)
#============================================================
# to create public subnets first
# 
resource "aws_subnet" "public_subnets" {
  count = "${length(local.az_for_fargate)}"
  
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
#===========================================================
#2.3.1 to create private subnets for rds
# RDS in this project is enabled multi-az
# private subnets will be created in each AZ for RDS
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
#============================================================
# up until now, we have created 
# 2 public subnets --> nat gateway/internet gateway/alb
# 2 private subnets --> ecs(fargate)
# 3 private subnets --> database(mySql)
locals {
  # get all subnets 
  public_subnets=concat(aws_subnet.public_subnets[*].id)
  private_subnets=concat(aws_subnet.private_subnets_for_fargate[*].id)
  private_database_subnets=concat(aws_subnet.private_subnets_for_rds[*].id)
  all_private_subnets = concat(aws_subnet.private_subnets_for_fargate[*].id,aws_subnet.private_subnets_for_rds[*].id)
}
output "public_subnets" {
  value=local.public_subnets
}
output "private_subnets_fargate" {
  value=local.private_subnets
}
output "private_subnets_database" {
  value=local.private_database_subnets
}
#============================================================
# there is one more step: RDS requires a subnet group 
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
#3.1 below is to create internet gateway 
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.web_vpc.id}"

  tags = {
    Name = "${local.prefix}-igw"
  }
}
#============================================================
#3.2 below is to create route table for internet gateway
#when we create a VPC, a default route table will be created 
#the default route table will connect and route all subnets under this VPC automatically
#the default route table will route xxx.xx.0.0/16 --> local
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
  count = "${length(local.public_subnets)}"

  subnet_id      = "${element(aws_subnet.public_subnets.*.id, count.index)}"
  route_table_id = aws_route_table.router-igw.id
}

#===========================================================
#4 to create NAT gateway
#4.1 before creating NAT, eip(s) should be specified
# each AZ need one NAT gateway to connect to internet (for high available)
# we can reduce the cost by using less NAT gateways
# each NAT gateway need creating in one public subnet
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
# here, we create two NATs in two supporting AZs.
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
#============================================================
#4.3 below is to create a "private" route table for private subnets
   #this private route table is to connect nat gateway
   # the nat gateway is assigned with a public EIP

  #its different from the web-route,
  #which connects to internet gateway directly

# each private subnet has one route table
resource "aws_route_table" "nat_gateway" {
  count = length(local.private_subnets)
  vpc_id = "${aws_vpc.web_vpc.id}"
  tags = {
    Name="${local.prefix}-router-nat"
  }
}
#each route table associated with one nat gateway 
resource "aws_route" "nat_gateway" {
  count = length(local.private_subnets)
  route_table_id = element(aws_route_table.nat_gateway.*.id,count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = element(aws_nat_gateway.main.*.id, count.index)
}
#============================================================
#4.4 below is to associate private subnets to the private route table
resource "aws_route_table_association" "private_fargate" {
  count = length(local.private_subnets)
  subnet_id      = element(local.private_subnets.*, count.index)
  route_table_id = element(aws_route_table.nat_gateway.*.id, count.index)
}

# the above is to create for ECS;
# now to create 3 route tables for 3 private subnets for rds
# RDS won't need NAT gateways to access internet,
# RDS is fully managed by AWS
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
# Note: in development environment,
# we may need RDS publicly accessible
# make sure 
# aaa)RDS have a subnet group with public subnets
# the aws subnets become public when they are associated with route tables which are connected to internet gateway
# we can't apply NAT gateway for 2 reasons. RDS' public access doesnot go in this way. 
# NAT gateway is one way direction only.  
# bbb) RDS security group accept connection from your IP address (check "what is my IP" online)
# ccc) if the security group is created by us ,not by aws, there is no default outbound rule in the security group
# which means, the traffic coming from RDS can't reach us, do add or check the outbound rule in SG
# all traffic from RDS can go anywhere on the internet
# ddd) modify RDS, and set it as 'public accessible'
# eee) download/install a database tool online. build the connection using the parameters in RDS aws console.  
# The database tools are so many. MySql Workbench is recommended by AWS for MySql database. 
#===========================================================



