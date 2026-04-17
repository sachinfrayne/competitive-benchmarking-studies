.PHONY: terraform-init terraform-plan terraform-apply terraform-destroy

terraform-init:
	cd $(STACK_DIR)terraform && terraform init

terraform-plan: terraform-init
	cd $(STACK_DIR)terraform && terraform plan -var-file=$(REPO_ROOT)/secrets/terraform.tfvars

terraform-apply: terraform-init
	cd $(STACK_DIR)terraform && terraform apply -var-file=$(REPO_ROOT)/secrets/terraform.tfvars

terraform-destroy: terraform-init
	@echo >&2 "WARNING: This will delete ALL resources."
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ]
	cd $(STACK_DIR)terraform && terraform destroy -var-file=$(REPO_ROOT)/secrets/terraform.tfvars
