.PHONY: up down init plan apply destroy fmt validate logs

# Start the mock AWS backend
up:
	docker-compose up -d
	@echo "Waiting for LocalStack to be healthy..."
	@until curl -sf http://localhost:4566/_localstack/health > /dev/null; do sleep 2; done
	@echo "LocalStack is up on http://localhost:4566"

down:
	docker-compose down

logs:
	docker-compose logs -f localstack

# Standard Terraform commands. If you installed the `tflocal` wrapper
# (pip install terraform-local), you can swap `terraform` for `tflocal`
# below and drop the manual endpoints block from providers.tf entirely —
# tflocal injects them for you automatically.
init:
	terraform init

fmt:
	terraform fmt -recursive

validate: fmt
	terraform validate

plan: validate
	terraform plan

apply: validate
	terraform apply

destroy:
	terraform destroy
