#1 to create private subnets for RDS (mySql)
  # this project will apply RDS Multi-AZ and Read Replica
  # 1.1 this requires a RDS to be multi AZ instance 
  #(can be achieved by turn on the feature of "enable multi-AZ")
  # 1.2 to create private subnets in all AZs in the target region
    # Note: ECS (fargate) does not support all AZ
    # for example, in ca-central-1, it only supports 1a and 1b
    # As i wish to host my website in a specific region, 
    # and one of 3 AZs does not support fargate...
    # so for ECS: the project uses either NAT or VPC Endpoint for private fargate
    # AZ 1 <-- public subnet 1 <-- NAT gateway 1 <-- route table 1 <-- private subnets 1 <-- ECS
    # AZ 2 <-- public subnet 2 <-- NAT gateway 2 <-- route table 2 <-- private subnets 2 <-- ECS auto scaling
    # or,
    # AZ 1 <-- VPC Endpoints <-- route table 1 <-- private subnets 1 <-- ECS
    # AZ 2 <-- VPC Endpoints <-- route table 2 <-- private subnets 2 <-- ECS auto scaling
    
    # for RDS:
    # AZ 1 <-- route table 1 <-- private subnets 3 <-- master RDS
    # AZ 2 <-- route table 2 <-- private subnets 4 <-- read replica
    # AZ 3 <-- route table 3 <-- private subnets 5 <-- read replica

    # Note: 
    # NAT gateway and VPC Endpoints are not free. Needs to carefully weigh between cost and high availability

  # Note: applying "replica" means more coding efforts to direct traffic of reporting/read
  # to read replica

#2 to create SG for mySql
  # 2.1 to create sg for rds
  # 2.2 to set up SGs for rds and ecs for communication (RDS.tf file)
#3 to create RDS (mySql)
#4 to create replica
#============================================================
#2 below is to create sg for db
resource "aws_security_group" "rds" {
  name = "${local.prefix}-sg-rds"
  vpc_id = aws_vpc.web_vpc.id
  
  # to open port 3306 for all ip source is not recommended
  # if in the dev environment we wish RDS to be public accessible
  # add your own ip address for inbound rule 
  /* 
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    #cidr_blocks = [var.myownIP]
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  */
}
#============================================================
#3 below is to create RDS
resource "aws_db_instance" "mysql" {
  engine                  = local.mysql_rds_engine
  identifier              = local.mysql_instance_name
  storage_type            = local.mysql_storage_type
  allocated_storage       = local.mysql_rds_allocated_storage
  storage_encrypted       = local.mysql_storage_encrypted
  # in the prod environment, the data needs to be encrypted
  engine_version          = local.mysql_rds_engine_version
  instance_class          = local.mysql_instance_class
  
  # to allow rds to scale, there are two ways, the storage itself can be auto scaled vertically by:
  max_allocated_storage = local.mysql_max_allocated_storage
  # also, to scale using read replicas 
  # this is a "manual" scales, we need to set the parameters to build replica using terraform
  # apart from scaling, we can also use aws_db_proxy to maintain a pool of connections to rds
  # RDS Proxy requires no coding changes, just to point app to proxy endpoint instead of rds endpoint
  # Read replica needs to edit connection strings for each read replica in coding.

  # there is another feature of RDS, multi-az,
  # if it is true, the console will create a Standby RDS in its secondary AZ, 
  # however, this secondary AZ is not on unless primary RDS becomes unavailable.
  # it is for Disaster recovery
  multi_az                = local.mysql_multi_az
  #====================================================================
  db_name                 = local.mysql_database_name
  username                = local.mysql_rds_user_name
  # there will be no username and password in plain text in any circumstance
  # store a secret in Secrets Manager with username and password 
  # any other service who is calling rds API should have permissions for specific secret
  # in the secret manager to read and get username and password
  password                = local.mysql_rds_password
  #====================================================================
  parameter_group_name    = local.mysql_parameter_group
  vpc_security_group_ids  = local.mysql_sg_ids
  db_subnet_group_name    = local.mysql_subnet_group
  #====================================================================
  skip_final_snapshot     = local.mysql_skip_final_snapshot
  # if the above is false, means everytime rds is terraformly destroyed,
  # a final snapshot is made with below name
  #final_snapshot_identifier = "${local.prefix}-finalshot-mysql-${local.current_day}" 

  # and, if we decide to build rds based on last snapshot
  # we need to go to console , look for the latest snapshot and claify its id
  #snapshot_identifier = local.mysql_snapshot_id
  backup_retention_period = local.mysql_backup_retention_period
  maintenance_window              = local.mysql_maintenance_window
  backup_window                   = local.mysql_backup_window
  deletion_protection             = local.mysql_deletion_protection 
  enabled_cloudwatch_logs_exports = local.mysql_enabled_cloudwatch_logs_exports
 #====================================================================
  publicly_accessible     = local.mysql_publicly_accessible
  tags = {
    Name = local.mysql_instance_name
  }
}

locals {
  mysql_rds_engine              = "mysql"
  mysql_instance_name           = "${local.prefix}-mysql"
  mysql_rds_allocated_storage   = 20
  mysql_max_allocated_storage   = 50
  mysql_storage_type            = "gp2"
  mysql_rds_engine_version      = "8.0"
  mysql_instance_class          = "db.t3.micro"
  mysql_database_name           = "here is your database name, or more precisely, schema name in mysql"
  mysql_rds_user_name           = local.mysql-creds.username
  mysql_rds_password            = local.mysql-creds.password
  mysql_parameter_group         = "default.mysql5.7"
  mysql_sg_ids                  = ["${aws_security_group.rds.id}"]
  mysql_subnet_group            = aws_db_subnet_group.rds.name
  mysql_skip_final_snapshot     = true
  mysql_snapshot_id             = "here is the id"
  mysql_backup_retention_period = 10
  mysql_publicly_accessible     = false
  mysql_multi_az                = true
  mysql_storage_encrypted       = false
  mysql_maintenance_window      = "Mon:00:00-Mon:03:00"
  mysql_backup_window           = "03:00-06:00"
  mysql_enabled_cloudwatch_logs_exports = ["general"]
  mysql_deletion_protection     = false
}
/*
# below is to create read replica in another AZ
resource "aws_db_instance" "mysql-replica" {
  depends_on = [ 
    aws_db_instance.mysql
   ]
  replicate_source_db         = aws_db_instance.mysql.identifier
  #====================================================================
  identifier                  = "${aws_db_instance.mysql.identifier}-replica"
  instance_class              = local.mysql_instance_class
  engine                      = local.mysql_rds_engine
  engine_version              = local.mysql_rds_engine_version 
  parameter_group_name        = local.mysql_parameter_group
  #====================================================================
  # there will be no username and password in plain text in any circumstance
  # store a secret in Secrets Manager with username and password 
  # any other service who is calling rds API should have permissions for specific secret
  # in the secret manager to read and get username and password
  password                = local.mysql_rds_password
  #====================================================================
  multi_az                    = false 
  vpc_security_group_ids      = local.mysql_sg_ids
  #====================================================================
  skip_final_snapshot         = true
  storage_encrypted           = local.mysql_storage_encrypted
  auto_minor_version_upgrade  = true
  # the major version upgrade may cause app failure
  # the minor version upgrade for replicas first, then master
  # both upgrades have downtime, or you can choose your own time to update manually
  backup_retention_period     = 7
  maintenance_window              = local.mysql_maintenance_window
  backup_window                   = local.mysql_backup_window
  deletion_protection             = local.mysql_deletion_protection 
  enabled_cloudwatch_logs_exports = local.mysql_enabled_cloudwatch_logs_exports  
  #====================================================================
  tags = {
    Name = "${aws_db_instance.mysql.identifier}-replica"
  }
  timeouts {
    create = "3h"
    delete = "3h"
    update = "3h"
  }
}
*/