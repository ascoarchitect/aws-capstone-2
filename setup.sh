#!/bin/bash

# Make all scripts executable
chmod +x bootstrap.sh deploy.sh destroy.sh

echo "AWS Kubernetes Capstone 2 - DOS Games Platform"
echo "============================================="
echo ""
echo "Setup complete! Scripts are now executable."
echo ""
echo "Quick Start Guide:"
echo "1. Ensure AWS credentials are configured: aws configure"
echo "2. Run bootstrap: ./bootstrap.sh"
echo "3. Deploy DOOM: ./deploy.sh doom"
echo "4. Switch to Civilization: ./deploy.sh switch"
echo "5. Clean up: ./destroy.sh"
echo ""
echo "This is a development project optimized for cost."
echo "Using t2.medium spot instances and minimal resources."