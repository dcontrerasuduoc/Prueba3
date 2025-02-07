terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.53.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "amazon_linux_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
 
  name = "VPC-DCONTRERAS"
  cidr = "10.0.0.0/16"
 
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
 
  enable_nat_gateway = true
  enable_vpn_gateway = false
 
  tags = {
    Terraform = "true"
    Environment = "prd"
  }
}

resource "aws_security_group" "allow_traffic" {
  name        = "GRUPO-DCONTRERAS"
  description = "Allow traffic on ports 80, 443, and 22"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "GRUPO-DCONTRERAS"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

locals {
  bucket_name = "bucket-dcontreras-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket" "example" {
  bucket = local.bucket_name
  tags = {
    Name = "MY BUCKET"
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.example.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "time_sleep" "wait_10_seconds" {
  depends_on      = [aws_s3_bucket.example]
  create_duration = "10s"
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.example.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject"],
      "Resource": [
        "${aws_s3_bucket.example.arn}/*"
      ]
    }]
  })

  depends_on = [time_sleep.wait_10_seconds]
}

resource "aws_s3_object" "object" {
  bucket = aws_s3_bucket.example.id
  key    = "index.php"
  source = "index.php"
  content_type = "text/html"

  depends_on = [aws_s3_bucket_policy.bucket_policy]
}

resource "aws_instance" "web" {
  count         = 3
  ami           = data.aws_ami.amazon_linux_ami.id
  instance_type = "t2.micro"
  key_name      = "vockey"

  subnet_id       = element(module.vpc.public_subnets, count.index)
  security_groups = [aws_security_group.allow_traffic.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd php
              sudo systemctl start httpd
              sudo systemctl enable httpd
              aws s3 cp s3://${aws_s3_bucket.example.bucket}/index.php /var/www/html/
              EOF

  tags = {
    Name = "EC2-DCONTRERAS-${count.index}"
  }
}

resource "aws_efs_file_system" "efs" {
  creation_token = "my-efs"
  tags = {
    Name = "my-efs"
  }
}

resource "aws_efs_mount_target" "efs_mount" {
  count          = 3
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = element(module.vpc.public_subnets, count.index)
  security_groups = [aws_security_group.allow_traffic.id]
}

resource "aws_lb" "alb" {
  name               = "MY-ALB-CONTRERAS"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_traffic.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Name = "MY-ALB-CONTRERAS"
  }
}

resource "aws_lb_target_group" "target_group" {
  name     = "TARGETS-DCONTRERAS"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "TARGETS-DCONTRERAS"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

resource "aws_lb_target_group_attachment" "target_attachment" {
  count            = 3
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id        = element(aws_instance.web.*.id, count.index)
  port             = 80
}

