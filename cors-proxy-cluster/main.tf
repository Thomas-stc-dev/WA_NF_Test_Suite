# main.tf - Fixed version with AMI fallbacks
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Variables
variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "instance_count" {
  description = "Number of proxy instances to create"
  type        = number
  default     = 10
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.nano"
}

variable "your_ip" {
  description = "Your IP address for SSH access (CIDR format)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "AWS Key Pair name for SSH access"
  type        = string
  default     = ""
}

# Provider
provider "aws" {
  region = var.region
}

# AMI Data Sources with fallbacks
data "aws_ami" "ubuntu_22" {
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
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "ubuntu_20" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Choose the best available AMI
locals {
  # Try Ubuntu 22.04 first, then 20.04, then Amazon Linux
  selected_ami = try(data.aws_ami.ubuntu_22.id, try(data.aws_ami.ubuntu_20.id, data.aws_ami.amazon_linux.id))
  
  # Determine if we're using Amazon Linux for different user data
  is_amazon_linux = try(data.aws_ami.ubuntu_22.id, try(data.aws_ami.ubuntu_20.id, "amazon")) == "amazon"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC (using default VPC for simplicity)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group
resource "aws_security_group" "tinyproxy" {
  name_prefix = "tinyproxy-"
  description = "Security group for TinyProxy instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "TinyProxy"
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "CORS-Anywhere"
    from_port   = 8889
    to_port     = 8889
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tinyproxy-security-group"
  }
}

# User Data Scripts for different OS types
locals {
  ubuntu_user_data = base64encode(<<-EOF
    #!/bin/bash
    
    # Log everything to user-data.log
    exec > >(tee /var/log/user-data.log) 2>&1
    echo "=== Starting TinyProxy installation at $(date) ==="
    
    # Update package list
    echo "Updating package list..."
    apt-get update -y
    
    # Install tinyproxy
    echo "Installing tinyproxy..."
    apt-get install -y tinyproxy
    
    # Backup original config
    echo "Backing up original config..."
    cp /etc/tinyproxy/tinyproxy.conf /etc/tinyproxy/tinyproxy.conf.backup
    
    # Create new tinyproxy configuration
    echo "Creating new tinyproxy configuration..."
    cat > /etc/tinyproxy/tinyproxy.conf << 'EOL'
User tinyproxy
Group tinyproxy
Port 8888
Allow 0.0.0.0/0
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
ConnectPort 443
ConnectPort 563
ConnectPort 80
ConnectPort 21
ConnectPort 22
ConnectPort 25
ConnectPort 53
ConnectPort 110
ConnectPort 143
ConnectPort 993
ConnectPort 995
DisableViaHeader Yes
Anonymous "Host"
Anonymous "Authorization" 
Anonymous "Cookie"
Anonymous "Referer"
Anonymous "User-Agent"
Anonymous "X-Forwarded-For"
Anonymous "X-Real-IP"
EOL

    # Create log directory
    echo "Creating log directory..."
    mkdir -p /var/log/tinyproxy
    chown tinyproxy:tinyproxy /var/log/tinyproxy
    
    # Kill any existing tinyproxy processes
    echo "Stopping any existing tinyproxy processes..."
    pkill -f tinyproxy || true
    sleep 2
    
    # Start tinyproxy directly (bypassing systemd issues)
    echo "Starting tinyproxy directly..."
    /usr/bin/tinyproxy -c /etc/tinyproxy/tinyproxy.conf
    
    # Also try to enable the service for future reboots
    echo "Enabling tinyproxy service..."
    systemctl enable tinyproxy || true
    
    # Wait a moment and test
    sleep 5
    
    # Test proxy locally
    echo "Testing proxy locally..."
    curl -x localhost:8888 http://httpbin.org/ip --connect-timeout 10 || echo "Local proxy test failed"
    
    # Check if tinyproxy process is running
    if pgrep -f tinyproxy > /dev/null; then
        echo "✅ TinyProxy is running successfully"
        ps aux | grep tinyproxy | grep -v grep
    else
        echo "❌ TinyProxy failed to start"
    fi
    
    # Create check script for troubleshooting
    cat > /home/ubuntu/check_proxy.sh << 'EOL'
#!/bin/bash
echo "Checking TinyProxy process..."
ps aux | grep tinyproxy | grep -v grep
echo ""
echo "Testing proxy locally..."
curl -x localhost:8888 http://httpbin.org/ip --connect-timeout 10 || echo "Proxy test failed"
EOL
    
    chmod +x /home/ubuntu/check_proxy.sh
    echo "=== TinyProxy setup completed at $(date) ===" >> /var/log/setup.log
  EOF
  )
  
  amazon_linux_user_data = base64encode(<<-EOF
    #!/bin/bash
    
    # Log everything to user-data.log
    exec > >(tee /var/log/user-data.log) 2>&1
    echo "=== Starting TinyProxy installation on Amazon Linux at $(date) ==="
    
    # Update package list
    echo "Updating package list..."
    yum update -y
    yum install -y epel-release
    yum install -y tinyproxy
    
    # Backup original config
    echo "Backing up original config..."
    cp /etc/tinyproxy/tinyproxy.conf /etc/tinyproxy/tinyproxy.conf.backup
    
    # Create new tinyproxy configuration
    echo "Creating new tinyproxy configuration..."
    cat > /etc/tinyproxy/tinyproxy.conf << 'EOL'
User tinyproxy
Group tinyproxy
Port 8888
Allow 0.0.0.0/0
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
ConnectPort 443
ConnectPort 563
ConnectPort 80
ConnectPort 21
ConnectPort 22
ConnectPort 25
ConnectPort 53
ConnectPort 110
ConnectPort 143
ConnectPort 993
ConnectPort 995
DisableViaHeader Yes
Anonymous "Host"
Anonymous "Authorization" 
Anonymous "Cookie"
Anonymous "Referer"
Anonymous "User-Agent"
Anonymous "X-Forwarded-For"
Anonymous "X-Real-IP"
EOL

    # Create log directory
    echo "Creating log directory..."
    mkdir -p /var/log/tinyproxy
    chown tinyproxy:tinyproxy /var/log/tinyproxy
    
    # Kill any existing tinyproxy processes
    echo "Stopping any existing tinyproxy processes..."
    pkill -f tinyproxy || true
    sleep 2
    
    # Start tinyproxy directly (bypassing systemd issues)
    echo "Starting tinyproxy directly..."
    /usr/bin/tinyproxy -c /etc/tinyproxy/tinyproxy.conf
    
    # Also try to enable the service for future reboots
    echo "Enabling tinyproxy service..."
    systemctl enable tinyproxy || true
    
    # Wait a moment and test
    sleep 5
    
    # Test proxy locally
    echo "Testing proxy locally..."
    curl -x localhost:8888 http://httpbin.org/ip --connect-timeout 10 || echo "Local proxy test failed"
    
    # Check if tinyproxy process is running
    if pgrep -f tinyproxy > /dev/null; then
        echo "✅ TinyProxy is running successfully"
        ps aux | grep tinyproxy | grep -v grep
    else
        echo "❌ TinyProxy failed to start"
    fi
    
    # Create check script for troubleshooting
    cat > /home/ec2-user/check_proxy.sh << 'EOL'
#!/bin/bash
echo "Checking TinyProxy process..."
ps aux | grep tinyproxy | grep -v grep
echo ""
echo "Testing proxy locally..."
curl -x localhost:8888 http://httpbin.org/ip --connect-timeout 10 || echo "Proxy test failed"
EOL
    
    chmod +x /home/ec2-user/check_proxy.sh
    echo "=== TinyProxy setup completed at $(date) ===" >> /var/log/setup.log
  EOF
  )
}

# EC2 Instances
resource "aws_instance" "tinyproxy" {
  count                       = var.instance_count
  ami                        = local.selected_ami
  instance_type              = var.instance_type
  key_name                   = var.key_name != "" ? var.key_name : null
  vpc_security_group_ids     = [aws_security_group.tinyproxy.id]
  associate_public_ip_address = true
  
  subnet_id = data.aws_subnets.default.ids[count.index % length(data.aws_subnets.default.ids)]
  
  user_data                   = local.is_amazon_linux ? local.amazon_linux_user_data : local.ubuntu_user_data
  user_data_replace_on_change = true
  
  monitoring = false
  ebs_optimized = true
  
  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
    
    tags = {
      Name = "tinyproxy-${count.index + 1}-root"
    }
  }

  tags = {
    Name        = "tinyproxy-${count.index + 1}"
    Environment = "testing"
    Purpose     = "proxy-server"
    Index       = count.index + 1
    AMI_Type    = local.is_amazon_linux ? "Amazon Linux" : "Ubuntu"
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Outputs
output "selected_ami_info" {
  description = "Information about the selected AMI"
  value = {
    ami_id = local.selected_ami
    ami_type = local.is_amazon_linux ? "Amazon Linux" : "Ubuntu"
  }
}

output "proxy_instances" {
  description = "Details of all proxy instances"
  value = [
    for i, instance in aws_instance.tinyproxy : {
      name          = "proxy-${i + 1}"
      instance_id   = instance.id
      public_ip     = instance.public_ip
      private_ip    = instance.private_ip
      proxy_endpoint = "${instance.public_ip}:8888"
      ssh_command   = local.is_amazon_linux ? "ssh -i your-key.pem ec2-user@${instance.public_ip}" : "ssh -i your-key.pem ubuntu@${instance.public_ip}"
    }
  ]
}

output "proxy_endpoints" {
  description = "List of proxy endpoints for easy copy-paste"
  value       = [for instance in aws_instance.tinyproxy : "${instance.public_ip}:8888"]
}

output "proxy_test_commands" {
  description = "Commands to test each proxy"
  value = [
    for i, instance in aws_instance.tinyproxy : 
    "curl -x ${instance.public_ip}:8888 http://httpbin.org/ip --connect-timeout 10"
  ]
}

output "ssh_commands" {
  description = "SSH commands for each instance"
  value = var.key_name != "" ? [
    for i, instance in aws_instance.tinyproxy : 
    local.is_amazon_linux ? 
      "ssh -i ${var.key_name}.pem ec2-user@${instance.public_ip}" :
      "ssh -i ${var.key_name}.pem ubuntu@${instance.public_ip}"
  ] : ["Key pair not specified - SSH commands not available"]
}

output "deployment_summary" {
  description = "Deployment summary"
  value = {
    region         = var.region
    instance_count = var.instance_count
    instance_type  = var.instance_type
    ami_type       = local.is_amazon_linux ? "Amazon Linux" : "Ubuntu"
    total_cost_estimate = "${var.instance_count * 3.80} USD/month (approximate for t3.nano)"
  }
}