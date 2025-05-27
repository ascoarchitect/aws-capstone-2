#!/bin/bash

# AWS Kubernetes Capstone 2 - Deploy Script
# This script deploys the DOS games application to EKS
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

# Check command line arguments
if [ $# -eq 0 ]; then
    print_error "No game specified"
    echo "Usage: $0 [doom|civ|switch]"
    echo "  doom   - Deploy with DOOM"
    echo "  civ    - Deploy with Civilization"
    echo "  switch - Switch between games (blue/green)"
    exit 1
fi

GAME=$1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)
CLUSTER_NAME="dos-games"
NAMESPACE="dos-game"

# Function to get current game
get_current_game() {
    kubectl get deployment game-deployment -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -o '[^:]*$' || echo "none"
}

# Handle switch command
if [ "$GAME" == "switch" ]; then
    CURRENT_GAME=$(get_current_game)
    if [ "$CURRENT_GAME" == "doom" ]; then
        GAME="civ"
    elif [ "$CURRENT_GAME" == "civ" ]; then
        GAME="doom"
    else
        print_error "No game currently deployed"
        exit 1
    fi
    print_info "Switching from $CURRENT_GAME to $GAME"
fi

# Validate game selection
if [ "$GAME" != "doom" ] && [ "$GAME" != "civ" ]; then
    print_error "Invalid game: $GAME"
    echo "Valid options: doom, civ, switch"
    exit 1
fi

print_header "AWS Kubernetes Capstone 2 - Deploy"
print_info "Deploying with game: $GAME"

# Check if cluster exists
print_info "Checking EKS cluster status..."
if eksctl get cluster --name $CLUSTER_NAME --region $REGION >/dev/null 2>&1; then
    print_status "EKS cluster exists"
else
    print_info "Creating EKS cluster (this will take 15-20 minutes)..."
    run_with_spinner "Creating EKS cluster..." "eksctl create cluster -f eks/cluster.yaml"
fi

# Update kubeconfig
run_with_spinner "Updating kubeconfig..." "aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION"

# Verify ECR repositories and images exist
print_info "Verifying ECR repositories and images..."
REPO_NAME="dos-games"
STATS_REPO_NAME="dos-games-stats"

# Check if repositories exist
if ! aws ecr describe-repositories --repository-names $REPO_NAME --region $REGION >/dev/null 2>&1; then
    print_error "Game ECR repository not found. Please run ./bootstrap.sh first"
    exit 1
fi

if ! aws ecr describe-repositories --repository-names $STATS_REPO_NAME --region $REGION >/dev/null 2>&1; then
    print_error "Stats API ECR repository not found. Please run ./bootstrap.sh first"
    exit 1
fi

# Check if required images exist
if ! aws ecr describe-images --repository-name $REPO_NAME --image-ids imageTag=$GAME --region $REGION >/dev/null 2>&1; then
    print_error "Game image ($GAME) not found in ECR. Please run ./bootstrap.sh first"
    exit 1
fi

if ! aws ecr describe-images --repository-name $STATS_REPO_NAME --image-ids imageTag=latest --region $REGION >/dev/null 2>&1; then
    print_error "Stats API image not found in ECR. Please run ./bootstrap.sh first"
    exit 1
fi

print_status "All required Docker images found in ECR"

# Login to ECR
run_with_spinner "Logging into ECR..." "aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# Apply storage class
run_with_spinner "Applying storage class..." "kubectl apply -f k8s/storage-class.yaml"

# Apply Kubernetes manifests
print_info "Applying Kubernetes manifests..."

# Function to substitute variables in k8s manifests and apply with spinner
substitute_and_apply() {
    local file=$1
    local message="$2"
    local temp_file="/tmp/$(basename $file)"
    
    # Substitute variables
    sed -e "s|\$ACCOUNT_ID|$ACCOUNT_ID|g" \
        -e "s|\$REGION|$REGION|g" \
        -e "s|\$GAME|$GAME|g" \
        -e "s|\$NAMESPACE|$NAMESPACE|g" \
        "$file" > "$temp_file"
    
    # Apply the substituted file with spinner
    run_with_spinner "$message" "kubectl apply -f $temp_file"
    
    # Clean up
    rm "$temp_file"
}

# Function to apply k8s manifest with spinner
apply_with_spinner() {
    local file=$1
    local message="$2"
    run_with_spinner "$message" "kubectl apply -f $file"
}

# Function to check if game is live and responding
check_game_live() {
    local url=$1
    local expected_game=$2
    local max_attempts=60
    local attempt=0
    
    print_info "Checking if $expected_game is live and responding..."
    
    while [ $attempt -lt $max_attempts ]; do
        # Check if URL is reachable and get the title to identify the game
        local response=$(curl -s --connect-timeout 5 --max-time 10 "http://$url" 2>/dev/null || echo "")
        
        if [ ! -z "$response" ]; then
            # Check if the response contains the expected game title
            if echo "$response" | grep -q -i "$expected_game" 2>/dev/null; then
                return 0  # Success
            elif echo "$response" | grep -q -i "doom\|civilization" 2>/dev/null; then
                # Game is responding but it's the wrong game (might be old deployment)
                print_info "Game is responding but showing wrong game, waiting for update..."
            else
                # Some response but not a game page
                print_info "LoadBalancer responding but game not ready yet..."
            fi
        fi
        
        printf "."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    return 1  # Failed
}

# Check if this is a game switch or initial deployment
CURRENT_GAME=$(get_current_game)
IS_SWITCH=false
if [ "$CURRENT_GAME" != "none" ] && [ "$CURRENT_GAME" != "$GAME" ]; then
    IS_SWITCH=true
    print_info "Detected game switch from $CURRENT_GAME to $GAME"
fi

if [ "$IS_SWITCH" = false ]; then
    # Initial deployment - deploy all components
    print_info "Performing initial deployment of all components..."
    
    # Create namespace
    apply_with_spinner "k8s/namespace.yaml" "Creating namespace..."

    # Apply ConfigMap
    apply_with_spinner "k8s/configmap.yaml" "Applying ConfigMap..."

    # Apply network policy
    apply_with_spinner "k8s/network-policy.yaml" "Applying network policy..."

    # Apply PVC
    apply_with_spinner "k8s/postgres-pvc.yaml" "Creating PVC..."

    # Apply secrets
    apply_with_spinner "k8s/postgres-secret.yaml" "Applying secrets..."

    # Deploy database (persistent - no variables needed)
    apply_with_spinner "k8s/database.yaml" "Deploying database..."

    # Wait for database to be ready
    print_info "Waiting for database to be ready..."
    run_with_spinner "Waiting for database deployment..." "kubectl wait --for=condition=available --timeout=300s deployment/postgres -n $NAMESPACE"

    # Deploy stats API (persistent - only needs ACCOUNT_ID and REGION)
    substitute_and_apply "k8s/stats-api.yaml" "Deploying stats API..."

    # Wait for stats API to be ready
    print_info "Waiting for stats API to be ready..."
    run_with_spinner "Waiting for stats API deployment..." "kubectl wait --for=condition=available --timeout=300s deployment/stats-api -n $NAMESPACE"

    # Apply game service (persistent)
    apply_with_spinner "k8s/game-service.yaml" "Applying game service..."

    # Apply HPAs (persistent)
    apply_with_spinner "k8s/game-hpa.yaml" "Applying game HPA..."
    apply_with_spinner "k8s/stats-api-hpa.yaml" "Applying stats API HPA..."
else
    # Game switch - only update the game deployment
    print_info "Performing blue/green game switch..."
fi

# Deploy/update game application (this happens for both initial deploy and switch)
substitute_and_apply "k8s/game-deployment.yaml" "Deploying game application..."

# Wait for game deployment to be ready
print_info "Waiting for game deployment to be ready..."
run_with_spinner "Waiting for game deployment..." "kubectl wait --for=condition=available --timeout=300s deployment/game-deployment -n $NAMESPACE"

# Get service URL
print_info "Waiting for LoadBalancer to be ready..."
for i in {1..60}; do
    URL=$(kubectl get svc game-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ ! -z "$URL" ]; then
        break
    fi
    sleep 5
done

if [ -z "$URL" ]; then
    print_error "LoadBalancer URL not available after 5 minutes"
    print_info "Check service status with: kubectl get svc -n $NAMESPACE"
else
    print_status "LoadBalancer is ready"
    
    # Check if the game is actually live and responding
    echo ""
    if check_game_live "$URL" "$GAME"; then
        echo ""
        print_status "$GAME is now live and responding!"
        print_status "DNS propagation completed successfully"
    else
        echo ""
        print_error "Game did not respond within 5 minutes"
        print_info "The deployment completed but the game may still be starting up"
        print_info "You can check manually at: http://$URL"
    fi
fi

# Display deployment information
if [ "$IS_SWITCH" = true ]; then
    print_header "Game Switch Complete!"
    echo ""
    print_info "Successfully switched from $CURRENT_GAME to $GAME"
    print_info "Database and Stats API remained running (no downtime)"
else
    print_header "Deployment Complete!"
    echo ""
    print_info "Architecture:"
    echo "  - Game Pods: 2 replicas (auto-scaling 2-5)"
    echo "  - Stats API: 2 replicas (auto-scaling 2-4)"
    echo "  - PostgreSQL: 1 replica with persistent storage"
fi
echo ""
print_info "Current game deployed: $GAME"
print_info "Namespace: $NAMESPACE"
echo ""

if [ ! -z "$URL" ]; then
    print_status "Application URL: http://$URL"
    echo ""
    if check_game_live "$URL" "$GAME" >/dev/null 2>&1; then
        print_info "✅ Game is confirmed live and responding"
    else
        print_info "⏳ Game may still be starting up - check the URL above"
    fi
else
    print_info "LoadBalancer URL not yet available"
fi

echo ""
print_info "Useful commands:"
echo "  kubectl get all -n $NAMESPACE           # View all resources"
echo "  kubectl get hpa -n $NAMESPACE           # View autoscaler status"
echo "  kubectl logs -n $NAMESPACE -l app=dos-game      # View game logs"
echo "  kubectl logs -n $NAMESPACE -l app=stats-api     # View API logs"
echo "  kubectl logs -n $NAMESPACE -l app=postgres      # View DB logs"
if [ "$GAME" == "doom" ]; then
    echo "  ./deploy.sh civ                          # Switch to Civilization"
else
    echo "  ./deploy.sh doom                         # Switch to DOOM"
fi
echo "  ./deploy.sh switch                       # Switch games (blue/green)"
echo "  ./destroy.sh                             # Clean up all resources"
