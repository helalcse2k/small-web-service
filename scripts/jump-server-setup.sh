#!/bin/bash
# =============================================================================
# jump-server-setup.sh
# One-shot setup script for Ubuntu jump server (DevOps Assessment)
# Installs: Docker, AWS CLI v2, Terraform, kubectl, Minikube, Git, Helm
# Usage: bash jump-server-setup.sh
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
section() { echo -e "\n${GREEN}========================================${NC}"; \
            echo -e "${GREEN}  $*${NC}"; \
            echo -e "${GREEN}========================================${NC}"; }

# ── Versions (pin for reproducibility) ───────────────────────────────────────
TERRAFORM_VERSION="1.9.8"
KUBECTL_VERSION="v1.31.3"
HELM_VERSION="v3.16.3"

CURRENT_USER="${SUDO_USER:-$USER}"

section "1. System Update & Base Packages"
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y \
  git curl wget unzip jq \
  apt-transport-https ca-certificates gnupg \
  lsb-release software-properties-common \
  build-essential net-tools htop
info "Base packages installed"

section "2. Docker Engine"
# Remove any old versions.
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Add Docker's official GPG key and repo
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker
sudo systemctl enable --now docker

# Add current user to docker group (no sudo needed)
sudo usermod -aG docker "$CURRENT_USER"
info "Docker installed: $(docker --version)"

section "3. AWS CLI v2"
cd /tmp
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip
sudo ./aws/install --update
rm -rf awscliv2.zip aws/
info "AWS CLI installed: $(aws --version)"

section "4. Terraform ${TERRAFORM_VERSION}"
cd /tmp
curl -fsSL \
  "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
  -o terraform.zip
unzip -q terraform.zip
sudo install -o root -g root -m 0755 terraform /usr/local/bin/terraform
rm -f terraform.zip terraform
info "Terraform installed: $(terraform --version | head -1)"

section "5. kubectl ${KUBECTL_VERSION}"
curl -fsSL \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  -o /tmp/kubectl
sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm -f /tmp/kubectl
info "kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

section "6. Minikube (latest)"
curl -fsSL \
  https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  -o /tmp/minikube
sudo install -o root -g root -m 0755 /tmp/minikube /usr/local/bin/minikube
rm -f /tmp/minikube
info "Minikube installed: $(minikube version --short)"

section "7. Helm ${HELM_VERSION}"
cd /tmp
curl -fsSL \
  "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
  -o helm.tar.gz
tar -zxf helm.tar.gz
sudo install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm
rm -rf helm.tar.gz linux-amd64/
info "Helm installed: $(helm version --short)"

section "8. conntrack (required by Minikube none driver)"
sudo apt-get install -y conntrack socat

section "9. Shell Utilities — shellcheck, hadolint"
# shellcheck (for linting scripts)
sudo apt-get install -y shellcheck
info "shellcheck: $(shellcheck --version | head -2)"

# hadolint (for linting Dockerfile)
HADOLINT_VERSION="v2.12.0"
sudo curl -fsSL \
  "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-x86_64" \
  -o /usr/local/bin/hadolint
sudo chmod +x /usr/local/bin/hadolint
info "hadolint: $(hadolint --version)"

section "10. Git Configuration"
git --version
info "Git ready. Configure your name/email after login:"
warn "  git config --global user.name  'Your Name'"
warn "  git config --global user.email 'you@example.com'"

section "11. Create Working Directory"
mkdir -p ~/devops-task
info "Working directory: ~/devops-task"

section "✅ Installation Complete — Summary"
echo ""
echo "  Tool         Version"
echo "  -----------  ----------------------------"
echo "  Docker       $(docker --version | awk '{print $3}' | tr -d ',')"
echo "  Docker Compose $(docker compose version | awk '{print $4}')"
echo "  AWS CLI      $(aws --version | awk '{print $1}' | cut -d/ -f2)"
echo "  Terraform    $(terraform --version | head -1 | awk '{print $2}')"
echo "  kubectl      $(kubectl version --client -o json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["clientVersion"]["gitVersion"])' 2>/dev/null || echo $KUBECTL_VERSION)"
echo "  Minikube     $(minikube version --short)"
echo "  Helm         $(helm version --short)"
echo "  shellcheck   $(shellcheck --version | grep version | awk '{print $2}')"
echo "  hadolint     $(hadolint --version | awk '{print $NF}')"
echo ""
warn "⚠️  IMPORTANT: Log out and SSH back in for Docker group to take effect!"
warn "   Run: exit"
warn "   Then: ssh -i key.pem ubuntu@<IP>"
warn ""
warn "   After re-login, run: docker ps   (should work without sudo)"
