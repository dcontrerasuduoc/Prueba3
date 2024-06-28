provider aws {
  region = us-east-1
}

module vpc {
  source  = terraform-aws-modulesvpcaws
  version = 3.13.0

  name = my-vpc
  cidr = 10.0.0.016
  azs  = [us-east-1a, us-east-1b, us-east-1c]

  private_subnets = [10.0.1.024, 10.0.2.024, 10.0.3.024]
  public_subnets  = [10.0.101.024, 10.0.102.024, 10.0.103.024]

  enable_nat_gateway = true
  enable_vpn_gateway = false

  tags = {
    Terraform   = true
    Environment = prd
  }
}

resource aws_security_group web_sg {
  name_prefix = web-sg-
  description = Allow web traffic
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = tcp
    cidr_blocks = [0.0.0.00]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = tcp
    cidr_blocks = [0.0.0.00]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = tcp
    cidr_blocks = [0.0.0.00]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = [0.0.0.00]
  }
}

resource aws_s3_bucket website_bucket {
  bucket = my-website-bucket
  acl    = private
}

resource aws_s3_bucket_object index_php {
  bucket = aws_s3_bucket.website_bucket.bucket
  key    = index.php
  source = pathtoindex.php  # Ruta local del archivo index.php
  acl    = public-read
}

resource aws_instance web_server {
  count         = 3
  ami           = ami-0c55b159cbfafe1f0  # Amazon Linux 2 AMI
  instance_type = t2.micro
  key_name      = vockey
  subnet_id     = element(module.vpc.public_subnets, count.index)
  security_groups = [aws_security_group.web_sg.name]

  user_data = -EOF
              #!binbash
              sudo yum update -y
              sudo yum install -y httpd php
              sudo systemctl start httpd
              sudo systemctl enable httpd
              EOF

  tags = {
    Name = WebServer${count.index}
  }
}

resource aws_efs_file_system web_efs {
  creation_token = web-efs
}

resource aws_efs_mount_target efs_mount {
  count          = 3
  file_system_id = aws_efs_file_system.web_efs.id
  subnet_id      = element(module.vpc.private_subnets, count.index)
  security_groups = [aws_security_group.web_sg.id]
}

resource null_resource mount_efs {
  count = 3

  provisioner remote-exec {
    inline = [
      sudo yum install -y amazon-efs-utils,
      sudo mkdir -p varwwwhtml,
      sudo mount -t efs ${aws_efs_file_system.web_efs.id} varwwwhtml
    ]

    connection {
      type        = ssh
      user        = ec2-user
      private_key = file(~.sshvockey.pem)
      host        = aws_instance.web_server[count.index].public_ip
    }
  }
}

resource null_resource copy_index {
  count = 3

  provisioner remote-exec {
    inline = [
      aws s3 cp s3${aws_s3_bucket.website_bucket.bucket}index.php varwwwhtml
    ]

    connection {
      type        = ssh
      user        = ec2-user
      private_key = file(~.sshvockey.pem)
      host        = aws_instance.web_server[count.index].public_ip
    }
  }
}

resource aws_lb web_lb {
  name               = web-lb
  internal           = false
  load_balancer_type = application
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false
}

resource aws_lb_target_group web_tg {
  name     = web-tg
  port     = 80
  protocol = HTTP
  vpc_id   = module.vpc.vpc_id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = 
    matcher             = 200
  }
}

resource aws_lb_listener web_listener {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = 80
  protocol          = HTTP

  default_action {
    type             = forward
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

resource aws_lb_target_group_attachment web_tg_attachment {
  count            = 3
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web_server[count.index].id
  port             = 80
}