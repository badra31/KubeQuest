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

# ── AMI dynamique ─────────────────────────────────────────────────────────────
# Récupère automatiquement la dernière Ubuntu 22.04 LTS officielle de Canonical
# Avantage : pas besoin de mettre à jour l'ID manuellement selon la région

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (éditeur officiel d'Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
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
  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
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
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_kube
  key_name               = aws_key_pair.kube_quest.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.kube_nodes.id]

  # IMDSv2 — empêche certaines attaques de récupérer les credentials AWS depuis un pod
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  # user_data = script exécuté au 1er démarrage de la VM
  # Il installe Docker + kubeadm + kubelet + kubectl (via common.sh)
  # et définit le nom de la machine (hostname)
  user_data = base64encode(join("\n", [
    file("${path.module}/user_data/common.sh"),
    "hostnamectl set-hostname kube-1"
  ]))

  root_block_device {
    volume_size = 15
    volume_type = "gp3"
  }

  # ignore_changes sur ami : évite de recréer la VM si Ubuntu publie une nouvelle image
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-kube-1"
    Role = "control-plane"
  })
}

resource "aws_instance" "kube_2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_kube
  key_name               = aws_key_pair.kube_quest.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.kube_nodes.id]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  user_data = base64encode(join("\n", [
    file("${path.module}/user_data/common.sh"),
    "hostnamectl set-hostname kube-2"
  ]))

  root_block_device {
    volume_size = 15
    volume_type = "gp3"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-kube-2"
    Role = "worker"
  })
}

resource "aws_instance" "ingress" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_small
  key_name               = aws_key_pair.kube_quest.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.ingress_node.id]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  user_data = base64encode(join("\n", [
    file("${path.module}/user_data/common.sh"),
    "hostnamectl set-hostname ingress"
  ]))

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ingress"
    Role = "ingress"
  })
}

resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_small
  key_name               = aws_key_pair.kube_quest.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.monitoring_node.id]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  user_data = base64encode(join("\n", [
    file("${path.module}/user_data/common.sh"),
    "hostnamectl set-hostname monitoring"
  ]))

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
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
