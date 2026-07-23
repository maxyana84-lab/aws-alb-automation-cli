#!/bin/bash
set -e

echo ">>> 1. Getting VPC and Subnets..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNET_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[0].SubnetId" --output text)
SUBNET_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[1].SubnetId" --output text)

echo ">>> 2. Creating Security Group..."
SG_ID=$(aws ec2 create-security-group \
    --group-name "alb-demo-sg-$(date +%s)" \
    --description "SG for ALB and EC2 Instances" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" --output text)

aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

echo ">>> 3. Creating Target Groups..."
TG_RED_ARN=$(aws elbv2 create-target-group \
    --name "tg-red-$(date +%s)" \
    --protocol HTTP --port 80 --vpc-id "$VPC_ID" --target-type instance \
    --query "TargetGroups[0].TargetGroupArn" --output text)

TG_BLUE_ARN=$(aws elbv2 create-target-group \
    --name "tg-blue-$(date +%s)" \
    --protocol HTTP --port 80 --vpc-id "$VPC_ID" --target-type instance \
    --query "TargetGroups[0].TargetGroupArn" --output text)

echo ">>> 4. Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name "demo-alb-$(date +%s)" \
    --subnets "$SUBNET_1" "$SUBNET_2" \
    --security-groups "$SG_ID" \
    --scheme internet-facing --type application \
    --query "LoadBalancers[0].LoadBalancerArn" --output text)

echo ">>> 5. Launching EC2 Instances with User Data..."
USERDATA_RED_B64=$(echo "#!/bin/bash
yum update -y && yum install -y httpd && systemctl start httpd && systemctl enable httpd
mkdir -p /var/www/html/red
echo '<h1 style=\"color:red;\">Welcome to RED Page</h1>' > /var/www/html/red/index.html" | base64 -w 0)

USERDATA_BLUE_B64=$(echo "#!/bin/bash
yum update -y && yum install -y httpd && systemctl start httpd && systemctl enable httpd
mkdir -p /var/www/html/blue
echo '<h1 style=\"color:blue;\">Welcome to BLUE Page</h1>' > /var/www/html/blue/index.html" | base64 -w 0)

AMI_ID=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query "Parameters[0].Value" --output text)

INSTANCE_RED_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" --count 1 --instance-type "t3.micro" \
    --security-group-ids "$SG_ID" --subnet-id "$SUBNET_1" \
    --user-data "$USERDATA_RED_B64" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Red-Server}]' \
    --query "Instances[0].InstanceId" --output text)

INSTANCE_BLUE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" --count 1 --instance-type "t3.micro" \
    --security-group-ids "$SG_ID" --subnet-id "$SUBNET_2" \
    --user-data "$USERDATA_BLUE_B64" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Blue-Server}]' \
    --query "Instances[0].InstanceId" --output text)

echo ">>> Waiting for EC2 instances to enter RUNNING state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_RED_ID" "$INSTANCE_BLUE_ID"

echo ">>> 6. Registering Targets..."
aws elbv2 register-targets --target-group-arn "$TG_RED_ARN" --targets Id="$INSTANCE_RED_ID"
aws elbv2 register-targets --target-group-arn "$TG_BLUE_ARN" --targets Id="$INSTANCE_BLUE_ID"

echo ">>> 7. Creating Listener and Path-Based Rules..."
LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG_RED_ARN" \
    --query "Listeners[0].ListenerArn" --output text)

aws elbv2 create-rule --listener-arn "$LISTENER_ARN" --priority 10 \
    --conditions Field=path-pattern,Values='/red*' \
    --actions Type=forward,TargetGroupArn="$TG_RED_ARN"

aws elbv2 create-rule --listener-arn "$LISTENER_ARN" --priority 20 \
    --conditions Field=path-pattern,Values='/blue*' \
    --actions Type=forward,TargetGroupArn="$TG_BLUE_ARN"

ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query "LoadBalancers[0].DNSName" --output text)

echo "=================================================="
echo "Deployment Finished Successfully!"
echo "Red Endpoint: http://$ALB_DNS/red/"
echo "Blue Endpoint: http://$ALB_DNS/blue/"
echo "=================================================="
