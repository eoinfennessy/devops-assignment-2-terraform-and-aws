provider "aws" {
  region = local.region
}

locals {
  name   = "ef"
  region = "us-east-1"

  tags = {
    Project = "devops-assignment-2"
  }
}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${local.name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  # database_subnets = ["10.0.51.0/24", "10.0.52.0/24", "10.0.53.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # create_database_subnet_group           = true
  # create_database_nat_gateway_route      = true
  # create_database_internet_gateway_route = true
  # create_database_subnet_route_table     = true

  enable_dns_hostnames = true

  tags = local.tags
}

module "http_sg" {
  source = "terraform-aws-modules/security-group/aws"

  vpc_id = module.vpc.vpc_id

  name                = "http-sg"
  description         = "Allow all HTTP ingress and all egress"
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
  egress_rules        = ["all-all"]

  tags = local.tags
}

module "ssh_sg" {
  source = "terraform-aws-modules/security-group/aws"

  vpc_id = module.vpc.vpc_id

  name                = "ssh_sg"
  description         = "Allows all SSH ingress"
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp"]

  tags = local.tags
}

module "postgresql_sg" {
  source = "terraform-aws-modules/security-group/aws"

  vpc_id = module.vpc.vpc_id

  name                = "postgresql_sg"
  description         = "Allows PostgreSQL ingress on port 5432"
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["postgresql-tcp"]

  tags = local.tags
}

module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"

  key_name           = "${local.name}-key"
  create_private_key = true

  tags = local.tags
}

# module "web_servers" {
#   source = "terraform-aws-modules/ec2-instance/aws"

#   count = 3

#   name                        = "web-server-${count.index}"
#   ami                         = "ami-0c7e036a20f1b245d"
#   instance_type               = "t2.nano"
#   key_name                    = module.key_pair.key_pair_name
#   vpc_security_group_ids      = [module.http_sg.security_group_id, module.ssh_sg.security_group_id]
#   subnet_id                   = module.vpc.public_subnets[count.index]
#   associate_public_ip_address = true
#   user_data = <<-EOT
#     #!/bin/bash
#     echo "<b>Instance ID:</b> " > /var/www/html/id.html
#     curl --silent http://169.254.169.254/latest/meta-data/instance-id/ >> /var/www/html/id.html
#   EOT
#   # monitoring             = true

#   tags = local.tags
# }

module "alb" {
  source = "terraform-aws-modules/alb/aws"

  name = "week-8-alb"

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [module.http_sg.security_group_id]

  target_groups = [
    {
      name_prefix      = "tg-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      # targets = {
      #   web_server_0_target = {
      #     target_id = module.web_servers[0].id
      #     port = 80
      #   }
      #   web_server_1_target = {
      #     target_id = module.web_servers[1].id
      #     port = 80
      #   }
      #   web_server_2_target = {
      #     target_id = module.web_servers[2].id
      #     port = 80
      #   }
      # }
    }
  ]
  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]
}

module "auto_scaling_group" {
  source = "terraform-aws-modules/autoscaling/aws"

  name = "${local.name}-auto-scaling-group"

  vpc_zone_identifier       = module.vpc.public_subnets
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  target_group_arns         = module.alb.target_group_arns
  health_check_grace_period = 30
  # enabled_metrics = 

  # Launch template
  launch_template_name        = "tf-launch-template"
  launch_template_description = "Launch template example"
  image_id                    = "ami-0c7e036a20f1b245d"
  instance_type               = "t2.nano"
  key_name                    = module.key_pair.key_pair_name
  security_groups             = [module.ssh_sg.security_group_id, module.http_sg.security_group_id]
  enable_monitoring           = true
  user_data                   = base64encode("#!/bin/bash\necho \"<b>Instance ID:</b> \" > /var/www/html/id.html\ncurl --silent http://169.254.169.254/latest/meta-data/instance-id/ >> /var/www/html/id.html")

  # auto-scaling policies
  scaling_policies = {
    scale-up-on-high-cpu = {
      policy_type        = "SimpleScaling"
      adjustment_type    = "ChangeInCapacity"
      scaling_adjustment = 1
      cooldown           = 30
    },
    scale-down-on-low-cpu = {
      policy_type        = "SimpleScaling"
      adjustment_type    = "ChangeInCapacity"
      scaling_adjustment = -1
      cooldown           = 30
    }
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "High CPU Alarm"
  alarm_description   = "Monitors CPU and triggers alarm on high CPU"
  alarm_actions       = [module.auto_scaling_group.autoscaling_policy_arns["scale-up-on-high-cpu"]]
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 40
  datapoints_to_alarm = 1
  evaluation_periods  = 2
  period              = 60

  dimensions = {
    AutoScalingGroupName = module.auto_scaling_group.autoscaling_group_name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_alarm" {
  alarm_name          = "Low CPU Alarm"
  alarm_description   = "Monitors CPU and triggers alarm on low CPU"
  alarm_actions       = [module.auto_scaling_group.autoscaling_policy_arns["scale-down-on-low-cpu"]]
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  threshold           = 15
  datapoints_to_alarm = 1
  evaluation_periods  = 2
  period              = 60

  dimensions = {
    AutoScalingGroupName = module.auto_scaling_group.autoscaling_group_name
  }
}

resource "aws_db_subnet_group" "postgresql_subnet_group" {
  name       = "postgresql-subnet-group"
  subnet_ids = module.vpc.public_subnets

  tags = local.tags
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier                     = "${local.name}-db"
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

  db_name                = "${local.name}db"
  username               = "postgres"
  create_random_password = false
  password               = "hdippassword123"
  port                   = 5432

  publicly_accessible    = true
  db_subnet_group_name   = aws_db_subnet_group.postgresql_subnet_group.name
  vpc_security_group_ids = [module.postgresql_sg.security_group_id]

  performance_insights_enabled = false
  skip_final_snapshot          = true

  # maintenance_window      = "Mon:00:00-Mon:03:00"
  # backup_window           = "03:00-06:00"
  backup_retention_period = 0

  tags = local.tags
}
