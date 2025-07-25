#!/bin/bash
# =============================================================================
# Instance Status Check and Recovery Script
# Helps diagnose issues with launched instances
# =============================================================================

set -euo pipefail

# Load shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

source "$LIB_DIR/error-handling.sh"
source "$LIB_DIR/aws-deployment-common.sh"
source "$LIB_DIR/aws-config.sh"

# Configuration
STACK_NAME="${1:-33}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"

# Colors for output
RED_COLOR='\033[0;31m'
GREEN_COLOR='\033[0;32m'
YELLOW_COLOR='\033[1;33m'
BLUE_COLOR='\033[0;34m'
NC_COLOR='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC_COLOR}"
}

# Function to check instance status
check_instance_status() {
    local instance_id="$1"
    
    print_status $BLUE_COLOR "🔍 Checking status of instance: $instance_id"
    
    # Get instance details
    local instance_info
    instance_info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Reservations[0].Instances[0]' \
        --output json 2>/dev/null || echo "{}")
    
    if [ "$instance_info" = "{}" ]; then
        print_status $RED_COLOR "❌ Instance $instance_id not found or access denied"
        return 1
    fi
    
    # Extract key information
    local state=$(echo "$instance_info" | jq -r '.State.Name')
    local public_ip=$(echo "$instance_info" | jq -r '.PublicIpAddress // empty')
    local private_ip=$(echo "$instance_info" | jq -r '.PrivateIpAddress // empty')
    local instance_type=$(echo "$instance_info" | jq -r '.InstanceType')
    local launch_time=$(echo "$instance_info" | jq -r '.LaunchTime')
    local key_name=$(echo "$instance_info" | jq -r '.KeyName // empty')
    
    print_status $GREEN_COLOR "📊 Instance Information:"
    echo "   State: $state"
    echo "   Instance Type: $instance_type"
    echo "   Public IP: ${public_ip:-Not assigned}"
    echo "   Private IP: ${private_ip:-Not assigned}"
    echo "   Key Name: ${key_name:-Not assigned}"
    echo "   Launch Time: $launch_time"
    
    # Check if instance is running
    if [ "$state" = "running" ]; then
        print_status $GREEN_COLOR "✅ Instance is running"
        
        if [ -n "$public_ip" ]; then
            print_status $BLUE_COLOR "🔍 Testing SSH connectivity..."
            test_ssh_connectivity "$public_ip" "$key_name"
        else
            print_status $YELLOW_COLOR "⚠️ No public IP assigned"
        fi
        
        # Check user data script status
        check_user_data_status "$instance_id"
        
    elif [ "$state" = "pending" ]; then
        print_status $YELLOW_COLOR "⏳ Instance is still starting up..."
    elif [ "$state" = "stopping" ] || [ "$state" = "shutting-down" ]; then
        print_status $RED_COLOR "🛑 Instance is shutting down"
    elif [ "$state" = "stopped" ]; then
        print_status $YELLOW_COLOR "⏸️ Instance is stopped"
        print_status $BLUE_COLOR "💡 You can start it again with: aws ec2 start-instances --instance-ids $instance_id"
    else
        print_status $RED_COLOR "❌ Instance is in unexpected state: $state"
    fi
}

# Function to test SSH connectivity
test_ssh_connectivity() {
    local public_ip="$1"
    local key_name="$2"
    
    # Find the key file
    local key_file=""
    if [ -f "$PROJECT_ROOT/GeuseMaker-key.pem" ]; then
        key_file="$PROJECT_ROOT/GeuseMaker-key.pem"
    elif [ -f "$PROJECT_ROOT/$key_name.pem" ]; then
        key_file="$PROJECT_ROOT/$key_name.pem"
    else
        print_status $YELLOW_COLOR "⚠️ Key file not found. Please provide the path to your .pem file"
        return 1
    fi
    
    # Test SSH connection
    print_status $BLUE_COLOR "🔑 Testing SSH with key: $key_file"
    
    if ssh -i "$key_file" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes ubuntu@"$public_ip" "echo 'SSH connection successful'" 2>/dev/null; then
        print_status $GREEN_COLOR "✅ SSH connection successful!"
        print_status $BLUE_COLOR "💡 You can now SSH into the instance:"
        echo "   ssh -i $key_file ubuntu@$public_ip"
        return 0
    else
        print_status $RED_COLOR "❌ SSH connection failed"
        print_status $YELLOW_COLOR "💡 This might be because:"
        echo "   1. User data script is still running"
        echo "   2. Security group doesn't allow SSH"
        echo "   3. Instance is still booting"
        return 1
    fi
}

# Function to check user data script status
check_user_data_status() {
    local instance_id="$1"
    
    print_status $BLUE_COLOR "📋 Checking user data script status..."
    
    # Try to get user data output from console
    local console_output
    console_output=$(aws ec2 get-console-output \
        --instance-id "$instance_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Output' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$console_output" ]; then
        print_status $GREEN_COLOR "📄 Console output available"
        
        # Check for user data completion
        if echo "$console_output" | grep -q "User data script completed successfully"; then
            print_status $GREEN_COLOR "✅ User data script completed successfully"
        elif echo "$console_output" | grep -q "user-data-complete"; then
            print_status $GREEN_COLOR "✅ User data script completed"
        else
            print_status $YELLOW_COLOR "⏳ User data script may still be running"
        fi
        
        # Show last few lines of console output
        print_status $BLUE_COLOR "📄 Last 10 lines of console output:"
        echo "$console_output" | tail -10 | sed 's/^/   /'
    else
        print_status $YELLOW_COLOR "⚠️ Console output not available yet"
    fi
}

# Function to find instances by stack name
find_stack_instances() {
    print_status $BLUE_COLOR "🔍 Looking for instances with stack name: $STACK_NAME"
    
    local instances
    instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Stack,Values=$STACK_NAME" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Reservations[].Instances[].{InstanceId:InstanceId,State:State.Name,PublicIp:PublicIpAddress,LaunchTime:LaunchTime}' \
        --output json 2>/dev/null || echo "[]")
    
    local instance_count=$(echo "$instances" | jq length)
    
    if [ "$instance_count" -eq 0 ]; then
        print_status $YELLOW_COLOR "⚠️ No instances found with stack name: $STACK_NAME"
        return 1
    fi
    
    print_status $GREEN_COLOR "📊 Found $instance_count instance(s):"
    echo "$instances" | jq -r '.[] | "   \(.InstanceId) (\(.State)) - \(.PublicIp // "No IP") - \(.LaunchTime)"'
    
    # Check each instance
    echo "$instances" | jq -r '.[].InstanceId' | while read -r instance_id; do
        echo ""
        check_instance_status "$instance_id"
    done
}

# Function to recover a stopped instance
recover_instance() {
    local instance_id="$1"
    
    print_status $BLUE_COLOR "🔄 Attempting to recover instance: $instance_id"
    
    # Check current state
    local state
    state=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown")
    
    if [ "$state" = "stopped" ]; then
        print_status $BLUE_COLOR "🚀 Starting stopped instance..."
        aws ec2 start-instances \
            --instance-ids "$instance_id" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE"
        
        print_status $GREEN_COLOR "✅ Instance start initiated"
        print_status $BLUE_COLOR "⏳ Waiting for instance to be running..."
        
        # Wait for instance to be running
        aws ec2 wait instance-running \
            --instance-ids "$instance_id" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE"
        
        print_status $GREEN_COLOR "✅ Instance is now running"
        
        # Check status again
        check_instance_status "$instance_id"
        
    elif [ "$state" = "running" ]; then
        print_status $GREEN_COLOR "✅ Instance is already running"
        check_instance_status "$instance_id"
    else
        print_status $RED_COLOR "❌ Cannot recover instance in state: $state"
    fi
}

# Main function
main() {
    print_status $BLUE_COLOR "🔍 GeuseMaker Instance Status Checker"
    print_status $BLUE_COLOR "====================================="
    
    # Check if specific instance ID provided
    if [[ "$STACK_NAME" =~ ^i-[a-f0-9]+$ ]]; then
        print_status $BLUE_COLOR "🔍 Checking specific instance: $STACK_NAME"
        check_instance_status "$STACK_NAME"
    else
        # Look for instances by stack name
        if ! find_stack_instances; then
            print_status $YELLOW_COLOR "💡 No instances found. You can:"
            echo "   1. Run the deployment script again"
            echo "   2. Check if the stack name is correct"
            echo "   3. Look for instances manually in AWS Console"
        fi
    fi
}

# Show usage if no arguments provided
if [ $# -eq 0 ]; then
    print_status $BLUE_COLOR "Usage: $0 [stack_name_or_instance_id]"
    echo ""
    print_status $YELLOW_COLOR "Examples:"
    echo "   $0 33                    # Check instances with stack name '33'"
    echo "   $0 i-07390b2fb8e8def47   # Check specific instance"
    echo ""
    print_status $YELLOW_COLOR "Environment variables:"
    echo "   AWS_REGION=us-east-1     # AWS region (default: us-east-1)"
    echo "   AWS_PROFILE=default      # AWS profile (default: default)"
    exit 1
fi

# Run main function
main "$@" 