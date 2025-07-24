# Prerequisites & Setup

> Everything you need before deploying your AI infrastructure

This guide covers all prerequisites and initial setup required to deploy the GeuseMaker successfully. Complete these steps before attempting any deployment.

## 📋 Prerequisites Checklist

### ✅ **Required Prerequisites**
- [ ] AWS Account with appropriate permissions
- [ ] AWS CLI installed and configured
- [ ] Docker and Docker Compose installed
- [ ] Git for repository management
- [ ] Basic command-line knowledge

### ✅ **Recommended Prerequisites**
- [ ] Terraform installed (for Infrastructure as Code)
- [ ] Make utility for automation
- [ ] Text editor or IDE
- [ ] SSH client
- [ ] Web browser for service access

---

## 🔧 System Requirements

### **Local Development Machine**

| Component | Minimum | Recommended | Purpose |
|-----------|---------|-------------|---------|
| **Operating System** | macOS 10.15+, Ubuntu 18.04+, Windows 10+ | Latest stable version | Development environment |
| **Memory (RAM)** | 4GB | 8GB+ | Build tools and development |
| **Storage** | 10GB free | 50GB+ free | Dependencies and artifacts |
| **Network** | Internet access | Stable broadband | AWS API calls and downloads |
| **CPU** | 2 cores | 4+ cores | Build and compilation tasks |

### **AWS Account Requirements**

| Resource | Requirement | Purpose |
|----------|-------------|---------|
| **Account Type** | Standard AWS account | Cloud infrastructure |
| **Billing** | Valid payment method | Resource usage costs |
| **Regions** | Access to chosen region | Service deployment |
| **Limits** | Default service limits | Instance and resource creation |

---

## 🔐 AWS Account Setup

### Step 1: Create AWS Account

If you don't have an AWS account:

1. **Visit AWS Console**: Go to [aws.amazon.com](https://aws.amazon.com)
2. **Create Account**: Click "Create an AWS Account"
3. **Complete Registration**: Provide required information
4. **Verify Payment Method**: Add valid credit/debit card
5. **Complete Verification**: Phone and email verification

### Step 2: IAM User Setup (Recommended)

For security, create a dedicated IAM user instead of using root account:

1. **Open IAM Console**: Navigate to IAM in AWS Console
2. **Create User**: Click "Add user"
3. **Set Permissions**: Attach the following policies:
   - `AmazonEC2FullAccess`
   - `IAMFullAccess`
   - `AmazonVPCFullAccess`
   - `CloudWatchLogsFullAccess`
   - `AmazonEFSFullAccess` (if using EFS)
   - `AmazonS3FullAccess` (for backups)

4. **Generate Access Keys**: Create programmatic access keys
5. **Save Credentials**: Store Access Key ID and Secret Access Key securely

### Step 3: Service Limits Verification

Check your account limits for key services:

```bash
# Check EC2 limits
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-1216C47A  # Running On-Demand instances

# Check Spot instance limits  
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-34B43A08  # Spot instances
```

**Typical Limits Needed:**
- EC2 instances: 5+ running instances
- Spot instances: 5+ running instances  
- EBS volumes: 20+ volumes
- VPC resources: Default limits usually sufficient

---

## 🛠️ Tool Installation

### **AWS CLI Installation**

**macOS (Homebrew):**
```bash
brew install awscli
```

**macOS/Linux (Direct):**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Windows:**
Download and run the [AWS CLI MSI installer](https://awscli.amazonaws.com/AWSCLIV2.msi)

**Verification:**
```bash
aws --version
# Should output: aws-cli/2.x.x Python/3.x.x...
```

### **Docker Installation**

**macOS:**
1. Download [Docker Desktop for Mac](https://docs.docker.com/desktop/mac/install/)
2. Install and start Docker Desktop
3. Verify installation

**Ubuntu/Debian:**
```bash
# Remove old versions
sudo apt-get remove docker docker-engine docker.io containerd runc

# Install dependencies
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg lsb-release

# Add Docker's GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
```

**Windows:**
1. Download [Docker Desktop for Windows](https://docs.docker.com/desktop/windows/install/)
2. Install and restart your computer
3. Start Docker Desktop

**Verification:**
```bash
docker --version
docker-compose --version
# Should show version information for both
```

### **Git Installation**

**macOS:**
```bash
# Using Homebrew
brew install git

# Or download from https://git-scm.com/download/mac
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install git
```

**Windows:**
Download from [git-scm.com](https://git-scm.com/download/win)

**Verification:**
```bash
git --version
# Should show git version
```

### **Optional: Terraform Installation**

**macOS (Homebrew):**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

**Ubuntu/Debian:**
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

**Windows:**
Download from [terraform.io](https://www.terraform.io/downloads.html)

**Verification:**
```bash
terraform --version
# Should show Terraform version
```

---

## ⚙️ Configuration Setup

### **AWS CLI Configuration**

Configure AWS CLI with your credentials:

```bash
aws configure
```

When prompted, enter:
- **AWS Access Key ID**: Your IAM user access key
- **AWS Secret Access Key**: Your IAM user secret key  
- **Default region name**: Your preferred region (e.g., `us-east-1`)
- **Default output format**: `json` (recommended)

**Verify Configuration:**
```bash
# Test AWS connectivity
aws sts get-caller-identity

# Should output your account ID and user information
```

### **Regional Configuration**

Choose your deployment region based on:

| Factor | Considerations |
|--------|----------------|
| **Latency** | Choose region closest to your users |
| **Services** | Ensure all required services available |
| **Costs** | Some regions have different pricing |
| **Compliance** | Data residency requirements |

**Popular Regions:**
- `us-east-1` (N. Virginia) - Lowest cost, most services
- `us-west-2` (Oregon) - Good for West Coast
- `eu-west-1` (Ireland) - Europe deployments
- `ap-southeast-1` (Singapore) - Asia Pacific

### **Docker Configuration**

**Resource Allocation (Desktop):**
- **Memory**: Allocate at least 4GB to Docker
- **CPU**: Allocate at least 2 CPU cores
- **Disk**: Ensure sufficient disk space for images

**Configuration Steps:**
1. Open Docker Desktop settings
2. Go to "Resources" → "Advanced"
3. Set appropriate memory and CPU limits
4. Apply and restart Docker

---

## 🔒 Security Configuration

### **SSH Key Setup**

Generate SSH key for secure instance access:

```bash
# Generate new SSH key (if you don't have one)
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"

# Start SSH agent
eval "$(ssh-agent -s)"

# Add key to SSH agent
ssh-add ~/.ssh/id_rsa
```

### **AWS Security Best Practices**

1. **Enable MFA**: Multi-factor authentication on your AWS account
2. **Use IAM Users**: Don't use root account for daily operations
3. **Least Privilege**: Grant minimal required permissions
4. **Regular Rotation**: Rotate access keys regularly
5. **Monitor Usage**: Enable CloudTrail logging

### **Local Security**

1. **Secure Credentials**: Never commit AWS credentials to Git
2. **Use Environment Variables**: For sensitive configuration
3. **File Permissions**: Secure SSH keys (`chmod 600`)
4. **Encrypted Storage**: Use disk encryption on development machine

---

## 🧪 Verification Tests

### **Complete Prerequisites Test**

Run this comprehensive test to verify all prerequisites:

```bash
# Test AWS CLI
echo "Testing AWS CLI..."
aws sts get-caller-identity && echo "✅ AWS CLI configured" || echo "❌ AWS CLI failed"

# Test Docker
echo "Testing Docker..."
docker run hello-world && echo "✅ Docker working" || echo "❌ Docker failed"

# Test Docker Compose
echo "Testing Docker Compose..."
docker-compose --version && echo "✅ Docker Compose available" || echo "❌ Docker Compose failed"

# Test Git
echo "Testing Git..."
git --version && echo "✅ Git available" || echo "❌ Git failed"

# Test network connectivity
echo "Testing AWS connectivity..."
aws ec2 describe-regions --output table && echo "✅ AWS connectivity working" || echo "❌ AWS connectivity failed"
```

### **Automated Prerequisites Check**

The GeuseMaker includes an automated prerequisites checker:

```bash
# Clone repository first
git clone <repository-url>
cd GeuseMaker

# Run automated check
make check-deps

# Or run individual check
./tools/install-deps.sh --check-only
```

---

## 🚨 Common Issues & Solutions

### **AWS CLI Issues**

**Issue**: `aws: command not found`
```bash
# Solution: Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Issue**: `Unable to locate credentials`
```bash
# Solution: Configure AWS CLI
aws configure
# Enter your Access Key ID and Secret Access Key
```

**Issue**: `An error occurred (UnauthorizedOperation)`
```bash
# Solution: Check IAM permissions
aws iam get-user
# Verify user has required permissions
```

### **Docker Issues**

**Issue**: `Cannot connect to Docker daemon`
```bash
# Solution: Start Docker service
sudo systemctl start docker  # Linux
# Or start Docker Desktop (macOS/Windows)
```

**Issue**: `Permission denied while trying to connect to Docker`
```bash
# Solution: Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in for changes to take effect
```

**Issue**: `docker-compose: command not found`
```bash
# Solution: Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### **Network Issues**

**Issue**: Cannot reach AWS services
```bash
# Solution: Check network connectivity
curl -I https://aws.amazon.com
# Check corporate firewall/proxy settings
```

**Issue**: DNS resolution problems
```bash
# Solution: Check DNS settings
nslookup aws.amazon.com
# Try different DNS servers (8.8.8.8, 1.1.1.1)
```

---

## 📚 Additional Resources

### **AWS Documentation**
- [AWS CLI User Guide](https://docs.aws.amazon.com/cli/latest/userguide/)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS Service Limits](https://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html)

### **Tool Documentation**
- [Docker Documentation](https://docs.docker.com/)
- [Git Documentation](https://git-scm.com/doc)
- [Terraform Documentation](https://www.terraform.io/docs/)

### **Security Resources**
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [Docker Security](https://docs.docker.com/engine/security/)

---

## ✅ Prerequisites Completion Checklist

Before proceeding to deployment, ensure:

### **Account & Access**
- [ ] AWS account created and billing configured
- [ ] IAM user created with appropriate permissions
- [ ] AWS CLI installed and configured
- [ ] AWS connectivity tested successfully

### **Development Environment**
- [ ] Docker and Docker Compose installed and working
- [ ] Git installed and configured
- [ ] SSH keys generated and configured
- [ ] Local machine meets minimum requirements

### **Security**
- [ ] MFA enabled on AWS account
- [ ] Access keys stored securely
- [ ] SSH keys properly secured (chmod 600)
- [ ] No credentials committed to version control

### **Optional Tools**
- [ ] Terraform installed (for IaC deployment)
- [ ] Make utility available
- [ ] Text editor/IDE configured

### **Verification**
- [ ] All automated checks passed
- [ ] Can successfully run AWS CLI commands
- [ ] Docker containers can be started
- [ ] Network connectivity confirmed

**🎉 Prerequisites Complete!** You're ready to proceed with deployment.

[**← Back to Documentation Hub**](../README.md) | [**→ Quick Start Guide**](quick-start.md)

---

**Estimated Setup Time:** 30-60 minutes  
**Difficulty:** Beginner to Intermediate  
**Support:** See [troubleshooting guide](../guides/troubleshooting/) for additional help