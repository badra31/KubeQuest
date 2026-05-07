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
  description = "Instance type for Kubernetes nodes"
  type        = string
  default     = "t2.micro"
}

variable "instance_type_ingress" {
  description = "Instance type for ingress node"
  type        = string
  default     = "t2.micro"
}

variable "instance_type_monitoring" {
  description = "Instance type for monitoring node"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI (update per region)"
  type        = string
  default     = "ami-09b10fca4b0ed1bf4" # eu-west-1 Ubuntu 22.04
}

variable "project_name" {
  description = "Project tag applied to all resources"
  type        = string
  default     = "kube-quest"
}
