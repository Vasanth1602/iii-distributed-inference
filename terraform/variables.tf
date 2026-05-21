variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
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