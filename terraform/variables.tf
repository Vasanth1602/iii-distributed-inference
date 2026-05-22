variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Used to name all resources consistently"
  type        = string
  default     = "iii-inference"
}

variable "github_repo" {
  description = "Your public GitHub repo URL for git clone in user data"
  type        = string
  default     = "https://github.com/Vasanth1602/iii-distributed-inference.git"
}

variable "gateway_instance_type" {
  description = "EC2 instance type for the gateway VM (nginx + iii engine + caller-worker)"
  type        = string
  default     = "t3.small"
}

variable "inference_instance_type" {
  description = "EC2 instance type for the inference worker VM"
  type        = string
  default     = "t3.micro"
}

variable "gateway_private_ip" {
  description = "Fixed private IP for the gateway VM — inference worker uses this to reach the iii engine"
  type        = string
  default     = "10.0.1.10"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (gateway VM)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (inference worker VM)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "gateway_disk_gb" {
  description = "Root EBS volume size in GB for the gateway VM"
  type        = number
  default     = 20
}

variable "inference_disk_gb" {
  description = "Root EBS volume size in GB for the inference worker VM"
  type        = number
  default     = 20
}