# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is
A Terraform project provisioning a small multi-region AWS footprint —
VPCs, IAM, EC2, S3, and a SQL Server RDS instance — designed to run against
**LocalStack** (a local AWS emulator) instead of a real AWS account. Nothing
here should ever touch real AWS or real credentials.

## Stack
- Terraform >= 1.6, AWS provider ~> 5.0
- LocalStack (Docker) standing in for AWS
- Two regions: eu-west-2 (primary) and eu-west-1 (secondary), via the
  `aws.secondary` provider alias

## Layout
- `main.tf` / `variables.tf` / `outputs.tf` / `providers.tf` — root module
- `modules/vpc` — VPC, subnets, IGW, route table (called once per region)
- `modules/iam` — EC2 role + instance profile, least-privilege S3 read policy
- `modules/ec2` — security group + instance (called once per region)
- `modules/s3` — bucket with versioning, encryption, public access block
- `modules/rds-sqlserver` — DB subnet group, security group, sqlserver-ex instance

## Commands

```bash
make up        # start LocalStack and wait for healthy
make down      # stop LocalStack
make init      # terraform init (run once, or after provider changes)
make validate  # terraform fmt + terraform validate
make plan      # validate then terraform plan
make apply     # validate then terraform apply
make destroy   # terraform destroy
make logs      # tail LocalStack container logs (useful when apply fails on RDS)
```

Plan and apply use `terraform.tfvars.example` for variable values:
```bash
terraform plan  -var-file=terraform.tfvars.example
terraform apply -var-file=terraform.tfvars.example
```

If `tflocal` (from `pip install terraform-local`) is installed, prefer it
over plain `terraform` for plan/apply/destroy — it auto-injects the
LocalStack endpoints so we don't have to maintain the `endpoints {}` block
by hand.

Inspect created resources with `awslocal` (from `pip install awscli-local`):
```bash
awslocal ec2 describe-instances --region eu-west-2
awslocal s3 ls
awslocal rds describe-db-instances
```

## Module architecture

**Region-aware modules** (called once per region with a `providers` block):
- `vpc` — subnets use `cidrsubnet(vpc_cidr, 8, 0-1)` for public, `10-11` for private
- `ec2` — one instance per region, placed in `public_subnet_ids[0]`

**Global/primary-only modules** (no provider alias, always use the default provider):
- `iam` — IAM is a global service; the same instance profile is reused by both EC2 modules
- `s3` — single bucket in primary region
- `rds-sqlserver` — single SQL Server Express instance in primary region, private subnets only

LocalStack persists state across Docker restarts via `PERSISTENCE=1` in
`docker-compose.yml` — it writes to `.localstack/` in the project root.
Neither `.localstack/` nor `terraform.tfstate` are gitignored by default;
exclude them from version control if you add a `.gitignore`.

## Conventions
- Every resource is tagged/named with `var.project_name` as a prefix.
- IAM policies are scoped to specific ARNs, never `"*"` resources — when
  adding new permissions, write a `data "aws_iam_policy_document"` rather
  than an inline JSON heredoc.
- Security groups reference other security groups by ID for service-to-service
  rules (see `modules/rds-sqlserver`), not by CIDR, except for the one
  internet-facing SSH rule.
- Each module is self-contained (its own provider requirement block) and
  takes only the inputs it needs — don't reach into root variables from
  inside a module.

## Known constraints of the mock
- No NAT gateway — private subnets have no outbound internet route.
- `skip_final_snapshot = true` / `deletion_protection = false` on RDS — fine
  for a throwaway mock, would be wrong defaults for a real production DB.
- `db_password` has a placeholder default in `terraform.tfvars.example` —
  this is for LocalStack only and must never be replaced with a real
  password in this repo. Real secrets belong in a secrets manager / CI
  secret store, referenced via a data source, never in tfvars.
- RDS SQL Server emulation in LocalStack is a newer feature area, more
  brittle than the EC2/S3/IAM emulation, and free-tier vs LocalStack-Pro
  availability has shifted between releases — if `apply` fails specifically
  on the `aws_db_instance` resource, check LocalStack's current RDS docs
  before assuming the Terraform code is wrong. Run `make logs` for the raw
  LocalStack error.

## When asked to extend this project
- Adding a third region: copy the `_secondary` module block pattern in
  `main.tf`, add a third `provider "aws" { alias = "tertiary" ... }` in
  `providers.tf`, and add the region to `var.ami_ids`.
- Adding a new AWS resource type: check whether LocalStack supports it
  before writing Terraform for it — not everything in the AWS provider is
  emulated. The services currently enabled in `docker-compose.yml` are
  `ec2,iam,rds,s3,sts`; adding a new service requires updating `SERVICES=`
  there and restarting LocalStack.
