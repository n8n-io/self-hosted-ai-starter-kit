# =============================================================================
# AI Starter Kit Terraform Outputs
# Output values for deployed infrastructure
# =============================================================================

# =============================================================================
# INSTANCE INFORMATION
# =============================================================================

output "instance_id" {
  description = "ID of the deployed EC2 instance"
  value       = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].spot_instance_id : aws_instance.main[0].id
}

output "instance_public_ip" {
  description = "Public IP address of the instance"
  value       = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the instance"
  value       = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].private_ip : aws_instance.main[0].private_ip
}

output "instance_type" {
  description = "Type of the deployed instance"
  value       = var.instance_type
}

output "instance_availability_zone" {
  description = "Availability zone of the instance"
  value       = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].availability_zone : aws_instance.main[0].availability_zone
}

# =============================================================================
# NETWORKING INFORMATION
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = local.vpc_id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = local.subnet_ids[0]
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.main.id
}

output "security_group_name" {
  description = "Name of the security group"
  value       = aws_security_group.main.name
}

# =============================================================================
# SSH ACCESS
# =============================================================================

output "key_name" {
  description = "Name of the SSH key pair"
  value       = var.key_name != null ? var.key_name : aws_key_pair.main[0].key_name
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${var.key_name != null ? var.key_name : "${var.stack_name}-key.pem"} ubuntu@${var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip}"
}

output "private_key_file" {
  description = "Path to the private key file (if generated)"
  value       = var.key_name == null ? "${var.stack_name}-key.pem" : null
  sensitive   = true
}

# =============================================================================
# SERVICE ENDPOINTS
# =============================================================================

output "n8n_url" {
  description = "URL to access n8n workflow automation"
  value       = "http://${var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip}:5678"
}

output "ollama_url" {
  description = "URL to access Ollama API"
  value       = "http://${var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip}:11434"
}

output "qdrant_url" {
  description = "URL to access Qdrant vector database"
  value       = "http://${var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip}:6333"
}

output "crawl4ai_url" {
  description = "URL to access Crawl4AI service"
  value       = "http://${var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip}:11235"
}

# =============================================================================
# LOAD BALANCER INFORMATION (IF ENABLED)
# =============================================================================

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = var.enable_load_balancer ? aws_lb.main[0].arn : null
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = var.enable_load_balancer ? aws_lb.main[0].dns_name : null
}

output "load_balancer_url" {
  description = "URL to access services via load balancer"
  value       = var.enable_load_balancer ? "http://${aws_lb.main[0].dns_name}" : null
}

output "target_group_arns" {
  description = "ARNs of the target groups"
  value       = var.enable_load_balancer ? [aws_lb_target_group.n8n[0].arn] : []
}

# =============================================================================
# STORAGE INFORMATION
# =============================================================================

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = var.enable_efs ? aws_efs_file_system.main[0].id : null
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = var.enable_efs ? aws_efs_file_system.main[0].dns_name : null
}

output "root_volume_id" {
  description = "ID of the root EBS volume"
  value       = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].root_block_device[0].volume_id : aws_instance.main[0].root_block_device[0].volume_id
}

# =============================================================================
# IAM INFORMATION
# =============================================================================

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = aws_iam_role.instance_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.main.name
}

# =============================================================================
# MONITORING INFORMATION
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.main.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.main.arn
}

output "monitoring_dashboard_url" {
  description = "URL to CloudWatch monitoring dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.stack_name}"
}

# =============================================================================
# COST INFORMATION
# =============================================================================

output "estimated_hourly_cost" {
  description = "Estimated hourly cost in USD"
  value       = var.deployment_type == "spot" ? var.spot_price : local.estimated_ondemand_cost
}

output "cost_allocation_tags" {
  description = "Cost allocation tags applied to resources"
  value = {
    Project     = "ai-starter-kit"
    Environment = var.environment
    Stack       = var.stack_name
    Owner       = var.owner
  }
}

# =============================================================================
# DEPLOYMENT INFORMATION
# =============================================================================

output "deployment_type" {
  description = "Type of deployment (spot or ondemand)"
  value       = var.deployment_type
}

output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for deployment"
  value       = terraform.workspace
}

output "aws_region" {
  description = "AWS region of the deployment"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# =============================================================================
# COMPREHENSIVE DEPLOYMENT SUMMARY
# =============================================================================

output "deployment_summary" {
  description = "Comprehensive deployment summary"
  value = {
    # Basic Information
    stack_name       = var.stack_name
    environment      = var.environment
    deployment_type  = var.deployment_type
    aws_region      = var.aws_region
    aws_account_id  = data.aws_caller_identity.current.account_id
    
    # Instance Information
    instance_id     = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].spot_instance_id : aws_instance.main[0].id
    instance_type   = var.instance_type
    public_ip       = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip
    availability_zone = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].availability_zone : aws_instance.main[0].availability_zone
    
    # Service URLs
    services = {
      n8n      = "http://${var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip}:5678"
      ollama   = "http://${var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip}:11434"
      qdrant   = "http://${var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip}:6333"
      crawl4ai = "http://${var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip}:11235"
    }
    
    # Access Information
    ssh_command = "ssh -i ${var.key_name != null ? var.key_name : "${var.stack_name}-key.pem"} ubuntu@${var.deployment_type == "spot" ? aws_spot_instance_request.main[0].public_ip : aws_instance.main[0].public_ip}"
    
    # Load Balancer (if enabled)
    load_balancer_url = var.enable_load_balancer ? "http://${aws_lb.main[0].dns_name}" : null
    
    # Monitoring
    cloudwatch_logs = aws_cloudwatch_log_group.main.name
    
    # Cost Information
    estimated_hourly_cost = var.deployment_type == "spot" ? var.spot_price : "varies"
    
    # Next Steps
    next_steps = [
      "Wait 5-10 minutes for services to initialize",
      "Access n8n at the provided URL to start building workflows",
      "Check CloudWatch logs for service status",
      "Review cost allocation tags in AWS Cost Explorer"
    ]
  }
}

# =============================================================================
# LOCAL VALUES FOR OUTPUTS
# =============================================================================

locals {
  # Estimated on-demand costs (simplified)
  estimated_ondemand_cost = lookup({
    "t3.micro"    = "0.0104"
    "t3.small"    = "0.0208"
    "t3.medium"   = "0.0416"
    "t3.large"    = "0.0832"
    "g4dn.xlarge" = "0.526"
    "g4dn.2xlarge" = "0.752"
    "g5.xlarge"   = "1.006"
    "c5.xlarge"   = "0.17"
    "m5.xlarge"   = "0.192"
  }, var.instance_type, "varies")
}