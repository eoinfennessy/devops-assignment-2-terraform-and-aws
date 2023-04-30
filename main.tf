provider "aws" {
  region = local.region
}

locals {
  name_prefix      = "ef"
  tags             = { Project = "devops-assignment-2" }
  region           = "us-east-1"
  db_name          = "messageboard"
  bastion_host_ami = "ami-02396cdd13e9a1257"
  web_app_ami      = "ami-085c6593eece083cb"
  user_data        = <<EOT
    #!/bin/bash
    export DB_URL=${module.db.db_instance_endpoint}
    export DB_NAME=${local.db_name}
    export DB_PASSWORD=${var.db_password}
    export DB_USER=${var.db_user}

    export AWS_RAW_BUCKET_NAME=${module.s3_bucket_raw.s3_bucket_id}
    export AWS_PROCESSED_BUCKET_NAME=${module.s3_bucket_processed.s3_bucket_id}

    cd /home/ec2-user/app
    source env/bin/activate
    uvicorn src.main:app --host 0.0.0.0 --port 80
  EOT
  lab_role = {
    role_arn             = "arn:aws:iam::004768635109:role/LabRole"
    instance_profile_arn = "arn:aws:iam::004768635109:instance-profile/LabInstanceProfile"
  }
}

# VPC ##########################################################################

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${local.name_prefix}-vpc"

  cidr            = "10.0.0.0/16"
  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = local.tags
}

# Security Groups ##############################################################

module "all_egress_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name               = "all-egress"
  description        = "Allow all egress"
  vpc_id             = module.vpc.vpc_id
  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules       = ["all-all"]

  tags = local.tags
}

module "http_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name                = "http"
  description         = "Allow all HTTP ingress"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp"]

  tags = local.tags
}

data "http" "my_ip" {
  url = "https://ifconfig.me/ip"
}

module "ssh_from_my_ip_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name                = "ssh-from-my-ip"
  description         = "Allows SSH ingress from IP address running Terraform script"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = ["${data.http.my_ip.response_body}/32"]
  # ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules = ["ssh-tcp"]

  tags = local.tags
}

module "postgresql_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name                = "postgresql"
  vpc_id              = module.vpc.vpc_id
  description         = "Allows PostgreSQL ingress on port 5432"
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["postgresql-tcp"]

  tags = local.tags
}

module "ssh_from_bastion_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name                = "ssh-from-bastion"
  description         = "Allows SSH ingress from bastion host only"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = ["${module.bastion_host.private_ip}/32"]
  ingress_rules = ["ssh-tcp"]

  tags = local.tags
}

# Key Pair #####################################################################

module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"

  key_name           = "${local.name_prefix}-key"
  create_private_key = true

  tags = local.tags
}

resource "local_file" "private_key" {
  content         = module.key_pair.private_key_pem
  filename        = "${module.key_pair.key_pair_name}.pem"
  file_permission = 600
}

# Bastion Host #################################################################

module "bastion_host" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name                        = "${local.name_prefix}-bastion-host"
  ami                         = local.bastion_host_ami
  instance_type               = "t2.nano"
  key_name                    = module.key_pair.key_pair_name
  vpc_security_group_ids      = [module.ssh_from_my_ip_sg.security_group_id, module.all_egress_sg.security_group_id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true

  tags = local.tags
}

# Load Balancer and Auto-Scaling Group #########################################

module "alb" {
  source = "terraform-aws-modules/alb/aws"

  name                  = "${local.name_prefix}-alb"
  load_balancer_type    = "application"
  vpc_id                = module.vpc.vpc_id
  subnets               = module.vpc.public_subnets
  create_security_group = false
  security_groups       = [module.http_sg.security_group_id, module.all_egress_sg.security_group_id]

  target_groups = [
    {
      name_prefix      = "${local.name_prefix}-tg-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
  ]
  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]
  tags = local.tags
}

module "auto_scaling_group" {
  source = "terraform-aws-modules/autoscaling/aws"

  name                      = "${local.name_prefix}-asg-fastapi-app"
  vpc_zone_identifier       = module.vpc.private_subnets
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  target_group_arns         = module.alb.target_group_arns
  health_check_grace_period = 30

  # Launch template
  launch_template_name        = "${local.name_prefix}-launch-template"
  launch_template_description = "Launch template for FastAPI app"
  launch_template_version     = "$Latest"
  image_id                    = local.web_app_ami
  instance_type               = "t2.nano"
  key_name                    = module.key_pair.key_pair_name
  security_groups = [
    module.ssh_from_bastion_sg.security_group_id,
    module.http_sg.security_group_id,
    module.all_egress_sg.security_group_id
  ]
  create_iam_instance_profile = false
  iam_instance_profile_arn    = local.lab_role.instance_profile_arn
  enable_monitoring           = true
  user_data                   = base64encode(local.user_data)

  # auto-scaling policies
  scaling_policies = {
    scale-out-on-high-cpu = {
      policy_type        = "SimpleScaling"
      adjustment_type    = "ChangeInCapacity"
      scaling_adjustment = 1
      cooldown           = 300
    },
    scale-in-on-low-cpu = {
      policy_type        = "SimpleScaling"
      adjustment_type    = "ChangeInCapacity"
      scaling_adjustment = -1
      cooldown           = 300
    }
  }
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "High CPU Alarm"
  alarm_description   = "Monitors CPU and triggers alarm on high CPU"
  alarm_actions       = [module.auto_scaling_group.autoscaling_policy_arns["scale-out-on-high-cpu"]]
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 70
  datapoints_to_alarm = 4
  evaluation_periods  = 5
  period              = 60

  dimensions = {
    AutoScalingGroupName = module.auto_scaling_group.autoscaling_group_name
  }
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_alarm" {
  alarm_name          = "Low CPU Alarm"
  alarm_description   = "Monitors CPU and triggers alarm on low CPU"
  alarm_actions       = [module.auto_scaling_group.autoscaling_policy_arns["scale-in-on-low-cpu"]]
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  threshold           = 30
  datapoints_to_alarm = 4
  evaluation_periods  = 5
  period              = 60

  dimensions = {
    AutoScalingGroupName = module.auto_scaling_group.autoscaling_group_name
  }
  tags = local.tags
}

# DB ###########################################################################

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = module.vpc.private_subnets
  tags       = local.tags
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier                     = "${local.name_prefix}-db"
  instance_use_identifier_prefix = true

  create_db_option_group    = false
  create_db_parameter_group = false

  engine               = "postgres"
  engine_version       = "14.6"
  family               = "postgres14" # DB parameter group
  major_engine_version = "14"         # DB option group
  instance_class       = "db.t3.micro"
  multi_az             = true

  storage_type      = "gp3"
  allocated_storage = 20

  db_name                = local.db_name
  username               = var.db_user
  create_random_password = false
  password               = var.db_password
  port                   = 5432

  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [module.postgresql_sg.security_group_id, module.all_egress_sg.security_group_id]

  skip_final_snapshot = true

  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_window           = "03:00-06:00"
  backup_retention_period = 0

  tags = local.tags
}

# S3, SQS, and Lambda ##########################################################

module "s3_bucket_raw" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket                   = "${local.name_prefix}-s3-bucket-raw"
  control_object_ownership = true
  acl                      = "private"
  tags                     = local.tags
}

module "s3_bucket_processed" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket                   = "${local.name_prefix}-s3-bucket-processed"
  control_object_ownership = true
  acl                      = "private"
  tags                     = local.tags
}

module "sqs" {
  source = "terraform-aws-modules/sqs/aws"
  name   = "${local.name_prefix}-queue"
  tags   = local.tags
}

module "s3_notifications" {
  source = "terraform-aws-modules/s3-bucket/aws//modules/notification"

  bucket = module.s3_bucket_raw.s3_bucket_id
  sqs_notifications = {
    sqs_create_object = {
      queue_arn = module.sqs.queue_arn
      events    = ["s3:ObjectCreated:*"]
    }
  }
}

module "s3_lambda_builds" {
  source = "terraform-aws-modules/s3-bucket/aws"
  bucket = "${local.name_prefix}-s3-bucket-lambda-builds"
  tags   = local.tags
}

module "lambda_function" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "${local.name_prefix}-anonymise-image"
  description   = "Anonymises images downloaded from a bucket and uploads processed image to another bucket"
  handler       = "anonymise_image.lambda_handler"
  runtime       = "python3.10"
  memory_size   = 1024
  timeout       = 60

  create_role = false
  lambda_role = local.lab_role.role_arn

  environment_variables = {
    PROCESSED_BUCKET_NAME = module.s3_bucket_processed.s3_bucket_id
  }

  source_path     = "./lambda_function"
  build_in_docker = true
  store_on_s3     = true
  s3_bucket       = module.s3_lambda_builds.s3_bucket_id

  tags = local.tags
}

resource "aws_lambda_event_source_mapping" "sqs_event" {
  event_source_arn = module.sqs.queue_arn
  function_name    = module.lambda_function.lambda_function_arn
  enabled          = true
  batch_size       = 1
}
