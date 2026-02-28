terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Credentials provided via AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY env vars
  # exported by deploy.sh from the aws login profile
}

# ── Latest Ubuntu 24.04 LTS AMI ──
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── SSH Key Pair ──
resource "aws_key_pair" "phone_coding" {
  key_name   = "${var.instance_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# ── Security Group ──
resource "aws_security_group" "phone_coding" {
  name        = "${var.instance_name}-sg"
  description = "Phone coding remote Amp environment"

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  # Mosh (UDP)
  ingress {
    from_port   = 60000
    to_port     = 61000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Mosh"
  }

  # ttyd web terminal
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ttyd web terminal"
  }

  # All outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.instance_name}-sg"
  }
}

# ── EC2 Instance ──
resource "aws_instance" "phone_coding" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.phone_coding.key_name
  vpc_security_group_ids = [aws_security_group.phone_coding.id]

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    ts_authkey   = var.ts_authkey
    amp_api_key  = var.amp_api_key
    github_token = var.github_token
  })

  # Spot instance support
  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "persistent"
        instance_interruption_behavior = "stop"
      }
    }
  }

  tags = {
    Name = var.instance_name
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
