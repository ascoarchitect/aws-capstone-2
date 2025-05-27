#!/bin/bash

# AWS Kubernetes Capstone 2 - Bootstrap Script
# This script sets up the development environment with all required tools
clear
set -e

echo "======================================"
echo "AWS Kubernetes Capstone 2 - Bootstrap"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

# Animation functions
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to run command with animation
run_with_spinner() {
    local message="$1"
    local command="$2"
    
    echo -n -e "${BLUE}[⚡]${NC} $message"
    
    # Temporarily disable 'set -e' to handle errors gracefully
    set +e
    
    # Create temporary files for output
    local stdout_file=$(mktemp)
    local stderr_file=$(mktemp)
    eval "$command" >"$stdout_file" 2>"$stderr_file" &
    local pid=$!
    
    # Show spinner while command runs
    spinner $pid
    
    # Wait for command to complete and get exit code
    wait $pid
    local exit_code=$?
    
    # Re-enable 'set -e'
    set -e
    
    # Clear the line and show result
    printf "\r"
    if [ $exit_code -eq 0 ]; then
        print_status "$message"
    else
        print_error "$message (failed)"
        if [ -f "$stderr_file" ] && [ -s "$stderr_file" ]; then
            echo -e "${RED}Error details:${NC}"
            cat "$stderr_file" | head -10  # Show first 10 lines of error
            echo ""
        fi
        print_error "Bootstrap failed. Exiting..."
        
        # Clean up temporary files before exit
        rm -f "$stdout_file" "$stderr_file"
        exit 1
    fi
    
    # Clean up temporary files
    rm -f "$stdout_file" "$stderr_file"
}

# Update package manager
run_with_spinner "Updating package manager..." "sudo yum update -y -q"

# Install essential tools first
run_with_spinner "Installing essential tools..." "sudo yum install -y wget unzip"

# Install Docker
if command_exists docker; then
    print_status "Docker is already installed"
else
    print_info "Installing Docker..."
    # Install Docker using Amazon Linux package manager
    run_with_spinner "Installing Docker package..." "sudo yum install -y docker"
    run_with_spinner "Starting Docker service..." "sudo systemctl start docker"
    run_with_spinner "Enabling Docker service..." "sudo systemctl enable docker"
    run_with_spinner "Adding user to docker group..." "sudo usermod -aG docker $USER"
    print_status "Docker installed"
    print_info "You may need to log out and back in for Docker permissions"
fi

# Install AWS CLI v2
if command_exists aws; then
    print_status "AWS CLI is already installed"
else
    print_info "Installing AWS CLI v2..."
    run_with_spinner "Downloading AWS CLI..." "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
    run_with_spinner "Installing unzip..." "sudo yum install -y unzip"
    run_with_spinner "Extracting AWS CLI..." "unzip -q awscliv2.zip"
    run_with_spinner "Installing AWS CLI..." "sudo ./aws/install"
    run_with_spinner "Cleaning up installation files..." "rm -rf awscliv2.zip aws/"
    print_status "AWS CLI installed"
fi

# Install kubectl
if command_exists kubectl; then
    print_status "kubectl is already installed"
else
    print_info "Installing kubectl..."
    run_with_spinner "Downloading kubectl..." "curl -LO 'https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl'"
    run_with_spinner "Installing kubectl..." "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
    run_with_spinner "Cleaning up kubectl download..." "rm kubectl"
    print_status "kubectl installed"
fi

# Install eksctl
if command_exists eksctl; then
    print_status "eksctl is already installed"
else
    print_info "Installing eksctl..."
    run_with_spinner "Downloading and installing eksctl..." "curl --silent --location 'https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz' | tar xz -C /tmp"
    run_with_spinner "Moving eksctl to /usr/local/bin..." "sudo mv /tmp/eksctl /usr/local/bin"
    print_status "eksctl installed"
fi

# Install Istio CLI
if command_exists istioctl; then
    CURRENT_VERSION=$(istioctl version --client --short 2>/dev/null | head -1)
    print_status "Istio CLI is already installed: $CURRENT_VERSION"
else
    print_info "Installing Istio CLI..."
    ISTIO_VERSION="1.26.0"
    cd /tmp
    run_with_spinner "Downloading Istio $ISTIO_VERSION..." "curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -"
    run_with_spinner "Installing istioctl..." "sudo mv istio-$ISTIO_VERSION/bin/istioctl /usr/local/bin/"
    run_with_spinner "Cleaning up Istio download..." "rm -rf istio-$ISTIO_VERSION"
    cd - >/dev/null
    print_status "Istio CLI installed"
    print_info "Version: $(istioctl version --client --short 2>/dev/null | head -1)"
fi

# Verify AWS credentials
print_info "Checking AWS credentials..."
if aws sts get-caller-identity >/dev/null 2>&1; then
    print_status "AWS credentials configured"
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    print_info "Account: $ACCOUNT_ID"
    print_info "Region: $REGION"
else
    print_error "AWS credentials not configured"
    print_info "Please run: aws configure"
    exit 1
fi

# Create ECR repositories
print_info "Setting up ECR repositories..."
REPO_NAME="dos-games"
STATS_REPO_NAME="dos-games-stats"

if aws ecr describe-repositories --repository-names $REPO_NAME --region $REGION >/dev/null 2>&1; then
    print_status "Game ECR repository already exists"
else
    run_with_spinner "Creating game ECR repository..." "aws ecr create-repository --repository-name $REPO_NAME --region $REGION"
fi

if aws ecr describe-repositories --repository-names $STATS_REPO_NAME --region $REGION >/dev/null 2>&1; then
    print_status "Stats API ECR repository already exists"
else
    run_with_spinner "Creating stats API ECR repository..." "aws ecr create-repository --repository-name $STATS_REPO_NAME --region $REGION"
fi

# Get ECR login token
run_with_spinner "Logging into ECR..." "aws ecr get-login-password --region $REGION | sudo docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# Build and push Docker images
print_info "Building and pushing Docker images..."
echo ""

# Build stats API image first
print_info "Building stats API image..."
cd docker/stats-api
run_with_spinner "Building stats API Docker image..." "sudo docker build --platform linux/amd64 -t dos-games-stats:latest . --quiet"
run_with_spinner "Tagging stats API image..." "sudo docker tag dos-games-stats:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/dos-games-stats:latest"
run_with_spinner "Pushing stats API image to ECR..." "sudo docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/dos-games-stats:latest"
cd ../..

# Build game images
print_info "Building game images..."
cd docker/doom
run_with_spinner "Building DOOM Docker image..." "sudo docker build --platform linux/amd64 -t $REPO_NAME:doom . --quiet"
cd ../..

cd docker/civ
run_with_spinner "Building Civilization Docker image..." "sudo docker build --platform linux/amd64 -t $REPO_NAME:civ . --quiet"
cd ../..

# Tag and push images to ECR
print_info "Pushing images to ECR..."
run_with_spinner "Tagging and pushing DOOM image..." "sudo docker tag $REPO_NAME:doom $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:doom && sudo docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:doom"
run_with_spinner "Tagging and pushing Civilization image..." "sudo docker tag $REPO_NAME:civ $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:civ && sudo docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:civ"

echo ""
print_status "All Docker images built and pushed to ECR successfully!"

echo ""
echo "======================================"
echo -e "${GREEN}Bootstrap completed successfully!${NC}"
echo "======================================"
echo ""
print_info "Environment setup complete:"
echo "   ✓ All required tools installed (Docker, AWS CLI, kubectl, eksctl, Istio CLI v1.26.0)"
echo "   ✓ Docker images built and pushed to ECR"
echo "   ✓ AWS credentials verified"
echo ""
echo "Next steps:"
echo "1. Run ./deploy.sh doom  # To deploy EKS cluster with DOOM"
echo "2. Run ./deploy.sh civ   # To deploy EKS cluster with Civilization"
echo "3. Run ./deploy.sh switch # To switch between games (blue/green deployment)"
echo ""
print_info "Docker images built and pushed to ECR:"
echo "   - $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:doom"
echo "   - $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:civ"
echo "   - $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$STATS_REPO_NAME:latest"
echo ""
print_info "Ready for Istio Service Mesh deployment with observability tools!"