terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "allowed_ssh_cidr" {
  type = string
}

variable "instance_profile_name" {
  description = "IAM instance profile to attach (optional)"
  type        = string
  default     = null
}

resource "aws_security_group" "ec2" {
  name        = "${var.name}-ec2-sg"
  description = "Allow SSH in, everything out"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-ec2-sg"
  }
}

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = var.instance_profile_name

  tags = {
    Name = "${var.name}-ec2"
  }
}

output "instance_id" {
  value = aws_instance.this.id
}

output "security_group_id" {
  value = aws_security_group.ec2.id
}

output "private_ip" {
  value = aws_instance.this.private_ip
}
