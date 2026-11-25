#!/bin/bash
# =============================================================================
# configure-aws-and-clone.sh
# Run AFTER jump-server-setup.sh and after re-login
# Configures AWS credentials and clones the solution repo
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
section() { echo -e "\n${GREEN}========================================${NC}"; \
            echo -e "${GREEN}  $*${NC}"; \
            echo -e "${GREEN}========================================${NC}"; }

section "1. Verify Docker works without sudo"
docker ps
info "Docker group OK"

section "2. Configure AWS CLI"
warn "You will be prompted for 4 values:"
warn "  Access Key ID     → from your AWS IAM user"
warn "  Secret Access Key → from your AWS IAM user"
warn "  Region            → us-east-1"
warn "  Output format     → json"
echo ""
aws configure

# Verify
info "Verifying AWS credentials..."
aws sts get-caller-identity
info "AWS credentials OK"

section "3. Clone your GitHub repository"
warn "Enter your GitHub repo URL (e.g. https://github.com/username/devops-task.git):"
read -r REPO_URL

cd ~/devops-task || exit 1
git clone "$REPO_URL" app
cd app || exit 1
info "Repo cloned to ~/devops-task/app"

section "4. Set up SSH key for EC2 deploy target"
warn "Paste your EC2 SSH private key content below."
warn "Press ENTER then Ctrl+D when done:"
mkdir -p ~/.ssh
cat > ~/.ssh/devops-task-key.pem
chmod 400 ~/.ssh/devops-task-key.pem
info "SSH key saved to ~/.ssh/devops-task-key.pem"

section "✅ Ready! Next steps:"
echo ""
echo "  1. Update Terraform variables:"
echo "     cd ~/devops-task/app/terraform"
echo "     nano staging.tfvars   ← set ecr_repository and key_name"
echo "     nano main.tf          ← set S3 bucket name"
echo ""
echo "  2. Run Terraform:"
echo "     terraform init"
echo "     terraform plan  -var-file=staging.tfvars"
echo "     terraform apply -var-file=staging.tfvars"
echo ""
echo "  3. After apply, copy outputs to GitHub secrets:"
echo "     terraform output"
