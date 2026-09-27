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

  owners = ["099720109477"]
}

resource "aws_key_pair" "app" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Name = "${var.project_name}-ssh-key"
  }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.app_security_group_id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.app.key_name

  user_data = templatefile("${path.module}/bootstrap.sh", {
    app_port = var.app_port
  })

  tags = {
    Name = "${var.project_name}-app"
  }
}
