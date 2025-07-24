# =============================================================================
# GeuseMaker Infrastructure as Code
# Terraform configuration for AWS deployment
# =============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  
  # Backend configuration (uncomment and configure for production)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "GeuseMaker/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-lock-table"
  # }
}

# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "GeuseMaker"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      Stack       = var.stack_name
    }
  }
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Get current AWS account information
data "aws_caller_identity" "current" {}

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Get default VPC if not provided
data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

# Get default subnets if not provided
data "aws_subnets" "default" {
  count = var.vpc_id == null ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Get latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get latest NVIDIA-optimized AMI (for GPU instances)
data "aws_ami" "nvidia_optimized" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["Deep Learning AMI GPU TensorFlow*Ubuntu*"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# =============================================================================
# LOCAL VALUES
# =============================================================================

locals {
  # Common tags
  common_tags = {
    Project     = "GeuseMaker"
    Environment = var.environment
    Stack       = var.stack_name
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
  
  # VPC and subnet configuration
  vpc_id     = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = var.subnet_ids != null ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # AMI selection based on instance type
  ami_id = var.instance_type != null && can(regex("^(g4dn|g5|p3|p4)", var.instance_type)) ? data.aws_ami.nvidia_optimized.id : data.aws_ami.ubuntu.id
  
  # Service ports
  service_ports = {
    ssh      = 22
    n8n      = 5678
    ollama   = 11434
    qdrant   = 6333
    crawl4ai = 11235
    postgres = 5432
    http     = 80
    https    = 443
  }
  
  # Instance user data
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    stack_name     = var.stack_name
    environment    = var.environment
    compose_file   = var.compose_file
    enable_nvidia  = can(regex("^(g4dn|g5|p3|p4)", var.instance_type))
    log_group      = aws_cloudwatch_log_group.main.name
    aws_region     = var.aws_region
  }))
}

# =============================================================================
# RANDOM RESOURCES
# =============================================================================

resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# KEY PAIR
# =============================================================================

resource "tls_private_key" "main" {
  count     = var.key_name == null ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  count      = var.key_name == null ? 1 : 0
  key_name   = "${var.stack_name}-key"
  public_key = tls_private_key.main[0].public_key_openssh
  
  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-key"
  })
}

# Save private key locally
resource "local_file" "private_key" {
  count           = var.key_name == null ? 1 : 0
  content         = tls_private_key.main[0].private_key_pem
  filename        = "${var.stack_name}-key.pem"
  file_permission = "0600"
}

# =============================================================================
# SECURITY GROUP
# =============================================================================

resource "aws_security_group" "main" {
  name        = "${var.stack_name}-sg"
  description = "Security group for ${var.stack_name} GeuseMaker"
  vpc_id      = local.vpc_id
  
  # SSH access
  ingress {
    description = "SSH"
    from_port   = local.service_ports.ssh
    to_port     = local.service_ports.ssh
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # n8n access
  ingress {
    description = "n8n"
    from_port   = local.service_ports.n8n
    to_port     = local.service_ports.n8n
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # Ollama access
  ingress {
    description = "Ollama"
    from_port   = local.service_ports.ollama
    to_port     = local.service_ports.ollama
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # Qdrant access
  ingress {
    description = "Qdrant"
    from_port   = local.service_ports.qdrant
    to_port     = local.service_ports.qdrant
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # Crawl4AI access
  ingress {
    description = "Crawl4AI"
    from_port   = local.service_ports.crawl4ai
    to_port     = local.service_ports.crawl4ai
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # HTTP access (for load balancer)
  dynamic "ingress" {
    for_each = var.enable_load_balancer ? [1] : []
    content {
      description = "HTTP"
      from_port   = local.service_ports.http
      to_port     = local.service_ports.http
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  
  # HTTPS access (for load balancer)
  dynamic "ingress" {
    for_each = var.enable_load_balancer ? [1] : []
    content {
      description = "HTTPS"
      from_port   = local.service_ports.https
      to_port     = local.service_ports.https
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  
  # Outbound internet access
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-sg"
  })
}

# =============================================================================
# IAM ROLE AND INSTANCE PROFILE
# =============================================================================

# IAM role for EC2 instance
resource "aws_iam_role" "instance_role" {
  name = "${var.stack_name}-instance-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach CloudWatch agent policy
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach CloudWatch logs policy
resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# Attach SSM policy for session manager
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom policy for EFS access
resource "aws_iam_role_policy" "efs_access" {
  count = var.enable_efs ? 1 : 0
  name  = "${var.stack_name}-efs-access"
  role  = aws_iam_role.instance_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "main" {
  name = "${var.stack_name}-instance-profile"
  role = aws_iam_role.instance_role.name
  
  tags = local.common_tags
}

# =============================================================================
# CLOUDWATCH LOG GROUP
# =============================================================================

resource "aws_cloudwatch_log_group" "main" {
  name              = "/aws/GeuseMaker/${var.stack_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-logs"
  })
}

# =============================================================================
# EFS (OPTIONAL)
# =============================================================================

resource "aws_efs_file_system" "main" {
  count          = var.enable_efs ? 1 : 0
  creation_token = "${var.stack_name}-efs"
  
  performance_mode = var.efs_performance_mode
  throughput_mode  = var.efs_throughput_mode
  
  dynamic "provisioned_throughput_in_mibps" {
    for_each = var.efs_throughput_mode == "provisioned" ? [var.efs_provisioned_throughput] : []
    content {
      provisioned_throughput_in_mibps = provisioned_throughput_in_mibps.value
    }
  }
  
  encrypted = true
  kms_key_id = aws_kms_key.efs[0].arn
  
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-efs"
  })
}

# KMS key for EFS encryption
resource "aws_kms_key" "efs" {
  count                   = var.enable_efs ? 1 : 0
  description             = "KMS key for ${var.stack_name} EFS encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  
  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-efs-key"
  })
}

resource "aws_kms_alias" "efs" {
  count         = var.enable_efs ? 1 : 0
  name          = "alias/${var.stack_name}-efs"
  target_key_id = aws_kms_key.efs[0].key_id
}

# EFS mount targets
resource "aws_efs_mount_target" "main" {
  count           = var.enable_efs ? length(local.subnet_ids) : 0
  file_system_id  = aws_efs_file_system.main[0].id
  subnet_id       = local.subnet_ids[count.index]
  security_groups = [aws_security_group.efs[0].id]
}

# Security group for EFS
resource "aws_security_group" "efs" {
  count       = var.enable_efs ? 1 : 0
  name        = "${var.stack_name}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = local.vpc_id
  
  ingress {
    description     = "NFS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.main.id]
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-efs-sg"
  })
}

# =============================================================================
# EC2 INSTANCE
# =============================================================================

# Spot instance request
resource "aws_spot_instance_request" "main" {
  count                           = var.deployment_type == "spot" ? 1 : 0
  ami                            = local.ami_id
  instance_type                  = var.instance_type
  key_name                       = var.key_name != null ? var.key_name : aws_key_pair.main[0].key_name
  subnet_id                      = local.subnet_ids[0]
  vpc_security_group_ids         = [aws_security_group.main.id]
  iam_instance_profile           = aws_iam_instance_profile.main.name
  user_data                      = local.user_data
  associate_public_ip_address    = true
  instance_initiated_shutdown_behavior = "terminate"
  
  spot_price                     = var.spot_price
  spot_type                      = var.spot_type
  wait_for_fulfillment          = true
  
  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }
  
  tags = merge(local.common_tags, {
    Name = var.stack_name
    Type = "spot"
  })
}

# On-demand instance
resource "aws_instance" "main" {
  count                           = var.deployment_type == "ondemand" ? 1 : 0
  ami                            = local.ami_id
  instance_type                  = var.instance_type
  key_name                       = var.key_name != null ? var.key_name : aws_key_pair.main[0].key_name
  subnet_id                      = local.subnet_ids[0]
  vpc_security_group_ids         = [aws_security_group.main.id]
  iam_instance_profile           = aws_iam_instance_profile.main.name
  user_data                      = local.user_data
  associate_public_ip_address    = true
  instance_initiated_shutdown_behavior = "terminate"
  
  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }
  
  tags = merge(local.common_tags, {
    Name = var.stack_name
    Type = "ondemand"
  })
}

# =============================================================================
# APPLICATION LOAD BALANCER (OPTIONAL)
# =============================================================================

resource "aws_lb" "main" {
  count              = var.enable_load_balancer ? 1 : 0
  name               = "${var.stack_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.main.id]
  subnets           = local.subnet_ids
  
  enable_deletion_protection = false
  
  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-alb"
  })
}

# Target group for n8n
resource "aws_lb_target_group" "n8n" {
  count    = var.enable_load_balancer ? 1 : 0
  name     = "${var.stack_name}-n8n-tg"
  port     = local.service_ports.n8n
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }
  
  tags = merge(local.common_tags, {
    Name    = "${var.stack_name}-n8n-tg"
    Service = "n8n"
  })
}

# Target group attachment
resource "aws_lb_target_group_attachment" "n8n" {
  count            = var.enable_load_balancer ? 1 : 0
  target_group_arn = aws_lb_target_group.n8n[0].arn
  target_id        = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].spot_instance_id : aws_instance.main[0].id
  port             = local.service_ports.n8n
}

# Load balancer listener
resource "aws_lb_listener" "main" {
  count             = var.enable_load_balancer ? 1 : 0
  load_balancer_arn = aws_lb.main[0].arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.n8n[0].arn
  }
}

# =============================================================================
# CLOUDWATCH ALARMS
# =============================================================================

# CPU utilization alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.stack_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  
  dimensions = {
    InstanceId = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].spot_instance_id : aws_instance.main[0].id
  }
  
  tags = local.common_tags
}

# Instance status check alarm
resource "aws_cloudwatch_metric_alarm" "instance_status" {
  alarm_name          = "${var.stack_name}-instance-status"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "StatusCheckFailed_Instance"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "This metric monitors instance status check"
  
  dimensions = {
    InstanceId = var.deployment_type == "spot" ? aws_spot_instance_request.main[0].spot_instance_id : aws_instance.main[0].id
  }
  
  tags = local.common_tags
}

# =============================================================================
# SECRETS MANAGER (OPTIONAL)
# =============================================================================

resource "aws_secretsmanager_secret" "postgres_password" {
  count                   = var.enable_secrets_manager ? 1 : 0
  name                    = "${var.stack_name}/postgres_password"
  description             = "PostgreSQL password for ${var.stack_name}"
  recovery_window_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-postgres-password"
  })
}

resource "aws_secretsmanager_secret_version" "postgres_password" {
  count          = var.enable_secrets_manager ? 1 : 0
  secret_id      = aws_secretsmanager_secret.postgres_password[0].id
  secret_string  = var.postgres_password != null ? var.postgres_password : random_password.postgres[0].result
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "random_password" "postgres" {
  count   = var.enable_secrets_manager && var.postgres_password == null ? 1 : 0
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "n8n_encryption_key" {
  count                   = var.enable_secrets_manager ? 1 : 0
  name                    = "${var.stack_name}/n8n_encryption_key"
  description             = "n8n encryption key for ${var.stack_name}"
  recovery_window_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = "${var.stack_name}-n8n-encryption-key"
  })
}

resource "aws_secretsmanager_secret_version" "n8n_encryption_key" {
  count          = var.enable_secrets_manager ? 1 : 0
  secret_id      = aws_secretsmanager_secret.n8n_encryption_key[0].id
  secret_string  = random_id.n8n_encryption_key[0].hex
}

resource "random_id" "n8n_encryption_key" {
  count       = var.enable_secrets_manager ? 1 : 0
  byte_length = 32
}

# Update IAM role policy for Secrets Manager access
resource "aws_iam_role_policy" "secrets_access" {
  count = var.enable_secrets_manager ? 1 : 0
  name  = "${var.stack_name}-secrets-access"
  role  = aws_iam_role.instance_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.postgres_password[0].arn,
          aws_secretsmanager_secret.n8n_encryption_key[0].arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}