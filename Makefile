.PHONY: up down init plan apply destroy fmt validate logs venv pip-install test

VENV_DIR := .venv
PYTHON    := python3

venv:
	@test -d $(VENV_DIR) || $(PYTHON) -m venv $(VENV_DIR)
	@echo "venv ready at $(VENV_DIR)/ — activate with: source $(VENV_DIR)/bin/activate"

pip-install: venv
	$(VENV_DIR)/bin/pip install --quiet --upgrade pip
	$(VENV_DIR)/bin/pip install terraform-local awscli awscli-local
	@echo "tflocal and awslocal are installed inside $(VENV_DIR)/"

# Start the mock AWS backend
up:
	docker-compose up -d
	@echo "Waiting for LocalStack to be healthy..."
	@until curl -sf http://localhost:4566/_localstack/health > /dev/null; do sleep 2; done
	@echo "LocalStack is up on http://localhost:4566"
	@echo "Waiting for Grafana to be healthy..."
	@until curl -sf http://localhost:3000/api/health > /dev/null; do sleep 2; done
	@echo "Grafana is up on http://localhost:3000  (admin / admin)"

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

test: pip-install
	$(VENV_DIR)/bin/pip install --quiet -r tests/requirements.txt
	$(VENV_DIR)/bin/pytest tests/ -v
