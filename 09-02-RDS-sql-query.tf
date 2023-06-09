# after we build RDS cluster, the database is empty. 
# (unless the db is created based on a snapshot)
# This project uses stored procedures in mySql for data analysis
# These stored procedures will be created by terraform (actually, CLI)
# also, for Database management purpose, the sql queries for 
# creating users, grants priviledge to users, creating schemas, tables, etc
# can be created using terraform as well.

# the steps are:
# 1 to create local file (init.sql) for database initiation
# 2 to create local file (da.sql) for data analysis
# 3 to execute these SQL statements using CLI
# 4 to pack CLI commands within terraform codes
# there are online practices a lot:
# but very rarely they tell you:
# "Executing statements in your database via the AWS API "
# ONLY works (at this time) 
# if your database is an Aurora Serverless cluster with the Data API enabled."
# like the following:
/*
aws rds-data execute-statement \
--resource-arn arn:aws:rds:us-east-1:123456789012:cluster:mydbinstance \
--database mydatabase \
--secret-arn arn:aws:secretsmanager:us-east-1:123456789012:secret:mysecret \
--sql "source /path/to/myscript.sql"
*/

# so, if we use aurora, we are lucky as we can use "aws rds-data execute-statement"
# if we use datawarehouse (redshift): we are luckier as we can use "aws_redshift_data_statement"
  # this is a terraform resource, we don't need to integrate terraform with AWS CLI if we wish to run sql for redshift. 
  # the terraform resource itself is enough to include all sql scripts for the task. 
# here comes the "but". if we use rds (mysql), no aws CLI or Terraform supports
# us to execute any sql... 
# there is a work around. use mySql command line. it's not AWS CLI. its mySql's own command line. 
# the syntax is :
# $ mysql -u your_user_name -pyour_password -D your db name -h your_host.com -P default_3306 > your_file_path_of_.sql

# if we use this syntax, password is in plain text which is not recommended. 
# in order to avoid password in plain text, we omit the password part. 
# another problem comes: mysql command will prompt to get a password from us. 
# this time ,we type the password. it's safer, but it intervenes automation. 
# the solution to avoid any future password prompt is :
# aa) create a .my.conf file in home directory (not /etc/)
    # $ vim ~/.my.conf
    # copy/paste below 3 lines with your own username and password for mysql, not for aws
    /* 
    [mysql]
    user=your_own_user_name
    password=your_own_password
    */
    ####Attention####
    #there should not be any space or quote between the equal sign and your_own_user_name,
    # also,  there should not be any space or quote between the equal sign and your_own_password,
    # any space or quote after the equal sign (=) will be considered as part of username or password
# bb) change the mode and restrict its usage
    # $ chmod 600 ~/.my.conf
# cc) now to test command without -p and -u (-P is port:3306 by default)
# $ mysql -D your db name -h your_host.com > your_file_path_of_.sql
#     as we can see, mysql will retrieve the username and password in the conf file itself. 
# dd) create .sql file which includes all sql queries, stored procedures
     # the file of .sql will be shared in another of my github repository
# ee) put the mySql command into terraform null_resource module
# ff) the database set up will be automated. 

#### Reminder ####
# the above sql statement i mentioned is to set up mySql database to make it ready for data loading. 
# of course, we could achieve the same by installing database tool, connecting to mySql in the cloud,
# run sql queries in the tool to set up and maintain database. 
# but if we require a full automation, we need to find a way for terraform to complete it. 
# Also, rds needs to be public accessible to use MySql command line
# if we put rds in the private subnets, we can use ECS to init the DB.
# lambda can't be used as boto3 doesnot support to execute multiple SQL statements at one time
# as we know, Procedures are more than one line.
locals {
  filepath="${path.module}/sql_statement/init.sql"

}

resource "null_resource" "sql_statement" {
  #only execute sql statement when it changes
  triggers = {
    filepath=local.filepath
    #file = filesha1(local.filepath)
  }

  provisioner "local-exec" {
    command = <<-EOF
      mysql -h "$DB_HOST"  -D "$DB_NAME" < "$filepath"
    EOF
    environment = {
      DB_HOST     = replace(aws_db_instance.mysql.endpoint,":3306","")
      DB_NAME     = aws_db_instance.mysql.db_name
      filepath    = local.filepath
    }
    interpreter = ["bash", "-c"]
    
  }
}

