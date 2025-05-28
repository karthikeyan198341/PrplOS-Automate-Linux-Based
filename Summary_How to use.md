# Purple OS Testing on Linux - Complete Summary

## Quick Start Options

### 1. Fastest (One Command)
```bash
curl -sSL https://your-url/linux_quick_setup.sh | bash
```

### 2. Manual Quick Setup
```bash
# Install packages (Ubuntu/Debian)
sudo apt update && sudo apt install -y python3 python3-pip python3-venv ssh

# Setup and run
mkdir purple_test && cd purple_test
python3 -m venv venv && source venv/bin/activate
pip install pyyaml jinja2
# Copy purple_os_test_native.py here
python purple_os_test_native.py
```

### 3. Docker Option
```bash
docker run --rm -v $PWD:/app/results \
  -e DEVICE_IP=192.168.1.1 \
  your-registry/purple-test:latest
```

## File Overview

I've created these files for your Linux deployment:

1. **LINUX_SETUP_GUIDE.md** - Comprehensive setup guide for all Linux distributions
2. **linux_quick_setup.sh** - Automated setup script with distribution detection
3. **LINUX_QUICK_START.txt** - Quick command reference
4. **docker-compose.yml** - Docker deployment with web server for reports
5. **Dockerfile** - Container setup
6. **deploy_purple_test.yml** - Ansible playbook for multiple servers
7. **LINUX_SERVER_EXAMPLES.md** - Real-world examples for different servers
8. **install.sh** - Simple one-line installer

## Key Advantages on Linux

1. **Native SSH** - No paramiko needed, uses system SSH
2. **Better Performance** - SSH multiplexing, connection pooling
3. **Easy Automation** - Cron, systemd timers, CI/CD integration
4. **No Dependencies** - Just PyYAML and Jinja2
5. **Container Ready** - Docker/Podman support included

## Deployment Methods

### Standalone Server
- Use `linux_quick_setup.sh` for automated setup
- Creates virtual environment, installs dependencies
- Sets up SSH keys and systemd services

### Docker Container
- Use provided Dockerfile and docker-compose.yml
- Includes web server for viewing reports
- Scheduler for periodic testing

### Ansible Deployment
- Use `deploy_purple_test.yml` for multiple servers
- Creates dedicated user, sets up services
- Handles log rotation and monitoring

### CI/CD Integration
- Examples provided for Jenkins, GitLab CI
- Kubernetes CronJob for cloud deployment

## Common Commands

```bash
# Run tests
./run.sh

# Run with custom IP
python purple_os_test_native.py --device-ip 192.168.1.100

# Run in background
nohup ./run.sh > test.log 2>&1 &

# View latest report
ls -lt test_reports/*.html | head -1

# Monitor logs
tail -f test_logs/*.log

# Schedule with cron
0 */6 * * * /home/user/purple_os_testing/run.sh

# Check systemd timer
systemctl status purple-os-test.timer
```

## Directory Structure
```
~/purple_os_testing/
├── venv/                    # Python virtual environment
├── test_logs/              # Test execution logs
├── test_reports/           # HTML reports
├── test_dashboards/        # Dashboard files
├── results/                # Device data
│   └── {variant}_results_folder/
├── purple_os_test_native.py
├── config.yaml
├── run.sh
└── requirements.txt
```

## Security Recommendations

1. Use dedicated user account
2. Set up SSH key authentication
3. Restrict SSH key permissions
4. Use read-only mounts for Docker
5. Enable SELinux/AppArmor if available
6. Regular log rotation

## Monitoring Integration

- Prometheus metrics endpoint
- JSON output for parsing
- Syslog integration via journald
- Email notifications (optional)

## Troubleshooting

Most issues are SSH-related:
```bash
# Debug SSH connection
ssh -vvv root@192.168.1.1

# Check SSH key permissions
chmod 600 ~/.ssh/purple_os_key
chmod 700 ~/.ssh

# Test with password
ssh -o PreferredAuthentications=password root@192.168.1.1
```

## Next Steps

1. Choose your deployment method
2. Run the appropriate setup script
3. Configure config.yaml if needed
4. Set up automation (cron/systemd/CI)
5. Monitor results

The native SSH version eliminates all Python dependency issues while providing better performance and Linux integration!