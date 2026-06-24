output "primary_vpc_id" {
  value = module.vpc_primary.vpc_id
}

output "secondary_vpc_id" {
  value = module.vpc_secondary.vpc_id
}

output "ec2_primary_id" {
  value = module.ec2_primary.instance_id
}

output "ec2_secondary_id" {
  value = module.ec2_secondary.instance_id
}

output "s3_bucket" {
  value = module.s3.bucket_id
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "iam_role" {
  value = module.iam.role_name
}
