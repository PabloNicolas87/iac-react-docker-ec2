variable "region" {
  description = "AWS region where resources will be deployed"
  default     = "us-east-2"
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI for Free Tier"
  default     = "ami-0199d4b5b8b4fde0e"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.micro"
}
