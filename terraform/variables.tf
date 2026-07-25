variable "aws_region" {
  description = "AWS region for infrastructure deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (production / staging / dev)"
  type        = string
  default     = "production"
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "AWS SSH Key pair name for EC2 access"
  type        = string
  default     = "syncwrite-key"
}

variable "public_key_path" {
  description = "Path to local public SSH key (~/.ssh/id_rsa.pub)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "domain_name" {
  description = "Fully qualified domain name for public routing"
  type        = string
  default     = "syncwrite.example.com"
}
