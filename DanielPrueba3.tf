provider "aws" {
  region = "us-east-1"
}

# 1. Crear VPC
module "my_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.1.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["us-east-1a", "us-east-1b", "us-east-1c"]

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = false

  tags = {
    Terraform   = "true"
    Environment = "prd"
  }
}

# 2. Crear Security Group
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Security group for HTTP, HTTPS, SSH access"
  vpc_id      = module.my_vpc.vpc_id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web_sg"
  }
}

# 3. Crear Bucket S3 y subir archivo index.php
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-unique-bucket-name"
  acl    = "private"
}

resource "aws_s3_bucket_object" "index_php" {
  bucket = aws_s3_bucket.my_bucket.bucket
  key    = "index.php"
  source = "index.php"
}

# 4. Crear instancias EC2
resource "aws_instance" "web_servers" {
  count         = 3
  ami           = "ami-0abcdef1234567890"
  instance_type = "t2.micro"
  key_name      = "vockey"
  subnet_id     = element(module.my_vpc.public_subnets, count.index)

  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum install -y httpd php
              systemctl start httpd
              systemctl enable httpd
              mkdir /mnt/efs_mount
              mount -t efs ${aws_efs_file_system.my_efs.file_system_id}:/ /mnt/efs_mount
              cp /mnt/efs_mount/index.php /var/www/html/
              EOF
}

# 5. Crear EFS
resource "aws_efs_file_system" "my_efs" {
  creation_token = "my-efs"
  performance_mode = "generalPurpose"

  tags = {
    Name = "my-efs"
  }
}

# 6. Crear ALB
resource "aws_lb" "my_lb" {
  name               = "my-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = module.my_vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Name = "my-lb"
  }
}

resource "aws_lb_target_group" "web_target_group" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.my_vpc.vpc_id

  health_check {
    path = "/"
    port = 80
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.my_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_target_group.arn
  }
}

resource "aws_lb_target_group_attachment" "web_attachment" {
  count             = 3
  target_group_arn  = aws_lb_target_group.web_target_group.arn
  target_id         = aws_instance.web_servers[count.index].id
  port              = 80
}
