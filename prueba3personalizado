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

# Generar un ID aleatorio
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Crear el bucket S3 con el nombre deseado
resource "aws_s3_bucket" "example" {
  bucket = "bucket-contreras-${random_id.bucket_suffix.hex}"
  tags = {
    Name = "MY BUCKET"
  }
}

# Permitir el acceso público al bucket S3
resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.example.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Esperar antes de aplicar la política de acceso público
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

  depends_on = [aws_s3_bucket_public_access_block.example]
}

# Crear objeto index.php dentro del bucket usando aws_s3_object
resource "aws_s3_object" "object" {
  bucket = aws_s3_bucket.example.id
  key    = "index.php"
  source = "index.php"

  depends_on = [aws_s3_bucket_policy.bucket_policy]
}

# Lanzar 3 instancias EC2 en diferentes AZs
resource "aws_instance" "web" {
  count         = 3
  ami           = data.aws_ami.amazon_linux_ami.id  # Usar la AMI encontrada
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

# Crear un volumen EFS y montarlo en las instancias EC2
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

# Crear un Load Balancer y adjuntar las instancias
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
