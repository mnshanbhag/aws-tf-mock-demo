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

variable "private_subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_id" {
  description = "SG (e.g. the EC2 app server's) that's allowed to reach SQL Server on 1433"
  type        = string
}

variable "username" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}

variable "instance_class" {
  type = string
}

variable "allocated_storage" {
  type = number
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.name}-db-subnet-group"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db-sg"
  description = "Allow SQL Server traffic only from the app tier"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SQL Server from app tier"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-db-sg"
  }
}

# sqlserver-ex = SQL Server Express, the free/lightest edition — fine for a
# mock and for small real workloads. Swap to sqlserver-se / -web / -ee for
# Standard, Web, or Enterprise editions on a real account.
resource "aws_db_instance" "this" {
  identifier        = "${var.name}-sqlserver"
  engine            = "sqlserver-ex"
  engine_version    = "15.00"
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage

  username = var.username
  password = var.password

  db_subnet_group_name  = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  publicly_accessible = false
  multi_az            = false

  # Mock-only settings — for a real prod DB you'd want skip_final_snapshot =
  # false and a real final_snapshot_identifier so you don't lose data on teardown.
  skip_final_snapshot = true
  deletion_protection  = false
}

output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}
