terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5"
}

provider "aws" {
  region = var.aws_region
}

# ── Key pair ──────────────────────────────────────────────────────────────────

resource "aws_key_pair" "kube_quest" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
  tags       = local.common_tags
}

# ── VPC & networking ──────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(local.common_tags, { Name = "${var.project_name}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.project_name}-igw" })
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, { Name = "${var.project_name}-subnet" })
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-rt" })
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# ── Security groups ───────────────────────────────────────────────────────────

resource "aws_security_group" "kube_nodes" {
  name        = "${var.project_name}-kube-nodes"
  description = "Allow inter-node and SSH traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "All internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-kube-sg" })
}

resource "aws_security_group" "ingress_node" {
  name        = "${var.project_name}-ingress-node"
  description = "Allow HTTP/HTTPS and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-ingress-sg" })
}

resource "aws_security_group" "monitoring_node" {
  name        = "${var.project_name}-monitoring-node"
  description = "Allow monitoring ports and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${var.project_name}-monitoring-sg" })
}

# ── EC2 instances ─────────────────────────────────────────────────────────────

resource "aws_instance" "kube_1" {
  ami                    = var.ami_id
  instance_type          = var.instance_type_kube
  key_name               = aws_key_pair.kube_quest.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.kube_nodes.id]
  user_data              = file("${path.module}/user_data/common.sh")

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-kube-1"
    Role = "control-plane"
  })
}

resource "aws_instance" "kube_2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type_kube
  key_name               = aws_key_pair.kube_quest.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.kube_nodes.id]
  user_data              = file("${path.module}/user_data/common.sh")

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-kube-2"
    Role = "worker"
  })
}

resource "aws_instance" "ingress" {
  ami                    = var.ami_id
  instance_type          = var.instance_type_ingress
  key_name               = aws_key_pair.kube_quest.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.ingress_node.id]
  user_data              = file("${path.module}/user_data/common.sh")

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ingress"
    Role = "ingress"
  })
}

resource "aws_instance" "monitoring" {
  ami                    = var.ami_id
  instance_type          = var.instance_type_monitoring
  key_name               = aws_key_pair.kube_quest.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.monitoring_node.id]
  user_data              = file("${path.module}/user_data/common.sh")

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-monitoring"
    Role = "monitoring"
  })
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  common_tags = {
    Project     = var.project_name
    ManagedBy   = "terraform"
    Environment = "cloud-lab"
  }
}
