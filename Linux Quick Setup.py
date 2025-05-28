#!/bin/bash
# Purple OS Testing Framework - Linux Quick Setup
# ===============================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Purple OS Testing Framework - Linux Setup${NC}"
echo "=========================================="
echo

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo -e "${RED}Cannot detect Linux distribution${NC}"
    exit 1
fi

echo -e "${GREEN}Detected: $PRETTY_NAME${NC}"

# Function to install packages based on distro
install_packages() {
    echo -e "${YELLOW}Installing system packages...${NC}"
    
    case $OS in
        ubuntu|debian)
            sudo apt update
            sudo apt install -y python3 python3-pip python3-venv ssh git
            ;;
        fedora|rhel|centos)
            sudo dnf install -y python3 python3-pip openssh-clients git || \
            sudo yum install -y python3 python3-pip openssh-clients git
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm python python-pip openssh git
            ;;
        opensuse*)
            sudo zypper install -y python3 python3-pip openssh git
            ;;
        *)
            echo -e "${RED}Unsupported distribution: $OS${NC}"
            echo "Please install manually: python3, pip, ssh, git"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}✓ System packages installed${NC}"
}

# Function to setup project
setup_project() {
    echo -e "${YELLOW}Setting up project directory...${NC}"
    
    # Get project directory
    read -p "Enter project directory [~/purple_os_testing]: " PROJECT_DIR
    PROJECT_DIR=${PROJECT_DIR:-~/purple_os_testing}
    PROJECT_DIR=$(eval echo "$PROJECT_DIR")  # Expand ~
    
    # Create directory
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # Create directory structure
    mkdir -p test_logs test_reports test_dashboards results logs archives
    
    echo -e "${GREEN}✓ Project directory created: $PROJECT_DIR${NC}"
}

# Function to setup Python environment
setup_python() {
    echo -e "${YELLOW}Setting up Python virtual environment...${NC}"
    
    # Create virtual environment
    python3 -m venv venv
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install Python packages
    echo "Installing Python packages..."
    pip install pyyaml jinja2
    
    # Optional packages
    read -p "Install optional packages (pandas, matplotlib, plotly)? [y/N]: " INSTALL_OPTIONAL
    if [[ "$INSTALL_OPTIONAL" =~ ^[Yy]$ ]]; then
        pip install pandas matplotlib plotly numpy || echo -e "${YELLOW}Some optional packages failed${NC}"
    fi
    
    echo -e "${GREEN}✓ Python environment ready${NC}"
}

# Function to setup SSH
setup_ssh() {
    echo -e "${YELLOW}Setting up SSH connection...${NC}"
    
    # Get device IP
    read -p "Enter Purple OS device IP [192.168.1.1]: " DEVICE_IP
    DEVICE_IP=${DEVICE_IP:-192.168.1.1}
    
    # Test basic connectivity
    echo "Testing network connectivity..."
    if ping -c 1 -W 2 "$DEVICE_IP" &> /dev/null; then
        echo -e "${GREEN}✓ Device is reachable${NC}"
    else
        echo -e "${YELLOW}⚠ Cannot ping device, continuing anyway${NC}"
    fi
    
    # SSH key setup
    read -p "Setup SSH key authentication? [Y/n]: " SETUP_KEY
    if [[ ! "$SETUP_KEY" =~ ^[Nn]$ ]]; then
        KEY_FILE="$HOME/.ssh/purple_os_key"
        
        if [ ! -f "$KEY_FILE" ]; then
            echo "Generating SSH key..."
            ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N ""
        else
            echo -e "${GREEN}✓ SSH key already exists${NC}"
        fi
        
        echo "Copying SSH key to device (you may need to enter password)..."
        ssh-copy-id -i "${KEY_FILE}.pub" "root@$DEVICE_IP" || \
            echo -e "${YELLOW}Failed to copy key, you can do it manually later${NC}"
        
        # Add to SSH config
        if ! grep -q "Host purple-os" ~/.ssh/config 2>/dev/null; then
            echo "Adding SSH config..."
            cat >> ~/.ssh/config << EOF

Host purple-os
    HostName $DEVICE_IP
    User root
    Port 22
    IdentityFile $KEY_FILE
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ControlMaster auto
    ControlPath ~/.ssh/control-%h-%p-%r
    ControlPersist 10m

EOF
            chmod 600 ~/.ssh/config
        fi
    fi
    
    # Test SSH connection
    echo "Testing SSH connection..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 root@$DEVICE_IP "echo 'SSH OK'" 2>/dev/null; then
        echo -e "${GREEN}✓ SSH connection successful${NC}"
    else
        echo -e "${YELLOW}⚠ SSH connection failed - check manually${NC}"
    fi
}

# Function to create test files
create_test_files() {
    echo -e "${YELLOW}Creating test files...${NC}"
    
    # Create config.yaml
    cat > config.yaml << EOF
# Purple OS Test Configuration
local_folder: "$PROJECT_DIR/results"

device:
  ip: "$DEVICE_IP"
  username: "root"
  port: 22

execution:
  max_workers: 10
  timeout: 30

tr181_parameters:
  device_info:
    - "Device.DeviceInfo.Manufacturer"
    - "Device.DeviceInfo.ModelName"
    - "Device.DeviceInfo.SoftwareVersion"
  network:
    - "Device.LAN.IPAddress"
    - "Device.WiFi.Radio.1.Enable"
EOF

    # Create run script
    cat > run_tests.sh << 'EOF'
#!/bin/bash
# Purple OS Test Runner

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Starting Purple OS Tests${NC}"

# Activate virtual environment
source venv/bin/activate

# Run tests with timestamp
timestamp=$(date +%Y%m%d_%H%M%S)
log_file="logs/test_run_${timestamp}.log"

# Create log directory
mkdir -p logs

# Run tests
echo "Starting tests at $(date)" | tee "$log_file"
python purple_os_test_native.py "$@" 2>&1 | tee -a "$log_file"
exit_code=$?

# Deactivate virtual environment
deactivate

echo "Tests completed at $(date)" | tee -a "$log_file"
echo "Exit code: $exit_code" | tee -a "$log_file"

# Show results location
if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}✓ Tests completed successfully${NC}"
    echo "Results available in:"
    echo "  - Reports: test_reports/"
    echo "  - Logs: test_logs/"
    echo "  - Device data: results/"
fi

exit $exit_code
EOF
    chmod +x run_tests.sh

    # Create systemd service files
    mkdir -p systemd
    
    cat > systemd/purple-os-test.service << EOF
[Unit]
Description=Purple OS Automated Testing
After=network.target

[Service]
Type=oneshot
User=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/run_tests.sh
StandardOutput=journal
StandardError=journal
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
EOF

    cat > systemd/purple-os-test.timer << EOF
[Unit]
Description=Run Purple OS tests daily at 2 AM
Requires=purple-os-test.service

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Create simple test script
    cat > test_connection.py << EOF
#!/usr/bin/env python3
import subprocess
import sys

print("Testing SSH connection to $DEVICE_IP...")
try:
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", 
         "root@$DEVICE_IP", "echo 'Connection OK'"],
        capture_output=True, text=True, timeout=10
    )
    if result.returncode == 0:
        print("✓ SSH connection successful!")
        print(f"Device response: {result.stdout.strip()}")
    else:
        print("✗ SSH connection failed")
        print(f"Error: {result.stderr}")
        sys.exit(1)
except Exception as e:
    print(f"✗ Error: {e}")
    sys.exit(1)
EOF
    chmod +x test_connection.py

    echo -e "${GREEN}✓ Test files created${NC}"
}

# Function to download test framework
download_framework() {
    echo -e "${YELLOW}Downloading test framework...${NC}"
    
    # Check if purple_os_test_native.py exists
    if [ ! -f purple_os_test_native.py ]; then
        echo -e "${YELLOW}purple_os_test_native.py not found${NC}"
        echo "Please copy the test framework file to: $PROJECT_DIR"
        echo "Then run: ./run_tests.sh"
        return 1
    fi
    
    return 0
}

# Main setup flow
main() {
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}Please don't run this script as root${NC}"
        exit 1
    fi
    
    # Install system packages
    install_packages
    
    # Setup project
    setup_project
    
    # Setup Python
    setup_python
    
    # Setup SSH
    setup_ssh
    
    # Create test files
    create_test_files
    
    # Download framework
    download_framework
    
    # Final instructions
    echo
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Setup completed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo
    echo "Project directory: $PROJECT_DIR"
    echo
    echo "Next steps:"
    echo "1. Copy purple_os_test_native.py to $PROJECT_DIR"
    echo "2. Run tests: ./run_tests.sh"
    echo
    echo "Quick test commands:"
    echo "  cd $PROJECT_DIR"
    echo "  source venv/bin/activate"
    echo "  python test_connection.py    # Test SSH"
    echo "  python purple_os_test_native.py    # Run full tests"
    echo "  deactivate"
    echo
    echo "For automated daily tests:"
    echo "  sudo cp systemd/purple-os-test.* /etc/systemd/system/"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable purple-os-test.timer"
    echo
    
    # Offer to run test
    read -p "Run connection test now? [Y/n]: " RUN_TEST
    if [[ ! "$RUN_TEST" =~ ^[Nn]$ ]]; then
        echo
        ./test_connection.py
    fi
}

# Run main
main