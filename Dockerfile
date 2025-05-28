# Dockerfile for Purple OS Testing Framework
FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    openssh-client \
    git \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Create necessary directories
RUN mkdir -p test_logs test_reports test_dashboards results

# Install Python dependencies
COPY requirements_docker.txt .
RUN pip install --no-cache-dir -r requirements_docker.txt

# Copy test framework
COPY purple_os_test_native.py .
COPY config.yaml .

# Copy scripts
COPY docker_scripts/entrypoint.sh /entrypoint.sh
COPY docker_scripts/scheduler.sh /app/scheduler.sh
RUN chmod +x /entrypoint.sh /app/scheduler.sh

# Set up SSH config for better performance
RUN mkdir -p /root/.ssh && \
    echo "Host *" >> /root/.ssh/config && \
    echo "    StrictHostKeyChecking no" >> /root/.ssh/config && \
    echo "    UserKnownHostsFile /dev/null" >> /root/.ssh/config && \
    echo "    ControlMaster auto" >> /root/.ssh/config && \
    echo "    ControlPath /tmp/ssh-%r@%h:%p" >> /root/.ssh/config && \
    echo "    ControlPersist 10m" >> /root/.ssh/config && \
    chmod 600 /root/.ssh/config

# Volume mount points
VOLUME ["/app/test_logs", "/app/test_reports", "/app/test_dashboards", "/app/results"]

# Default environment variables
ENV DEVICE_IP=192.168.1.1
ENV DEVICE_USERNAME=root
ENV MAX_WORKERS=10

# Entry point
ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "purple_os_test_native.py"]