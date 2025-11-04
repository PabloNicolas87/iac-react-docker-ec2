##############################################
# 0. BASE CONFIGURATION
##############################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = "terraform-assumido"

  default_tags {
    tags = {
      Project = "lab1"
      Env     = "dev"
      Owner   = "Pablo"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  repo_name  = "lab1-runtime"
  image_tag  = "latest"
}

##############################################
# 1. IAM ROLE AND INSTANCE PROFILE
##############################################

resource "aws_iam_role" "ec2_role" {
  name = "lab1-ec2-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = { Service = "ec2.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "lab1-ec2-deploy-role"
  role = aws_iam_role.ec2_role.name
  depends_on = [aws_iam_role.ec2_role]
}

##############################################
# 2. NETWORKING
##############################################

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "lab1-vpc" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "lab1-igw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags = { Name = "lab1-subnet-public-a" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "lab1-rt-public" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

##############################################
# 3. SECURITY GROUP
##############################################

resource "aws_security_group" "web_sg" {
  name        = "lab1-sg"
  description = "Allow public HTTP traffic"
  vpc_id      = aws_vpc.main.id

  ingress = [{
    description      = "Public HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    security_groups  = []
    self             = false
  }]

  egress = [{
    description      = "All outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    security_groups  = []
    self             = false
  }]

  tags = { Name = "lab1-sg" }
}

##############################################
# 4. ECR REPOSITORY
##############################################

resource "aws_ecr_repository" "app_repo" {
  name         = local.repo_name
  force_delete = true
  tags         = { Name = "lab1-ecr" }
}

##############################################
# 5. EC2 INSTANCE
##############################################

resource "aws_instance" "app_server" {
  ami                        = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    REGION="${var.region}"
    ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
    REPO_NAME="${local.repo_name}"
    IMAGE_URL="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:${local.image_tag}"

    echo "=== Installing Docker ==="
    dnf update -y
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user

    echo "=== Logging into ECR ==="
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

    echo "=== Running container ==="
    docker pull "$IMAGE_URL"
    docker run -d --restart always -p 80:80 "$IMAGE_URL"

    echo "=== Setup complete ==="
  EOF

  tags = { Name = "lab1-ec2" }
}

##############################################
# 6. ELASTIC IP
##############################################

resource "aws_eip" "app_eip" {
  domain = "vpc"
  tags   = { Name = "lab1-eip" }
}

resource "aws_eip_association" "app_eip_assoc" {
  instance_id   = aws_instance.app_server.id
  allocation_id = aws_eip.app_eip.id
}
