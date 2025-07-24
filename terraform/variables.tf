# =============================================================================
# GeuseMaker Terraform Variables
# Variable definitions for infrastructure deployment
# =============================================================================

# =============================================================================
# BASIC CONFIGURATION
# =============================================================================

variable "stack_name" {
  description = "Name of the deployment stack"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.stack_name))
    error_message = "Stack name must start with a letter, contain only alphanumeric characters and hyphens, and end with an alphanumeric character."
  }
  
  validation {
    condition     = length(var.stack_name) >= 3 && length(var.stack_name) <= 64
    error_message = "Stack name must be between 3 and 64 characters long."
  }
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "owner" {
  description = "Owner of the resources (for tagging)"
  type        = string
  default     = "GeuseMaker"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# =============================================================================
# DEPLOYMENT CONFIGURATION
# =============================================================================

variable "deployment_type" {
  description = "Type of deployment (spot, ondemand)"
  type        = string
  default     = "spot"
  
  validation {
    condition     = contains(["spot", "ondemand"], var.deployment_type)
    error_message = "Deployment type must be either 'spot' or 'ondemand'."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "g4dn.xlarge"
  
  validation {
    condition = can(regex("^(t3|t3a|m5|m5a|m6i|c5|c5n|c6i|g4dn|g5|p3|p4)\\.", var.instance_type))
    error_message = "Instance type must be from supported families: t3, t3a, m5, m5a, m6i, c5, c5n, c6i, g4dn, g5, p3, p4."
  }
}

variable "spot_price" {
  description = "Maximum price for spot instances (only used when deployment_type is 'spot')"
  type        = string
  default     = "0.50"
  
  validation {
    condition     = can(tonumber(var.spot_price)) && tonumber(var.spot_price) > 0 && tonumber(var.spot_price) <= 50
    error_message = "Spot price must be a number between 0 and 50."
  }
}

variable "spot_type" {
  description = "Spot instance request type"
  type        = string
  default     = "one-time"
  
  validation {
    condition     = contains(["one-time", "persistent"], var.spot_type)
    error_message = "Spot type must be either 'one-time' or 'persistent'."
  }
}

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================

variable "vpc_id" {
  description = "VPC ID to deploy resources in (if null, uses default VPC)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs to deploy resources in (if null, uses default subnets)"
  type        = list(string)
  default     = null
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the services"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All values must be valid CIDR blocks."
  }
}

# =============================================================================
# SSH KEY CONFIGURATION
# =============================================================================

variable "key_name" {
  description = "Name of existing AWS key pair (if null, creates a new one)"
  type        = string
  default     = null
}

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================

variable "root_volume_type" {
  description = "Type of root EBS volume"
  type        = string
  default     = "gp3"
  
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "Root volume type must be one of: gp2, gp3, io1, io2."
  }
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 100
  
  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 1000
    error_message = "Root volume size must be between 20 and 1000 GB."
  }
}

variable "enable_efs" {
  description = "Enable EFS for shared storage"
  type        = bool
  default     = false
}

variable "efs_performance_mode" {
  description = "EFS performance mode"
  type        = string
  default     = "generalPurpose"
  
  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "EFS performance mode must be either 'generalPurpose' or 'maxIO'."
  }
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "provisioned"
  
  validation {
    condition     = contains(["bursting", "provisioned"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be either 'bursting' or 'provisioned'."
  }
}

variable "efs_provisioned_throughput" {
  description = "EFS provisioned throughput in MiB/s (only used when throughput_mode is 'provisioned')"
  type        = number
  default     = 100
  
  validation {
    condition     = var.efs_provisioned_throughput >= 1 && var.efs_provisioned_throughput <= 1000
    error_message = "EFS provisioned throughput must be between 1 and 1000 MiB/s."
  }
}

# =============================================================================
# APPLICATION CONFIGURATION
# =============================================================================

variable "compose_file" {
  description = "Docker Compose file to use"
  type        = string
  default     = "docker-compose.gpu-optimized.yml"
  
  validation {
    condition     = can(regex("\\.ya?ml$", var.compose_file))
    error_message = "Compose file must have .yml or .yaml extension."
  }
}

# =============================================================================
# LOAD BALANCER CONFIGURATION
# =============================================================================

variable "enable_load_balancer" {
  description = "Enable Application Load Balancer"
  type        = bool
  default     = false
}

variable "enable_cloudfront" {
  description = "Enable CloudFront distribution"
  type        = bool
  default     = false
}

# =============================================================================
# MONITORING CONFIGURATION
# =============================================================================

variable "log_retention_days" {
  description = "CloudWatch logs retention in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the allowed CloudWatch values."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = false
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

variable "enable_imdsv2" {
  description = "Require IMDSv2 for EC2 metadata service"
  type        = bool
  default     = true
}

variable "disable_api_termination" {
  description = "Enable termination protection for instances"
  type        = bool
  default     = false
}

# =============================================================================
# COST OPTIMIZATION
# =============================================================================

variable "budget_tier" {
  description = "Budget tier for cost optimization (low, medium, high)"
  type        = string
  default     = "medium"
  
  validation {
    condition     = contains(["low", "medium", "high"], var.budget_tier)
    error_message = "Budget tier must be one of: low, medium, high."
  }
}

variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags"
  type        = bool
  default     = true
}

# =============================================================================
# BACKUP CONFIGURATION
# =============================================================================

variable "enable_backup" {
  description = "Enable automated backups"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# =============================================================================
# ADVANCED CONFIGURATION
# =============================================================================

variable "user_data_script" {
  description = "Custom user data script (overrides default if provided)"
  type        = string
  default     = null
}

variable "additional_security_group_rules" {
  description = "Additional security group rules"
  type = list(object({
    type        = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = []
}

variable "instance_metadata_options" {
  description = "Instance metadata options"
  type = object({
    http_endpoint = string
    http_tokens   = string
    http_put_response_hop_limit = number
  })
  default = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2
    http_put_response_hop_limit = 1
  }
}

# =============================================================================
# FEATURE FLAGS
# =============================================================================

variable "enable_gpu_monitoring" {
  description = "Enable GPU-specific monitoring (for GPU instances)"
  type        = bool
  default     = true
}

variable "enable_auto_scaling" {
  description = "Enable auto scaling (for future implementation)"
  type        = bool
  default     = false
}

variable "enable_multi_az" {
  description = "Deploy across multiple availability zones"
  type        = bool
  default     = false
}

# =============================================================================
# DEBUGGING AND DEVELOPMENT
# =============================================================================

variable "debug_mode" {
  description = "Enable debug mode for troubleshooting"
  type        = bool
  default     = false
}

variable "preserve_on_failure" {
  description = "Preserve resources on failure (for debugging)"
  type        = bool
  default     = false
}

# Add these security-related variables at the end of the file

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

variable "enable_secrets_manager" {
  description = "Enable AWS Secrets Manager for credentials"
  type        = bool
  default     = false
}

variable "postgres_password" {
  description = "PostgreSQL password (leave null to auto-generate)"
  type        = string
  default     = null
  sensitive   = true
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = false
}

variable "enable_guardduty" {
  description = "Enable AWS GuardDuty for threat detection"
  type        = bool
  default     = false
}

variable "backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for all data"
  type        = bool
  default     = true
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for HTTPS (optional)"
  type        = string
  default     = null
}