#!/bin/bash
# Simple installer for Purple OS Testing Framework
# Just run: curl -sSL https://your-url/install.sh | bash

set -e

echo "Purple OS Testing - Quick Install"
echo "================================"

# Detect Python
if command -v python3 &> /dev/null; then
    PYTHON=python3
elif command -v python &> /dev/null; then
    PYTHON=python
else
    echo "Error: Python not found. Please install Python 3 first."
    exit 1
fi

# Create directory
DIR="$HOME/purple_os_testing"
mkdir -p "$DIR"
cd "$DIR"

# Download test framework
echo "Downloading test framework..."
cat > purple_os_test_native.py << 'FRAMEWORK_EOF'
# Insert purple_os_test_native.py content here
# This would be the actual framework code
FRAMEWORK_EOF

# Create minimal requirements
cat > requirements.txt << EOF
pyyaml>=6.0
jinja2>=3.0
EOF

# Setup virtual environment
echo "Setting up Python environment..."
$PYTHON -m venv venv
source venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt

# Create run script
cat > run.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
python purple_os_test_native.py "$@"
EOF
chmod +x run.sh

# Create config
cat > config.yaml << EOF
local_folder: "$DIR/results"
device:
  ip: "192.168.1.1"
  username: "root"
EOF

# Test SSH
echo
echo -n "Testing SSH connection to 192.168.1.1... "
if ssh -o BatchMode=yes -o ConnectTimeout=3 root@192.168.1.1 "echo OK" &>/dev/null; then
    echo "SUCCESS"
else
    echo "FAILED"
    echo
    echo "Please ensure:"
    echo "  1. Device is at IP 192.168.1.1"
    echo "  2. SSH is enabled on device"
    echo "  3. Root login without password is allowed"
fi

echo
echo "Installation complete!"
echo
echo "To run tests:"
echo "  cd $DIR"
echo "  ./run.sh"
echo
echo "Or directly:"
echo "  $DIR/run.sh"

# Offer to run now
echo
read -p "Run test now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    ./run.sh
fi