data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical (official Ubuntu AMI publisher)
}

# Registers your local SSH public key with AWS so it can be injected into the instance for `ubuntu` login.
resource "aws_key_pair" "app" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Name = "${var.project_name}-ssh-key"
  }
}

# IAM role the EC2 instance assumes at runtime; grants only CloudWatch logging and Secrets Manager access below.
resource "aws_iam_role" "app" {
  name = "${var.project_name}-ec2-runtime"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-ec2-runtime"
  }
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.app.name
}

# Lets the CloudWatch Agent create log streams and publish log events, scoped to this project's log groups only.
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.project_name}-cloudwatch-logs"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents"
      ]
      Resource = [for arn in var.log_group_arns : "${arn}:*"]
    }]
  })
}

# Lets the instance read the RDS master secret and read/write the app secret; scoped to just those two ARNs.
resource "aws_iam_role_policy" "secrets_manager" {
  name = "${var.project_name}-database-secrets"
  role = aws_iam_role.app.id
  policy = templatefile("${path.module}/secrets-policy.json", {
    region            = var.aws_region
    master_secret_arn = var.db_admin_secret_arn
    app_secret_arn    = var.db_app_secret_arn
  })
}

# The single app server: runs bootstrap.sh as user-data on first boot to install and configure everything.
resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.app_security_group_id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.app.key_name
  iam_instance_profile        = aws_iam_instance_profile.app.name
  monitoring                  = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required" # enforces IMDSv2, blocking classic SSRF-based instance-metadata theft
  }

  user_data = templatefile("${path.module}/bootstrap.sh", {
    app_port            = var.app_port
    aws_region          = var.aws_region
    db_name             = var.db_name
    db_admin_secret_arn = var.db_admin_secret_arn
    db_app_secret_arn   = var.db_app_secret_arn
    db_host             = var.db_host
    db_port             = var.db_port
    domain_name_json    = jsonencode(var.domain_name)
    certbot_email_json  = jsonencode(var.certbot_email)
    nginx_server_name   = var.domain_name == "" ? "_" : var.domain_name
    log_group_names     = var.log_group_names
  })

  tags = {
    Name = "${var.project_name}-app"
  }

  depends_on = [
    aws_iam_role_policy.cloudwatch_logs,
    aws_iam_role_policy.secrets_manager
  ]
}
