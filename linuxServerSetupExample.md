# Linux Server Setup Examples

## Ubuntu 20.04/22.04 LTS Server

```bash
# Full setup from scratch
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 python3-pip python3-venv openssh-client git

# Create dedicated user
sudo useradd -m -s /bin/bash purple-tester
sudo usermod -aG sudo purple-tester

# Switch to test user
sudo -i -u purple-tester

# Setup project
cd ~
git clone https://github.com/your-repo/purple-os-testing.git
cd purple-os-testing

# Python environment
python3 -m venv venv
source venv/bin/activate
pip install pyyaml jinja2

# SSH key
ssh-keygen -t ed25519 -f ~/.ssh/purple_os_ed25519 -N ""
ssh-copy-id -i ~/.ssh/purple_os_ed25519.pub root@192.168.1.1

# Test
python purple_os_test_native.py
```

## CentOS 8 / Rocky Linux 8 / AlmaLinux 8

```bash
# System setup
sudo dnf update -y
sudo dnf install -y python39 python39-pip openssh-clients git
sudo alternatives --set python3 /usr/bin/python3.9

# SELinux considerations
sudo setsebool -P httpd_can_network_connect 1  # If serving reports

# Firewall
sudo firewall-cmd --permanent --add-port=8080/tcp  # If serving reports
sudo firewall-cmd --reload

# Project setup
mkdir ~/purple_testing && cd ~/purple_testing
python3.9 -m venv venv
source venv/bin/activate
pip install pyyaml jinja2

# Run tests
python purple_os_test_native.py
```

## Amazon Linux 2 / AWS EC2

```bash
# Update and install
sudo yum update -y
sudo yum install -y python3 python3-pip git

# For AWS, consider instance profile for credentials
# Setup project
cd /home/ec2-user
git clone your-repo purple-testing
cd purple-testing

# Virtual environment
python3 -m venv venv
source venv/bin/activate
pip install pyyaml jinja2

# If using Systems Manager for scheduling
cat > /home/ec2-user/run_purple_test.sh << 'EOF'
#!/bin/bash
cd /home/ec2-user/purple-testing
source venv/bin/activate
python purple_os_test_native.py
aws s3 cp test_reports/ s3://your-bucket/purple-test-reports/ --recursive
EOF
chmod +x /home/ec2-user/run_purple_test.sh
```

## Debian 11 (Bullseye)

```bash
# Install dependencies
sudo apt update
sudo apt install -y python3 python3-pip python3-venv ssh git

# Create project structure
mkdir -p /opt/purple-testing/{logs,reports,results}
cd /opt/purple-testing

# Setup Python
python3 -m venv venv
source venv/bin/activate
pip install pyyaml jinja2

# Systemd integration
sudo tee /etc/systemd/system/purple-test@.service << EOF
[Unit]
Description=Purple OS Test for %i
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/purple-testing/venv/bin/python /opt/purple-testing/purple_os_test_native.py --device-ip %i
WorkingDirectory=/opt/purple-testing
StandardOutput=journal
StandardError=journal
EOF

# Run for specific device
sudo systemctl start purple-test@192.168.1.1.service
```

## Container-Optimized OS (CoreOS, Flatcar)

```bash
# Using podman/docker
cat > Containerfile << EOF
FROM registry.access.redhat.com/ubi8/python-39
USER root
RUN yum install -y openssh-clients
USER 1001
COPY requirements.txt .
RUN pip install pyyaml jinja2
COPY purple_os_test_native.py .
CMD ["python", "purple_os_test_native.py"]
EOF

# Build and run
podman build -t purple-test .
podman run -v $PWD/results:/app/results:Z purple-test
```

## Raspberry Pi (Raspbian)

```bash
# Install on Raspberry Pi
sudo apt update
sudo apt install -y python3-pip python3-venv git

# Temperature monitoring during tests
cat > monitor_temp.sh << 'EOF'
#!/bin/bash
while true; do
    temp=$(vcgencmd measure_temp | cut -d= -f2)
    echo "$(date): $temp" >> temperature.log
    sleep 60
done
EOF

# Run tests with monitoring
./monitor_temp.sh &
python3 purple_os_test_native.py
kill %1
```

## Jenkins Integration (Any Linux)

```groovy
pipeline {
    agent { label 'linux' }
    
    environment {
        DEVICE_IP = '192.168.1.1'
        VENV_DIR = "${WORKSPACE}/venv"
    }
    
    stages {
        stage('Setup') {
            steps {
                sh '''
                    python3 -m venv ${VENV_DIR}
                    . ${VENV_DIR}/bin/activate
                    pip install pyyaml jinja2
                '''
            }
        }
        
        stage('Test') {
            steps {
                sh '''
                    . ${VENV_DIR}/bin/activate
                    python purple_os_test_native.py --device-ip ${DEVICE_IP}
                '''
            }
        }
        
        stage('Archive') {
            steps {
                archiveArtifacts artifacts: 'test_reports/*.html', fingerprint: true
                publishHTML([
                    reportDir: 'test_reports',
                    reportFiles: '*.html',
                    reportName: 'Purple OS Test Report'
                ])
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
    }
}
```

## GitLab CI Integration

```yaml
# .gitlab-ci.yml
purple-os-test:
  image: python:3.9-slim
  before_script:
    - apt-get update && apt-get install -y openssh-client
    - pip install pyyaml jinja2
    - mkdir -p ~/.ssh
    - echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
    - chmod 600 ~/.ssh/id_rsa
  script:
    - python purple_os_test_native.py --device-ip $DEVICE_IP
  artifacts:
    paths:
      - test_reports/
    reports:
      junit: test_reports/junit.xml
    expire_in: 1 week
  only:
    - schedules
    - main
```

## Kubernetes CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: purple-os-tester
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: tester
            image: your-registry/purple-test:latest
            env:
            - name: DEVICE_IP
              value: "192.168.1.1"
            volumeMounts:
            - name: ssh-key
              mountPath: /root/.ssh
              readOnly: true
            - name: reports
              mountPath: /app/test_reports
          volumes:
          - name: ssh-key
            secret:
              secretName: purple-ssh-key
              defaultMode: 0600
          - name: reports
            persistentVolumeClaim:
              claimName: test-reports-pvc
          restartPolicy: OnFailure
```

## High Availability Setup (Multiple Servers)

```bash
# On each server
# 1. Install and setup as above
# 2. Use shared storage for results

# NFS mount for shared results
sudo mkdir -p /mnt/purple-tests
sudo mount -t nfs storage-server:/exports/purple-tests /mnt/purple-tests

# Modify config.yaml
echo "local_folder: '/mnt/purple-tests/results'" >> config.yaml

# Distributed testing with different device IPs
# Server 1
python purple_os_test_native.py --device-ip 192.168.1.1

# Server 2  
python purple_os_test_native.py --device-ip 192.168.1.2

# Server 3
python purple_os_test_native.py --device-ip 192.168.1.3
```

## Monitoring Integration (Prometheus)

```python
# Add to purple_os_test_native.py for metrics
from prometheus_client import start_http_server, Summary, Counter, Gauge

# Metrics
test_duration = Summary('purple_test_duration_seconds', 'Test duration')
test_total = Counter('purple_test_total', 'Total tests run', ['status'])
device_up = Gauge('purple_device_up', 'Device availability')

# Start metrics server
start_http_server(8000)

# In test methods
@test_duration.time()
def run_test():
    # test code
    test_total.labels(status='success').inc()
```

## Security Best Practices

```bash
# 1. Use dedicated user with minimal privileges
sudo useradd -r -s /bin/nologin purple-test-svc

# 2. Restrict SSH key usage
# In authorized_keys on device:
command="/bin/echo 'Test only'",no-port-forwarding,no-X11-forwarding ssh-rsa AAAA...

# 3. Use secrets management
# HashiCorp Vault example
vault write secret/purple-test device_ip=192.168.1.1
export DEVICE_IP=$(vault read -field=device_ip secret/purple-test)

# 4. Audit logging
auditctl -w /opt/purple-testing -p rwxa -k purple_test
```