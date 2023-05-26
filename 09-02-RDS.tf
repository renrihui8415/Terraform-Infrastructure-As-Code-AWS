#1 to create private subnets for RDS (mySql)
  # 1.1 this project will apply master rds with read replicas in across AZs
  # 1.2 to create private subnets in all AZs in the target region
    # Note: ECS (fargate) does not support all AZ
    # when i wish to host my website in a specific AWS region, 
    # i found one of 3 AZs does not support fargate...
    # so for ECS:
    # AZ 1 <-- public subnet 1 <-- NAT gateway 1 <-- route table 1 <-- private subnets 1 <-- ECS
    # AZ 2 <-- public subnet 2 <-- NAT gateway 2 <-- route table 2 <-- private subnets 2 <-- ECS auto scaling

    # for RDS(if any):
    # AZ 1 <-- public subnet 1 <-- NAT gateway 1 <-- route table 1 <-- private subnets 3 <-- master RDS
    # AZ 2 <-- public subnet 2 <-- NAT gateway 2 <-- route table 2 <-- private subnets 4 <-- read replica
    # AZ 3 <-- public subnet 3 <-- NAT gateway 3 <-- route table 3 <-- private subnets 5 <-- read replica

    # to combine both into one:
    # AZ 1 <-- public subnet 1 <-- NAT gateway 1 <-- route table 1 <-- private subnets 1 <-- ECS              <-- route table 3 <-- private subnets 1   <-- subnet group 1 <-- RDS
    # AZ 2 <-- public subnet 2 <-- NAT gateway 2 <-- route table 2 <-- private subnets 2 <-- ECS auto scaling <-- route table 4,5 <-- private subnets 2,3 <-- subnet group 1 <-- RDS

    # Note: 
    # NAT gateway is not free. Needs to carefully weigh between cost and high availability

  # Note: applying "read replica" means more coding efforts to direct traffic of reporting/read
  # to read replicas

#2 to create SG for mySql
#3 to create RDS (mySql)


#2 below is to create sg for db
resource "aws_security_group" "rds" {
  name = "${local.prefix}-sg-rds"
  vpc_id = aws_vpc.web_vpc.id
  /*
  # to open port 3306 for all ip source is not recommended
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  */
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#allow access only between ecs and rds
resource "aws_security_group_rule" "ecs_to_rds" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  #=====================================================
  #limit the access to rds 
  source_security_group_id =aws_security_group.ecs_service.id
  #=====================================================
  security_group_id = aws_security_group.rds.id
  depends_on = [
    aws_security_group.rds
  ]
}
resource "aws_security_group_rule" "rds_to_ecs" {
  type            = "ingress"
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  source_security_group_id = aws_security_group.rds.id

  security_group_id = aws_security_group.ecs_service.id
  depends_on = [
    aws_security_group.ecs_service
  ]
}

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
  # this is a "manual" scaling, we need to set the parameters to build replica using terraform or AWS console
  # apart from scaling, we can also use aws_db_proxy to maintain a pool of connections to rds
  # RDS Proxy requires no coding changes, just to point app to proxy endpoint instead of rds endpoint
  # Read replica needs to edit connection strings for each read replica in coding.
  # Note: RDS Proxy is not free to use.

  # there is another feature of RDS: multi-az,
  # if it is true, the console will show its secondary AZ after the RDS is built successfully.
  # however, this secondary AZ is not on unless primary RDS becomes unavailable.
  # it is for Disaster recovery
  multi_az                = local.mysql_multi_az
  #====================================================================
  db_name                 = local.mysql_database_name
  username                = local.mysql_rds_user_name
  #### #Attention!!! ####
  # there will be no username and password in plain text in coding in any circumstance
  # store a secret in Secrets Manager with username and password 
  # any other service who is calling rds API should have permissions to read this specific secret
  # in the secret manager 
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

  # and, if we decide to build rds based on the latest final snapshot
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
output "mysql_endpoint" {
  value = aws_db_instance.mysql.endpoint
}

locals {
  mysql_rds_engine              = "mysql"
  mysql_instance_name           = "${local.prefix}-rds-mysql"
  mysql_rds_allocated_storage   = 20
  mysql_max_allocated_storage   = 50
  mysql_storage_type            = "gp2"
  mysql_rds_engine_version      = "5.7"
  mysql_instance_class          = "db.t2.micro"
  mysql_database_name           = "here is the name of your database"
  mysql_rds_user_name           = local.mysql-creds.username
  # terraform will read the secret from secrets manager
  # make sure you have permissions to secrets manager as well
  # otherwise your terraform codes won't be able to get the username/passwor required to build the db
  # ATTENTION!#
  # terraform has a state file which records everything in plain text...including the password 
  # make sure to encrypt the file by establishing a backend s3 bucket in the AWS cloud
  # the s3 provides encryption by default, use a combination of s3 and dynamo table to keep 
  # the terraform state file safe.
  # meanwhile, restrict access to the s3 and dynamo table in IAM console
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

# below is to create read replica in another AZ
# AWS will deploy the read replica in another AZ if the master rds is multi-az

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
  password                = local.mysql_rds_password
  #====================================================================
  multi_az                    = false 
  vpc_security_group_ids      = local.mysql_sg_ids
  #====================================================================
  skip_final_snapshot         = true
  storage_encrypted           = local.mysql_storage_encrypted
  auto_minor_version_upgrade  = true
  # the major version upgrade may cause app failure
  # the minor version upgrade for all replicas before update for a master
  # both upgrades have downtime
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
