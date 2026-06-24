# Mock AWS infra with Terraform + Claude Code

A working example of VPCs (2 regions), IAM, EC2, S3, and a SQL Server RDS
instance, built so you can practice the **Claude Code → Terraform → AWS**
workflow without an AWS account. "AWS" here is [LocalStack](https://www.localstack.cloud/),
a Docker container that emulates the AWS APIs on your own machine.

## 1. Prerequisites

- Docker (for LocalStack)
- Terraform >= 1.6 (`terraform -version`)
- Optional but recommended: `pip install terraform-local` — gives you a
  `tflocal` command that's a drop-in replacement for `terraform init/plan/apply`
  and auto-configures the LocalStack endpoints for you
- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) installed:
  ```bash
  curl -fsSL https://claude.ai/install.sh | bash
  # or: npm install -g @anthropic-ai/claude-code
  ```

## 2. Start the mock backend

```bash
make up
```

This starts LocalStack on `localhost:4566` — every single AWS API call
(EC2, IAM, S3, RDS, STS) gets intercepted there instead of going anywhere
near real AWS. `MSSQL_ACCEPT_EULA=Y` in `docker-compose.yml` is what allows
LocalStack to spin up the SQL Server engine.

## 3. Run Terraform against it

```bash
terraform init
terraform plan  -var-file=terraform.tfvars.example
terraform apply -var-file=terraform.tfvars.example
```

Or, if you installed `tflocal`, just substitute it for `terraform` in those
three commands and you can delete the manual `endpoints {}` blocks from
`providers.tf` — `tflocal` does that wiring for you.

You should see Terraform create: 2 VPCs (with public/private subnets, an
IGW, and route tables), an IAM role + instance profile, 2 EC2 instances (one
per region), an S3 bucket, and a SQL Server RDS instance — all inside the
LocalStack container, none of it real, none of it costing anything.

Check what got created:
```bash
pip install awscli-local   # gives you `awslocal`, a pre-configured aws-cli
awslocal ec2 describe-instances --region eu-west-2
awslocal s3 ls
awslocal rds describe-db-instances
```

Tear it down with `terraform destroy` (or `make destroy`), then `make down`
to stop LocalStack itself.

## 4. The actual point: using Claude Code on this

This is the part that's the same whether you're pointed at LocalStack or a
real AWS account — that's deliberate. The habits you build here transfer
directly.

**Start a session in the project root:**
```bash
cd aws-tf-mock-demo
claude
```

Claude Code reads `CLAUDE.md` automatically, so it already knows the stack,
the module layout, the conventions, and the LocalStack constraints before
you type anything.

**A realistic first session might look like this:**

> *You:* What does this infrastructure actually provision? Walk me through it.

Claude Code will read through `main.tf` and the modules and give you back an
architecture summary — this is the cheap way to sanity-check that it's
understood the project correctly before you ask it to change anything.

> *You:* Run `make up` then `terraform plan` and tell me if anything looks wrong before we apply.

This is the core loop: Claude Code runs the actual commands (you'll get a
permission prompt the first time it tries to run something — approve it, or
approve "for this session" if you don't want to be asked every time), reads
the output, and reports back in plain language instead of you scrolling
through a wall of plan output yourself.

> *You:* Add a third EC2 instance in eu-west-2 for a bastion host — only allow SSH from my IP, not 0.0.0.0/0.

Claude Code will typically: add a variable for your IP, extend the `ec2`
module call (or reuse it with different vars) in `main.tf`, run
`terraform fmt` and `terraform validate` itself, run `terraform plan`, and
show you the diff before asking whether to apply. This back-and-forth — ask,
review the plan, approve — is the same shape you'd use against a real
account, just with zero risk while you're learning it.

> *You:* The `terraform apply` failed on the RDS resource with [paste the error]. What's wrong?

Paste real error output and let it debug from the actual message rather than
guessing — for RDS specifically this often turns out to be a LocalStack
version/feature gap rather than a Terraform mistake (see `CLAUDE.md` →
"Known constraints").

**Other things worth trying once you're comfortable:**
- *"Add a NAT gateway so the private subnets have outbound internet access"* —
  good exercise in extending a module without breaking the existing call sites.
- *"Write a `tags` module so every resource gets a consistent set of tags,
  and refactor the existing modules to use it"* — a realistic refactor task.
- *"Explain what would need to change in `providers.tf` to point this at
  real AWS instead of LocalStack"* — useful before you ever actually do it.
- `/init` inside `claude` if you ever want it to regenerate `CLAUDE.md` from
  scratch after you've changed the project structure a lot.

## 5. Why this is a safe way to learn

- LocalStack is a Docker container with no relationship to your real AWS
  account — there's no credential anywhere in this repo that could
  accidentally create a real, billable resource.
- `terraform destroy` here is free to run as many times as you like.
- The habits that matter for real infra work — reading the plan before
  approving an apply, scoping IAM policies to specific resources rather than
  `"*"`, keeping state somewhere durable, not committing real secrets — are
  all modeled in this repo even though the backend is fake. When you do move
  to a real account, the only things that change are `providers.tf` (drop
  the LocalStack endpoints, use real credentials) and probably the backend
  block (move state to a real S3 bucket + DynamoDB lock table instead of
  local disk).

## 6. Moving to real AWS later (not yet — just so you know the shape of it)

1. Remove the `endpoints {}` blocks and the `skip_*`/`s3_use_path_style`
   lines from both `provider "aws"` blocks in `providers.tf`.
2. Set up real credentials (AWS SSO / `aws configure` / an assumed role) —
   never hardcode them in `.tf` files.
3. Move the `backend "local"` block to `backend "s3"` pointing at a bucket +
   lock table you provision once, separately, before this project's state
   needs to live anywhere.
4. Update `var.ami_ids` to current, real AMI IDs for each region.
5. Tighten `allowed_ssh_cidr` to your actual IP, and reconsider
   `skip_final_snapshot` / `deletion_protection` on the RDS instance.
6. Run `terraform plan` and read every single line before the first real
   `apply`.
