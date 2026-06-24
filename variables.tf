variable "project_name" {
  description = "Short name used as a prefix/tag on every resource"
  type        = string
  default     = "mits-demo"
}

variable "environment" {
  description = "Environment tag, e.g. dev / staging / prod"
  type        = string
  default     = "dev"
}

# --- Regions -----------------------------------------------------------
# London as primary (closest to home), Ireland as secondary, since this is
# what a UK-based deployment would realistically use.

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "eu-west-2" # London
}

variable "secondary_region" {
  description = "Secondary AWS region"
  type        = string
  default     = "eu-west-1" # Ireland
}

# --- Networking ----------------------------------------------------------

variable "primary_vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "secondary_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

# --- EC2 -------------------------------------------------------------------
# Real AMIs are region-specific. These defaults are Amazon Linux 2023 IDs
# that were valid at time of writing for eu-west-2 / eu-west-1 — swap for
# current ones if you ever point this at real AWS. LocalStack does not
# validate that the AMI actually exists, so any string works for the mock.

variable "ami_ids" {
  description = "Map of region -> AMI ID"
  type        = map(string)
  default = {
    "eu-west-2" = "ami-0e8d4a1d09f0266f4"
    "eu-west-1" = "ami-0ec7f9846da6b0f01"
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the instances. Lock this down in real use."
  type        = string
  default     = "0.0.0.0/0" # fine for a local mock, NOT fine for real AWS
}

# --- RDS SQL Server ---------------------------------------------------------

variable "db_username" {
  description = "Master username for the SQL Server instance"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for the SQL Server instance. Mock value only — never commit real secrets."
  type        = string
  default     = "MockPassw0rd!2026"
  sensitive   = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.small"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}
