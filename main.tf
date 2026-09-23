
############################################################
# NCA - Case Study 1 Phase 1
# AWS Infrastructure
#
# Architecture:
# Internet
#    |
#    v
# Internet Gateway
#    |
#    v
# Public Subnets (AZ 1a + 1b)
#    |
#    v
# Application Load Balancer
#    |
#    v
# Private Subnets (AZ 1a + 1b)
#    |
#    +--> Auto Scaling Web Servers (Nginx)
#    |
#    +--> RDS MySQL
#
# Monitoring:
# EC2 -> CloudWatch Agent -> CloudWatch
# CloudWatch Alarm -> Auto Scaling
# CloudWatch Alarm -> SNS
############################################################


############################################################
# 0. PROVIDER
############################################################

provider "aws" {
  region = "eu-central-1"
}


############################################################
# 1. VPC
############################################################

resource "aws_vpc" "nca_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "nca-cs1-vpc"
  }
}


############################################################
# 2. PUBLIC SUBNET - AVAILABILITY ZONE 1a
############################################################

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.nca_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-lb-1"
  }
}


############################################################
# 3. PRIVATE SUBNET - WEB SERVERS - AZ 1a
############################################################

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.nca_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "private-subnet-web-1"
  }
}


############################################################
# 4. PRIVATE SUBNET - WEB SERVERS - AZ 1b
############################################################

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.nca_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-central-1b"

  tags = {
    Name = "private-subnet-web-2"
  }
}


############################################################
# 5. PUBLIC SUBNET - AVAILABILITY ZONE 1b
############################################################

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.nca_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-lb-2"
  }
}


############################################################
# 6. INTERNET GATEWAY
############################################################

resource "aws_internet_gateway" "nca_igw" {
  vpc_id = aws_vpc.nca_vpc.id

  tags = {
    Name = "nca-cs1-igw"
  }
}


############################################################
# 7. PUBLIC ROUTE TABLE
############################################################

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.nca_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.nca_igw.id
  }

  tags = {
    Name = "nca-public-route-table"
  }
}


############################################################
# 8. PUBLIC ROUTE TABLE ASSOCIATIONS
############################################################

resource "aws_route_table_association" "public_assoc_1" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}


############################################################
# 9. ELASTIC IP FOR NAT GATEWAY
############################################################

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "nca-nat-eip"
  }
}


############################################################
# 10. NAT GATEWAY
############################################################

resource "aws_nat_gateway" "nca_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  depends_on = [
    aws_internet_gateway.nca_igw
  ]

  tags = {
    Name = "nca-nat-gateway"
  }
}


############################################################
# 11. PRIVATE ROUTE TABLE
############################################################

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.nca_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nca_nat.id
  }

  tags = {
    Name = "nca-private-route-table"
  }
}


############################################################
# 12. PRIVATE ROUTE TABLE ASSOCIATIONS
############################################################

resource "aws_route_table_association" "private_assoc_1" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_assoc_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}


############################################################
# 13. AMAZON LINUX AMI
############################################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}


############################################################
# 14. ALB SECURITY GROUP
############################################################

resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.nca_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nca-alb-sg"
  }
}


############################################################
# 15. WEB SERVER SECURITY GROUP
############################################################

resource "aws_security_group" "web_sg" {
  name   = "web-server-sg"
  vpc_id = aws_vpc.nca_vpc.id

  # Only the ALB can access the web servers
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nca-web-sg"
  }
}


############################################################
# 16. DATABASE SECURITY GROUP
############################################################

resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  vpc_id = aws_vpc.nca_vpc.id

  # MySQL is ONLY accessible from the web servers
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nca-db-sg"
  }
}


############################################################
# 17. APPLICATION LOAD BALANCER
############################################################

resource "aws_lb" "web_alb" {
  name               = "nca-web-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb_sg.id
  ]

  subnets = [
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_2.id
  ]

  tags = {
    Name = "nca-web-alb"
  }
}


############################################################
# 18. ALB TARGET GROUP
############################################################

resource "aws_lb_target_group" "web_tg" {
  name     = "nca-web-targets"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.nca_vpc.id

  health_check {
    path     = "/"
    protocol = "HTTP"
    port     = "traffic-port"

    healthy_threshold   = 2
    unhealthy_threshold = 2

    timeout  = 5
    interval = 30
  }

  tags = {
    Name = "nca-web-target-group"
  }
}


############################################################
# 19. ALB LISTENER
############################################################

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn

  port     = 80
  protocol = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}


############################################################
# 20. IAM ROLE FOR WEB SERVERS
############################################################

resource "aws_iam_role" "web_server_role" {
  name = "web-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Action = "sts:AssumeRole"

        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}


############################################################
# 21. CLOUDWATCH AGENT POLICY
############################################################

resource "aws_iam_role_policy_attachment" "cw_agent_policy" {
  role = aws_iam_role.web_server_role.name

  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}


############################################################
# 22. INSTANCE PROFILE
############################################################

resource "aws_iam_instance_profile" "web_server_profile" {
  name = "web-server-profile"
  role = aws_iam_role.web_server_role.name
}


############################################################
# 23. CLOUDWATCH LOG GROUPS
############################################################

resource "aws_cloudwatch_log_group" "nginx_logs" {
  name              = "/nca/nginx/access"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "nginx_error_logs" {
  name              = "/nca/nginx/error"
  retention_in_days = 7
}


############################################################
# 24. LAUNCH TEMPLATE
############################################################

resource "aws_launch_template" "web_template" {
  name_prefix = "web-template-"

  image_id = data.aws_ami.amazon_linux.id

  instance_type = "t3.micro"

  vpc_security_group_ids = [
    aws_security_group.web_sg.id
  ]

  iam_instance_profile {
    name = aws_iam_instance_profile.web_server_profile.name
  }

  user_data = base64encode(<<-EOF
#!/bin/bash

# Update operating system
yum update -y

# Install Nginx and CloudWatch Agent
yum install -y nginx amazon-cloudwatch-agent

# Start Nginx
systemctl enable nginx
systemctl start nginx

# Create simple web page
echo "<h1>Welkom op de NCA-webserver</h1>" > /usr/share/nginx/html/index.html

# CloudWatch Agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CONFIG'
{
  "metrics": {
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "totalcpu": true,
        "metrics_collection_interval": 60
      },

      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      },

      "disk": {
        "measurement": [
          "used_percent"
        ],
        "resources": [
          "*"
        ],
        "metrics_collection_interval": 60
      }
    }
  },

  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/nca/nginx/access",
            "log_stream_name": "{instance_id}"
          },

          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/nca/nginx/error",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CONFIG

# Start CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

EOF
  )

  tags = {
    Name = "NCA-Web-Server"
  }
}


############################################################
# 25. AUTO SCALING GROUP
############################################################

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity = 2
  min_size         = 1
  max_size         = 3

  # Web servers are distributed over both private subnets
  vpc_zone_identifier = [
    aws_subnet.private_subnet.id,
    aws_subnet.private_subnet_2.id
  ]

  # Attach instances to ALB
  target_group_arns = [
    aws_lb_target_group.web_tg.arn
  ]

  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }

  # Rolling deployment strategy
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }

    triggers = [
      "launch_template"
    ]
  }

  tag {
    key                 = "Name"
    value               = "NCA-Web-Server-ASG"
    propagate_at_launch = true
  }
}


############################################################
# 26. SCALE UP POLICY
############################################################

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "nca-scale-up"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name

  adjustment_type    = "ChangeInCapacity"
  scaling_adjustment = 1

  cooldown = 300
}


############################################################
# 27. SCALE DOWN POLICY
############################################################

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "nca-scale-down"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name

  adjustment_type    = "ChangeInCapacity"
  scaling_adjustment = -1

  cooldown = 300
}


############################################################
# 28. SNS ALERT TOPIC
############################################################

resource "aws_sns_topic" "alerts" {
  name = "nca-alerts"
}


############################################################
# 29. SNS EMAIL SUBSCRIPTION
############################################################


# AWS will send a confirmation email after deployment.

resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn

  protocol = "email"

  endpoint = "noudpeters8@gmail.com"
}


############################################################
# 30. CLOUDWATCH HIGH CPU ALARM
############################################################

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name = "nca-web-high-cpu"

  alarm_description = "Scale web servers when average CPU exceeds 70% for 5 minutes"

  comparison_operator = "GreaterThanThreshold"

  evaluation_periods = 1

  metric_name = "CPUUtilization"

  namespace = "AWS/EC2"

  period = 300

  statistic = "Average"

  threshold = 70

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }

  alarm_actions = [
    aws_autoscaling_policy.scale_up.arn,
    aws_sns_topic.alerts.arn
  ]
}


############################################################
# 31. CLOUDWATCH LOW CPU ALARM
############################################################

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name = "nca-web-low-cpu"

  alarm_description = "Scale web servers down when average CPU is below 30% for 5 minutes"

  comparison_operator = "LessThanThreshold"

  evaluation_periods = 1

  metric_name = "CPUUtilization"

  namespace = "AWS/EC2"

  period = 300

  statistic = "Average"

  threshold = 30

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }

  alarm_actions = [
    aws_autoscaling_policy.scale_down.arn,
    aws_sns_topic.alerts.arn
  ]
}


############################################################
# 32. CLOUDWATCH DASHBOARD
############################################################

resource "aws_cloudwatch_dashboard" "nca_dashboard" {
  dashboard_name = "nca-web-dashboard"

  dashboard_body = jsonencode({
    widgets = [

      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          title  = "Web Server CPU Utilization"
          region = "eu-central-1"

          metrics = [
            [
              "AWS/EC2",
              "CPUUtilization",
              "AutoScalingGroupName",
              aws_autoscaling_group.web_asg.name
            ]
          ]

          period = 300
          stat   = "Average"

          view = "timeSeries"
        }
      }

    ]
  })
}


############################################################
# 33. DATABASE PASSWORD
############################################################

variable "db_password" {
  description = "Password for the NCA MySQL database"

  type = string

  sensitive = true
}


############################################################
# 34. RDS DATABASE SUBNET GROUP
############################################################

resource "aws_db_subnet_group" "db_subnet" {
  name = "main-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_subnet.id,
    aws_subnet.private_subnet_2.id
  ]

  tags = {
    Name = "nca-db-subnet-group"
  }
}


############################################################
# 35. MYSQL DATABASE
############################################################

resource "aws_db_instance" "mysql_db" {
  allocated_storage = 20

  db_name = "ticketsdb"

  engine = "mysql"

  engine_version = "8.0"

  instance_class = "db.t3.micro"

  username = "admin"

  password = var.db_password

  db_subnet_group_name = aws_db_subnet_group.db_subnet.name

  vpc_security_group_ids = [
    aws_security_group.db_sg.id
  ]

  skip_final_snapshot = true

  tags = {
    Name = "nca-mysql-database"
  }
}


############################################################
# 36. OUTPUTS
############################################################

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"

  value = aws_lb.web_alb.dns_name
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint"

  value = aws_db_instance.mysql_db.address
}

output "cloudwatch_dashboard" {
  description = "CloudWatch dashboard name"

  value = aws_cloudwatch_dashboard.nca_dashboard.dashboard_name
}

