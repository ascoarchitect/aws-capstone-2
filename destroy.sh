#!/bin/bash

# AWS Kubernetes Capstone 2 - Destroy Script
# This script cleans up all resources created by the project
clear
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

print_header() {
    echo -e "${BLUE}======================================"
    echo -e "$1"
    echo -e "======================================${NC}"
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
    
    # Run command in background and capture exit code
    eval "$command" >/dev/null 2>&1 &
    local pid=$!
    
    # Show spinner while command runs
    spinner $pid
    
    # Wait for command to complete and get exit code
    wait $pid
    local exit_code=$?
    
    # Clear the line and show result
    printf "\r"
    if [ $exit_code -eq 0 ]; then
        print_status "$message"
    else
        print_error "$message (failed)"
        return $exit_code
    fi
}

print_header "AWS Kubernetes Capstone 2 - Destroy"

# Confirmation prompt
echo -e "${RED}WARNING: This will delete all resources created by this project!${NC}"
echo "This includes:"
echo "  - EKS cluster and all nodes"
echo "  - Load balancer"
echo "  - ECR repository and images"
echo "  - All Kubernetes resources"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    print_info "Destruction cancelled"
    exit 0
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
CLUSTER_NAME="dos-games"
NAMESPACE="dos-game"
REPO_NAME="dos-games"
STATS_REPO_NAME="dos-games-stats"

# Delete Kubernetes resources
print_info "Deleting Kubernetes resources..."
if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
    # Delete all resources in namespace
    run_with_spinner "Deleting all resources in namespace..." "kubectl delete all --all -n $NAMESPACE --timeout=60s"
    
    # Delete Istio configurations
    run_with_spinner "Deleting Istio configurations..." "kubectl delete vs,dr,gw,pa,ap,telemetry --all -n $NAMESPACE --timeout=60s"
    
    # Delete namespace
    run_with_spinner "Deleting namespace..." "kubectl delete namespace $NAMESPACE --timeout=60s"
    print_status "Kubernetes resources deleted"
else
    print_info "Namespace not found, skipping Kubernetes cleanup"
fi

# Delete Istio observability configurations
print_info "Deleting Istio observability configurations..."
run_with_spinner "Deleting observability gateway..." "kubectl delete vs,gw observability-gateway kiali-vs grafana-vs jaeger-vs -n istio-system --timeout=60s || true"

# Uninstall Istio
print_info "Uninstalling Istio..."
if kubectl get namespace istio-system >/dev/null 2>&1; then
    run_with_spinner "Uninstalling Istio..." "istioctl uninstall --purge -y"
    run_with_spinner "Deleting Istio namespace..." "kubectl delete namespace istio-system --timeout=120s || true"
    print_status "Istio uninstalled"
else
    print_info "Istio not found"
fi

# Delete EKS cluster
print_info "Checking for EKS cluster..."
if eksctl get cluster --name $CLUSTER_NAME --region $REGION >/dev/null 2>&1; then
    print_info "Deleting EKS cluster (this will take 10-15 minutes)..."
    run_with_spinner "Deleting EKS cluster..." "eksctl delete cluster --name $CLUSTER_NAME --region $REGION --wait"
    print_status "EKS cluster deleted"
else
    print_info "EKS cluster not found"
fi

# Delete ECR images
print_info "Deleting ECR images..."
if aws ecr describe-repositories --repository-names $REPO_NAME --region $REGION >/dev/null 2>&1; then
    # List all images
    IMAGES=$(aws ecr list-images --repository-name $REPO_NAME --region $REGION --query 'imageIds[*]' --output json)
    
    if [ "$IMAGES" != "[]" ]; then
        # Delete all images
        run_with_spinner "Deleting ECR images..." "aws ecr batch-delete-image --repository-name $REPO_NAME --region $REGION --image-ids '$IMAGES'"
        print_status "ECR images deleted"
    else
        print_info "No images found in repository"
    fi
else
    print_info "ECR repository not found"
fi

# Delete ECR repository
print_info "Deleting games ECR repository..."
if aws ecr describe-repositories --repository-names $REPO_NAME --region $REGION >/dev/null 2>&1; then
    run_with_spinner "Deleting games ECR repository..." "aws ecr delete-repository --repository-name $REPO_NAME --region $REGION --force"
    print_status "Games ECR repository deleted"
else
    print_info "Games ECR repository already deleted"
fi

# Delete stats API ECR repository
print_info "Deleting stats API ECR repository..."
if aws ecr describe-repositories --repository-names $STATS_REPO_NAME --region $REGION >/dev/null 2>&1; then
    run_with_spinner "Deleting stats API ECR repository..." "aws ecr delete-repository --repository-name $STATS_REPO_NAME --region $REGION --force"
    print_status "Stats API ECR repository deleted"
else
    print_info "Stats API ECR repository already deleted"
fi

# Clean up local Docker images
print_info "Cleaning up local Docker images..."
run_with_spinner "Removing local Docker images..." "sudo docker rmi dos-games:doom dos-games:civ dos-games-stats:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:doom $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:civ $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$STATS_REPO_NAME:latest 2>/dev/null || true"
print_status "Local Docker images cleaned"

# Remove kubeconfig context
print_info "Removing kubeconfig context..."
run_with_spinner "Cleaning kubeconfig..." "kubectl config delete-context arn:aws:eks:$REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME && kubectl config delete-cluster arn:aws:eks:$REGION:$ACCOUNT_ID:cluster/$CLUSTER_NAME 2>/dev/null || true"
print_status "kubeconfig cleaned"

print_header "Cleanup Complete!"
echo ""
print_info "All resources have been deleted"
print_info "To redeploy, run ./bootstrap.sh followed by ./deploy.sh"