variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-1"
}

variable "key_name" {
  description = "Name of the AWS key pair for SSH access"
  type        = string
}

variable "public_key_path" {
  description = "Path to your local public SSH key"
  type        = string
  default     = "~/.ssh/kube-quest.pub"
}

variable "instance_type_kube" {
  description = "Instance type for Kubernetes nodes (t3.small = 2 CPUs, 2GB RAM — minimum requis par kubeadm)"
  type        = string
  default     = "t3.small"
}

variable "instance_type_small" {
  description = "Instance type for ingress and monitoring (t2.micro = free tier)"
  type        = string
  default     = "t2.micro"
}

variable "project_name" {
  description = "Project tag applied to all resources"
  type        = string
  default     = "kube-quest"
}
