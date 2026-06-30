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

# ── Lambda (S3 event handler) ──────────────────────────────────────────────────
# Deploys a Python function that logs every S3 ObjectCreated event.
# The aws_s3_bucket_notification below wires S3 → this function.
# The aws_lambda_permission inside the module lets S3 call it.

module "lambda" {
  source        = "./modules/lambda"
  name          = var.project_name
  s3_bucket_id  = module.s3.bucket_id
  s3_bucket_arn = module.s3.bucket_arn
}

# ── S3 replica bucket (secondary region) ──────────────────────────────────────
# Cross-region replication destination — lives in eu-west-1.
# The replication IAM role + configuration are in replication.tf.

module "s3_replica" {
  source = "./modules/s3-replica"
  providers = {
    aws = aws.secondary
  }
  bucket_name = "${var.project_name}-${var.environment}-replica"
}

# ── S3 event notification → Lambda ────────────────────────────────────────────
# Kept at root level (not inside the s3 module) because it depends on both
# module.s3 and module.lambda — putting it inside either module would create
# a circular dependency.

resource "aws_s3_bucket_notification" "upload_trigger" {
  bucket = module.s3.bucket_id

  lambda_function {
    lambda_function_arn = module.lambda.function_arn
    events              = ["s3:ObjectCreated:*"]
  }

  # The lambda permission must exist before S3 will accept the notification config.
  depends_on = [module.lambda]
}

# ── Grafana dashboard ──────────────────────────────────────────────────────────
# Provisions a CloudWatch datasource + 4-panel dashboard inside the Grafana
# container. Open http://localhost:3000 (admin / admin) after apply.

module "grafana" {
  source        = "./modules/grafana"
  function_name = module.lambda.function_name
}

module "iam" {
  source        = "./modules/iam"
  name          = var.project_name
  s3_bucket_arn = module.s3.bucket_arn
}

module "ec2_primary" {
  source                = "./modules/ec2"
  name                  = "${var.project_name}-primary"
  vpc_id                = module.vpc_primary.vpc_id
  subnet_id             = module.vpc_primary.public_subnet_ids[0]
  ami_id                = var.ami_ids[var.primary_region]
  instance_type         = var.instance_type
  allowed_ssh_cidr      = var.allowed_ssh_cidr
  instance_profile_name = module.iam.instance_profile_name
}

module "rds" {
  source                    = "./modules/rds-sqlserver"
  name                      = var.project_name
  vpc_id                    = module.vpc_primary.vpc_id
  private_subnet_ids        = module.vpc_primary.private_subnet_ids
  allowed_security_group_id = module.ec2_primary.security_group_id
  username                  = var.db_username
  password                  = var.db_password
  instance_class            = var.db_instance_class
  allocated_storage         = var.db_allocated_storage
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
  name                  = "${var.project_name}-secondary"
  vpc_id                = module.vpc_secondary.vpc_id
  subnet_id             = module.vpc_secondary.public_subnet_ids[0]
  ami_id                = var.ami_ids[var.secondary_region]
  instance_type         = var.instance_type
  allowed_ssh_cidr      = var.allowed_ssh_cidr
  instance_profile_name = module.iam.instance_profile_name
}
