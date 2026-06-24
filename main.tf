# ============================================================================
# PRIMARY REGION (eu-west-2 / London)
# ============================================================================

module "vpc_primary" {
  source   = "./modules/vpc"
  name     = "${var.project_name}-primary"
  vpc_cidr = var.primary_vpc_cidr
  azs      = ["${var.primary_region}a", "${var.primary_region}b"]
}

module "s3" {
  source      = "./modules/s3"
  bucket_name = "${var.project_name}-${var.environment}-bucket"
}

module "iam" {
  source        = "./modules/iam"
  name          = var.project_name
  s3_bucket_arn = module.s3.bucket_arn
}

module "ec2_primary" {
  source                 = "./modules/ec2"
  name                   = "${var.project_name}-primary"
  vpc_id                 = module.vpc_primary.vpc_id
  subnet_id              = module.vpc_primary.public_subnet_ids[0]
  ami_id                 = var.ami_ids[var.primary_region]
  instance_type          = var.instance_type
  allowed_ssh_cidr       = var.allowed_ssh_cidr
  instance_profile_name  = module.iam.instance_profile_name
}

module "rds" {
  source                     = "./modules/rds-sqlserver"
  name                       = var.project_name
  vpc_id                     = module.vpc_primary.vpc_id
  private_subnet_ids         = module.vpc_primary.private_subnet_ids
  allowed_security_group_id  = module.ec2_primary.security_group_id
  username                   = var.db_username
  password                   = var.db_password
  instance_class             = var.db_instance_class
  allocated_storage          = var.db_allocated_storage
}

# ============================================================================
# SECONDARY REGION (eu-west-1 / Ireland)
# Everything here uses the `aws.secondary` provider alias. Note the
# `instance_profile_name` reuse: IAM is a global service in real AWS, so the
# same role/profile from the primary region is valid here too. (LocalStack
# treats IAM per-account rather than truly globally, but for this mock it
# resolves fine since both providers point at the same container.)
# ============================================================================

module "vpc_secondary" {
  source = "./modules/vpc"
  providers = {
    aws = aws.secondary
  }
  name     = "${var.project_name}-secondary"
  vpc_cidr = var.secondary_vpc_cidr
  azs      = ["${var.secondary_region}a", "${var.secondary_region}b"]
}

module "ec2_secondary" {
  source = "./modules/ec2"
  providers = {
    aws = aws.secondary
  }
  name                   = "${var.project_name}-secondary"
  vpc_id                 = module.vpc_secondary.vpc_id
  subnet_id              = module.vpc_secondary.public_subnet_ids[0]
  ami_id                 = var.ami_ids[var.secondary_region]
  instance_type          = var.instance_type
  allowed_ssh_cidr       = var.allowed_ssh_cidr
  instance_profile_name  = module.iam.instance_profile_name
}
