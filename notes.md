#cloud-config
package_update: true
package_upgrade: true
runcmd:
  - 'yum install -y amazon-efs-utils nfs-utils docker git'
  - 'curl -L "https://github.com/docker/compose/releases/download/v2.17.2/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose'
  - 'chmod +x /usr/local/bin/docker-compose'
  - 'systemctl enable docker && systemctl start docker'
  - 'usermod -aG docker ec2-user'
  
  # Install NVIDIA driver and container toolkit (if not already pre-installed)
  - 'yum install -y nvidia-driver-latest-dkms nvidia-container-toolkit'
  - 'nvidia-container-cli info || true'
  - 'systemctl restart docker'
  
  # Generate self-signed TLS certificates for n8n
  - 'mkdir -p /home/ec2-user/certs'
  - 'openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /home/ec2-user/certs/n8n-selfsigned.key -out /home/ec2-user/certs/n8n-selfsigned.crt -subj "/CN=localhost"'
  
  # Set up EFS variables and mount EFS temporarily to pre-create directories
  - 'file_system_id_1=fs-0bba0ecccb246a550'
  - 'efs_mount_point_1=/mnt/efs/fs1'
  - 'mkdir -p "${efs_mount_point_1}"'
  - 'test -f "/sbin/mount.efs" && echo "${file_system_id_1}:/ ${efs_mount_point_1} efs tls,_netdev 0 0" >> /etc/fstab || echo "${file_system_id_1}.efs.us-east-1.amazonaws.com:/ ${efs_mount_point_1} nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" >> /etc/fstab'
  - |
    retryCnt=15; waitTime=30;
    while true; do
      mount -a -t efs,nfs4 defaults;
      if [ $? -eq 0 ] || [ $retryCnt -lt 1 ]; then
        echo "File system mounted successfully";
        break;
      fi;
      echo "File system not available, retrying to mount.";
      ((retryCnt--));
      sleep $waitTime;
    done
  - 'mkdir -p /mnt/efs/fs1/postgres_storage /mnt/efs/fs1/n8n_storage /mnt/efs/fs1/ollama_storage /mnt/efs/fs1/qdrant_storage'
  - 'umount /mnt/efs/fs1'
  
  # Clone the AI Starter Kit repository and configure environment
  - 'cd /home/ec2-user && git clone https://github.com/n8n-io/self-hosted-ai-starter-kit.git ai-starter-kit'
  - 'cd /home/ec2-user/ai-starter-kit && cp .env.example .env'
  - 'echo "POSTGRES_USER=root" >> /home/ec2-user/ai-starter-kit/.env'
  - 'echo "POSTGRES_PASSWORD=password" >> /home/ec2-user/ai-starter-kit/.env'
  - 'echo "POSTGRES_DB=n8n" >> /home/ec2-user/ai-starter-kit/.env'
  - 'echo "N8N_ENCRYPTION_KEY=super-secret-key" >> /home/ec2-user/ai-starter-kit/.env'
  - 'echo "N8N_USER_MANAGEMENT_JWT_SECRET=even-more-secret" >> /home/ec2-user/ai-starter-kit/.env'
  - 'echo "N8N_PROTOCOL=https" >> /home/ec2-user/ai-starter-kit/.env'
  - 'echo "N8N_SSL_KEY=/files/certs/n8n-selfsigned.key" >> /home/ec2-user/ai-starter-kit/.env'
  - 'echo "N8N_SSL_CERT=/files/certs/n8n-selfsigned.crt" >> /home/ec2-user/ai-starter-kit/.env'
  - 'echo "EFS_DNS=${file_system_id_1}.efs.us-east-1.amazonaws.com" >> /home/ec2-user/ai-starter-kit/.env'
  
  # Launch Docker Compose stack (using GPU profile for GPU instances; use "cpu" for CPU instances)
  - 'cd /home/ec2-user/ai-starter-kit && /usr/local/bin/docker-compose --profile gpu-nvidia up -d'
  
  # Print success message with public IP
  - ["sh", "-c", "echo '===============================================' && echo 'AI Starter Kit deployment complete!' && echo 'Access n8n at: https://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):5678/' && echo '==============================================='"]
  
  # Set up Spot Instance Termination Handling
  - |
    cat <<'EOF' > /usr/local/bin/spot-termination-check.sh
    #!/bin/bash
    CHECK_INTERVAL=60
    while true; do
      TERMINATION_TIME=$(curl -s http://169.254.169.254/latest/meta-data/spot/termination-time || true)
      if [ ! -z "$TERMINATION_TIME" ]; then
        echo "Spot instance termination notice received at $TERMINATION_TIME. Initiating graceful shutdown..."
        cd /home/ec2-user/ai-starter-kit && /usr/local/bin/docker-compose down
        shutdown -h now
        exit 0
      fi
      sleep ${CHECK_INTERVAL}
    done
    EOF
  - 'chmod +x /usr/local/bin/spot-termination-check.sh'
  - 'nohup /usr/local/bin/spot-termination-check.sh >/var/log/spot-termination.log 2>&1 &'
