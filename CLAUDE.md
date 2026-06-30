# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is
A Terraform project provisioning a small multi-region AWS footprint —
VPCs, IAM, EC2, S3, and a SQL Server RDS instance — designed to run against
**LocalStack** (a local AWS emulator) instead of a real AWS account. Nothing
here should ever touch real AWS or real credentials.

## Stack
- Terraform >= 1.6, AWS provider ~> 5.0, archive provider ~> 2.0, Grafana provider ~> 3.7
- LocalStack (Docker) standing in for AWS
- Grafana 11.0 (Docker) for the visible dashboard at `http://localhost:3000`
- Two regions: eu-west-2 (primary) and eu-west-1 (secondary), via the
  `aws.secondary` provider alias

## Layout
- `main.tf` / `variables.tf` / `outputs.tf` / `providers.tf` — root module
- `replication.tf` — IAM role + `aws_s3_bucket_replication_configuration` (primary → replica)
- `modules/vpc` — VPC, subnets, IGW, route table (called once per region)
- `modules/iam` — EC2 role + instance profile, least-privilege S3 read policy
- `modules/ec2` — security group + instance (called once per region)
- `modules/s3` — bucket with versioning, encryption, public access block
- `modules/s3-replica` — destination bucket for cross-region replication (secondary region)
- `modules/lambda` — execution role, `archive_file` zip, Lambda function, S3 invoke permission
- `modules/lambda/handler.py` — Python 3.12 handler that logs S3 ObjectCreated events
- `modules/grafana` — Grafana CloudWatch datasource + 4-panel dashboard (Invocations, Errors, Duration, Logs)
- `modules/rds-sqlserver` — DB subnet group, security group, sqlserver-ex instance
- `tests/` — pytest integration tests using boto3 against LocalStack

## Commands

```bash
make pip-install  # create .venv (if needed) and install tflocal + awslocal
make up           # start LocalStack and wait for healthy
make down         # stop LocalStack
make init         # terraform init (run once, or after provider changes)
make validate     # terraform fmt + terraform validate
make plan         # validate then terraform plan
make apply        # validate then terraform apply
make destroy      # terraform destroy
make logs         # tail LocalStack container logs (useful when apply fails on RDS)
make test         # run pytest integration tests against LocalStack (requires apply first)
```

**Python tools (`tflocal`, `awslocal`) must run inside the project venv.**
Always install via `make pip-install` (never a bare `pip install`) — it
creates `.venv/` if absent and installs into it. To use the tools
interactively, activate first:
```bash
source .venv/bin/activate
```

Plan and apply use `terraform.tfvars.example` for variable values:
```bash
terraform plan  -var-file=terraform.tfvars.example
terraform apply -var-file=terraform.tfvars.example
```

If `tflocal` is installed (via `make pip-install`), prefer it over plain
`terraform` for plan/apply/destroy — it auto-injects the LocalStack
endpoints so we don't have to maintain the `endpoints {}` block by hand.

Inspect created resources with `awslocal` (installed via `make pip-install`):
```bash
awslocal ec2 describe-instances --region eu-west-2
awslocal s3 ls
awslocal rds describe-db-instances
```

## Module architecture

**Region-aware modules** (called once per region with a `providers` block):
- `vpc` — subnets use `cidrsubnet(vpc_cidr, 8, 0-1)` for public, `10-11` for private
- `ec2` — one instance per region, placed in `public_subnet_ids[0]`
- `s3-replica` — destination bucket for cross-region replication, in the secondary region

**Global/primary-only modules** (no provider alias, always use the default provider):
- `iam` — IAM is a global service; the same instance profile is reused by both EC2 modules
- `s3` — single bucket in primary region (versioned, encrypted, no public access)
- `lambda` — Python function triggered by S3 ObjectCreated events; zipped at plan time via `archive_file`
- `rds-sqlserver` — single SQL Server Express instance in primary region, private subnets only

**Root-level resources** (in `replication.tf` and `main.tf`):
- `aws_iam_role.replication` + `aws_s3_bucket_replication_configuration` — kept at root because they reference both `module.s3` and `module.s3_replica`; putting them in either module would create a circular dependency
- `aws_s3_bucket_notification.upload_trigger` — same reasoning: depends on both `module.s3` and `module.lambda`

**Grafana** (`modules/grafana`):
- `grafana_data_source` — CloudWatch plugin configured with `endpoint = "http://localstack:4566"` and dummy credentials; uses the Docker Compose service name so Grafana can reach LocalStack from inside its own container
- `grafana_dashboard` — 4-panel dashboard declared in a single `jsonencode()` call; Terraform diffs the JSON so panel changes trigger a redeployment automatically

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

## Integration tests

Tests live in `tests/` and use `boto3` pointed at LocalStack. Run them with `make test` **after** `terraform apply`. They cover:
- Primary bucket: existence, versioning, encryption, public-access block
- Replica bucket: existence + versioning (required for replication to work)
- Replication config: rule exists, rule enabled, destination ARN matches replica bucket
- Event notification: Lambda notification configured, `s3:ObjectCreated:*` event wired
- Lambda: function exists, correct runtime, direct invocation returns `{statusCode: 200}`, batch processing
- Upload smoke: `PutObject` + `GetObject` round-trip, `VersionId` present on versioned bucket

`tests/conftest.py` holds the boto3 fixtures. The hardcoded `PROJECT_NAME`/`ENVIRONMENT` constants must match `terraform.tfvars.example`.

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
- Lambda in LocalStack Community runs functions in-process (no container
  isolation). `python3.12` runtime works; the handler is zipped locally by
  the `archive` provider so no upload to a real S3 bucket is needed.
- Grafana's CloudWatch datasource reaches LocalStack via the Docker Compose
  internal network (`http://localstack:4566`), not `localhost:4566`. The
  Terraform grafana provider runs on the host and reaches Grafana via
  `http://localhost:3000`. Dashboard panels may show "No data" until the
  Lambda is invoked at least once (run `make test` to generate data).
- S3 cross-region replication in LocalStack is emulated at the API level
  (the replication config is accepted and stored) but objects are NOT
  actually copied to the replica bucket in real time — the destination bucket
  exists for testing replication *configuration*, not replication *transfer*.
  In real AWS you would verify replication by uploading an object and waiting
  for it to appear in the destination bucket with a `ReplicationStatus` tag.

## When asked to extend this project
- Adding a third region: copy the `_secondary` module block pattern in
  `main.tf`, add a third `provider "aws" { alias = "tertiary" ... }` in
  `providers.tf`, and add the region to `var.ami_ids`.
- Adding a new AWS resource type: check whether LocalStack supports it
  before writing Terraform for it — not everything in the AWS provider is
  emulated. The services currently enabled in `docker-compose.yml` are
  `ec2,iam,lambda,logs,rds,s3,sts`; adding a new service requires updating
  `SERVICES=` there and restarting LocalStack.
- Adding more Lambda triggers: add another `lambda_function { ... }` block
  inside `aws_s3_bucket_notification.upload_trigger` in `main.tf`, or
  add an SQS/SNS destination by adding `queue { ... }` / `topic { ... }` blocks
  (add `sqs` or `sns` to SERVICES first).
- Adding a second Lambda function: create a new module call in `main.tf`
  (same pattern as `module "lambda"`) pointing at a different handler file.
  Each function needs its own `aws_lambda_permission` and its own entry in
  `aws_s3_bucket_notification`.
