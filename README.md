# AWS ALB Automated Deployment with Path-Based Routing

Automated AWS infrastructure deployment using AWS CLI and Bash scripting.

## Architecture & Features
- **Application Load Balancer (ALB)** acting as the public entry point.
- **Path-Based Routing**:
  - Traffic to `/red*` routes to `Red-Server` target group.
  - Traffic to `/blue*` routes to `Blue-Server` target group.
- **EC2 Auto-Configuration**: Automated Apache installation and HTML setup via User Data scripts.
- **Security Group**: Configured to allow inbound HTTP traffic on port 80.

## How to Run

1. Make the deployment script executable:
   ```bash
   chmod +x deploy.sh
