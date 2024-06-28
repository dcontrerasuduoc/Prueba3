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

resource "random_string" "random_id" {
  length  = 8
  special = false
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Terraform   = "true"
    Environment = "prd"
  }
}

resource "aws_security_group" "allow_http_https_ssh" {
  vpc_id = module.vpc.vpc_id

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
    Name = "allow_http_https_ssh"
  }
}

resource "aws_s3_bucket" "website_bucket" {
  bucket = "my-website-bucket-${random_string.random_id.result}"
  acl    = "private"

  tags = {
    Name        = "website_bucket"
    Environment = "prd"
  }
}

resource "aws_s3_bucket_acl" "website_bucket_acl" {
  bucket = aws_s3_bucket.website_bucket.id
  acl    = "public-read"
}

resource "aws_s3_object" "index_php" {
  bucket = aws_s3_bucket.website_bucket.bucket
  key    = "index.php"
  source = "index.php"
  acl    = "public-read"
}

resource "aws_efs_file_system" "efs" {
  creation_token = "efs-for-web-servers-${random_string.random_id.result}"
}

resource "aws_instance" "web" {
  count = 3

  ami                         = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI (change as necessary)
  instance_type               = "t2.micro"
  subnet_id                   = element(module.vpc.public_subnets, count.index)
  key_name                    = "vockey"
  vpc_security_group_ids      = [aws_security_group.allow_http_https_ssh.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd php
              sudo systemctl start httpd
              sudo systemctl enable httpd
              sudo mkdir -p /var/www/html
              sudo mount -t efs ${aws_efs_file_system.efs.id}:/ /var/www/html
              aws s3 cp s3://${aws_s3_bucket.website_bucket.bucket}/index.php /var/www/html/
              EOF

  tags = {
    Name = "WebServerInstance"
  }
}

resource "aws_efs_mount_target" "efs_mount_target" {
  count           = 3
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = element(module.vpc.public_subnets, count.index)
  security_groups = [aws_security_group.allow_http_https_ssh.id]
}

resource "aws_lb" "alb" {
  name               = "my-alb-${random_string.random_id.result}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http_https_ssh.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Name        = "my-alb"
    Environment = "prd"
  }
}

resource "aws_lb_target_group" "tg" {
  name     = "my-tg-${random_string.random_id.result}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name        = "my-tg"
    Environment = "prd"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_lb_target_group_attachment" "tg_attachment" {
  count            = 3
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = element(aws_instance.web.*.id, count.index)
  port             = 80
}
