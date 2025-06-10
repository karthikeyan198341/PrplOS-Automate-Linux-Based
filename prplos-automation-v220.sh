#!/bin/bash

# =============================================================================
# PrplOS Build Automation Suite - Enhanced Version
# =============================================================================
# File: prplos-automation-v2.2.0.sh
# Description: Enhanced build automation for embedded systems development
# Author: Auto-generated for prplOS development with BCMSDK integration
# Version: 2.2.0 - Fixed Docker/Sudo issues, Removed Dashboard, Text Reports
# =============================================================================

set -euo pipefail

# =============================================================================
# GLOBAL CONFIGURATION
# =============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="${SCRIPT_DIR}"
readonly LOG_DIR="${PROJECT_ROOT}/logs"
readonly REPORTS_DIR="${PROJECT_ROOT}/reports"
readonly DOCKER_DIR="${PROJECT_ROOT}/docker"
readonly HELPERS_DIR="${PROJECT_ROOT}/helpers"

# Build Configuration
readonly PRPLOS_REPO="https://git.openwrt.org/openwrt/openwrt.git"
readonly TARGET_PACKAGE="netifd"
readonly BUILD_CORES="$(nproc)"

# Performance Tracking
declare -A BUILD_METRICS
declare -A TIMING_DATA
TOTAL_START_TIME=""
TOTAL_END_TIME=""

# Environment Setup
export DEBIAN_FRONTEND=noninteractive
export FORCE_UNSAFE_CONFIGURE=1
export CI=true

# Docker User Configuration
readonly DOCKER_UID=$(id -u)
readonly DOCKER_GID=$(id -g)
readonly DOCKER_USER="${USER}"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Logging Functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_DIR}/automation.log"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_DIR}/automation.log" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "${LOG_DIR}/automation.log"
}

log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" | tee -a "${LOG_DIR}/automation.log"
}

# Performance Monitoring
start_timer() {
    local phase="$1"
    TIMING_DATA["${phase}_start"]=$(date +%s.%N)
    log_info "Started phase: $phase"
}

end_timer() {
    local phase="$1"
    TIMING_DATA["${phase}_end"]=$(date +%s.%N)
    local start_time="${TIMING_DATA[${phase}_start]:-$(date +%s.%N)}"
    local end_time="${TIMING_DATA[${phase}_end]:-$(date +%s.%N)}"
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    BUILD_METRICS["$phase"]="$duration"
    log_info "Completed phase: $phase (Duration: ${duration}s)"
}

# System Resource Monitoring
monitor_resources() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    local memory_usage=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}' 2>/dev/null || echo "0")
    local disk_usage=$(df "${PROJECT_ROOT}" | tail -1 | awk '{print $5}' | cut -d'%' -f1 2>/dev/null || echo "0")
    
    echo "CPU: ${cpu_usage}% | Memory: ${memory_usage}% | Disk: ${disk_usage}%" >> "${REPORTS_DIR}/resource_usage.txt"
}

# Progress Tracking
update_progress() {
    local step="$1"
    local total="$2"
    local current="$3"
    local message="$4"
    
    local percentage=$((current * 100 / total))
    log_info "Progress: $step ($current/$total) - $percentage% - $message"
}

# Safe directory operations
safe_cd() {
    local target_dir="$1"
    
    if [[ ! -d "$target_dir" ]]; then
        log_error "Directory does not exist: $target_dir"
        return 1
    fi
    
    cd "$target_dir" || {
        log_error "Failed to change to directory: $target_dir"
        return 1
    }
    
    log_debug "Changed to directory: $(pwd)"
    return 0
}

# Git Helper Functions
is_git_repository() {
    git rev-parse --git-dir &> /dev/null
}

ensure_git_repository() {
    local repo_dir="$1"
    local repo_url="$2"
    
    log_info "Ensuring Git repository exists at: $repo_dir"
    
    if [[ ! -d "$repo_dir" ]]; then
        log_info "Repository directory does not exist, creating: $repo_dir"
        mkdir -p "$repo_dir"
    fi
    
    safe_cd "$repo_dir" || return 1
    
    if ! is_git_repository; then
        log_info "Not a Git repository, cloning from: $repo_url"
        cd ..
        rm -rf "$(basename "$repo_dir")"
        git clone "$repo_url" "$(basename "$repo_dir")" || {
            log_error "Failed to clone repository"
            return 1
        }
        safe_cd "$repo_dir" || return 1
    else
        log_info "Git repository exists, checking status"
        git status --porcelain > /dev/null 2>&1 || {
            log_warn "Git repository may be corrupted, re-cloning"
            cd ..
            rm -rf "$(basename "$repo_dir")"
            git clone "$repo_url" "$(basename "$repo_dir")" || {
                log_error "Failed to clone repository"
                return 1
            }
            safe_cd "$repo_dir" || return 1
        }
    fi
    
    log_info "Git repository ready at: $(pwd)"
    return 0
}

setup_git_branch() {
    local branch_name="$1"
    local create_new="${2:-false}"
    
    log_info "Setting up Git branch: $branch_name"
    
    if ! is_git_repository; then
        log_error "Not in a Git repository"
        return 1
    fi
    
    # Fetch latest changes
    git fetch origin 2>/dev/null || {
        log_warn "Failed to fetch from origin, continuing anyway"
    }
    
    # Check if branch exists locally
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        log_info "Branch $branch_name exists locally, checking out"
        git checkout "$branch_name" || {
            log_error "Failed to checkout branch $branch_name"
            return 1
        }
    elif git show-ref --verify --quiet "refs/remotes/origin/$branch_name"; then
        log_info "Branch $branch_name exists remotely, creating local tracking branch"
        git checkout -b "$branch_name" "origin/$branch_name" || {
            log_error "Failed to create tracking branch $branch_name"
            return 1
        }
    elif [[ "$create_new" == "true" ]]; then
        log_info "Creating new branch: $branch_name"
        git checkout -b "$branch_name" || {
            log_error "Failed to create new branch $branch_name"
            return 1
        }
    else
        log_warn "Branch $branch_name does not exist, staying on current branch"
        return 1
    fi
    
    log_info "Successfully set up branch: $(git branch --show-current)"
    return 0
}

# Docker Helper Functions - FIXED FOR SUDO ISSUES
fix_docker_permissions() {
    local workspace_path="$1"
    
    log_info "Fixing workspace permissions for: $workspace_path"
    
    if [[ ! -d "$workspace_path" ]]; then
        log_error "Workspace path does not exist: $workspace_path"
        return 1
    fi
    
    # Create all required OpenWRT directories first
    mkdir -p "$workspace_path"/{feeds,tmp,staging_dir,build_dir,bin,logs,dl}
    mkdir -p "$workspace_path"/feeds/{packages,luci,routing,telephony,video,base,management}
    mkdir -p "$workspace_path"/tmp/{info,work,ipkg-info}
    
    # Fix permissions without Docker sudo issues
    if command -v docker &> /dev/null; then
        # Use current user's UID/GID in Docker to avoid permission issues
        docker run --rm \
            -v "${workspace_path}:/workspace" \
            -e LOCAL_UID="${DOCKER_UID}" \
            -e LOCAL_GID="${DOCKER_GID}" \
            ubuntu:22.04 /bin/bash -c "
            # Create user with same UID/GID as host
            groupadd -g \${LOCAL_GID} builduser 2>/dev/null || true
            useradd -u \${LOCAL_UID} -g \${LOCAL_GID} -m builduser 2>/dev/null || true
            
            # Fix permissions as root, then change ownership
            cd /workspace
            mkdir -p feeds/{packages,luci,routing,telephony,video,base,management} tmp/{info,work,ipkg-info} staging_dir build_dir bin logs dl
            chmod -R 755 .
            find . -type d -exec chmod 755 {} \;
            find . -type f -name '*.sh' -exec chmod +x {} \;
            
            # Change ownership to match host user
            chown -R \${LOCAL_UID}:\${LOCAL_GID} .
        " 2>&1 | tee -a "${LOG_DIR}/docker_permissions.log" || {
            log_warn "Docker permission fix had warnings, continuing..."
        }
    else
        # Direct permission fix without Docker
        chmod -R 755 "${workspace_path}" 2>/dev/null || true
        find "${workspace_path}" -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
    fi
    
    log_info "Permissions fixed for: $workspace_path"
}

run_docker_command() {
    local workspace_path="$1"
    local command="$2"
    local fallback="${3:-true}"
    
    if command -v docker &> /dev/null && docker images | grep -q prplos-dev; then
        log_debug "Running Docker command: $command"
        
        # Run command with proper user mapping to avoid sudo issues
        if docker run --rm \
            -v "${workspace_path}:/workspace" \
            -e LOCAL_UID="${DOCKER_UID}" \
            -e LOCAL_GID="${DOCKER_GID}" \
            -e HOME=/tmp \
            --user "${DOCKER_UID}:${DOCKER_GID}" \
            prplos-dev:latest /bin/bash -c "cd /workspace && $command"; then
            return 0
        elif [[ "$fallback" == "true" ]]; then
            log_warn "Docker command failed, running directly"
            safe_cd "$workspace_path" && eval "$command"
        else
            return 1
        fi
    elif [[ "$fallback" == "true" ]]; then
        log_info "Docker not available, running command directly"
        safe_cd "$workspace_path" && eval "$command"
    else
        log_error "Docker not available and fallback disabled"
        return 1
    fi
}

# Enhanced Feeds Management
prepare_feeds_environment() {
    local workspace_dir="$1"
    
    log_info "Preparing feeds environment in: $workspace_dir"
    
    # Clean any existing problematic feeds state
    rm -rf feeds/* 2>/dev/null || true
    rm -f feeds.conf feeds.conf.backup 2>/dev/null || true
    
    # Create comprehensive feeds directory structure
    mkdir -p feeds/{packages,luci,routing,telephony,video,base,management}
    mkdir -p tmp/{info,work,ipkg-info}
    mkdir -p staging_dir build_dir bin logs dl
    
    # Set comprehensive permissions
    chmod -R 755 feeds 2>/dev/null || true
    chmod -R u+w . 2>/dev/null || true
    
    # Regenerate feeds configuration
    if [[ -f feeds.conf.default ]]; then
        cp feeds.conf.default feeds.conf
        log_info "Regenerated feeds.conf from default"
    fi
    
    log_info "Feeds environment prepared successfully"
}

# Build Environment Setup
prepare_build_environment() {
    local workspace_type="$1"
    local workspace_path="${PROJECT_ROOT}/workspace/${workspace_type}"
    
    log_info "Preparing build environment for: $workspace_type"
    
    # Create workspace directory
    mkdir -p "$workspace_path"
    
    # Ensure OpenWRT repository
    ensure_git_repository "${workspace_path}/openwrt" "$PRPLOS_REPO" || {
        log_error "Failed to prepare OpenWRT repository"
        return 1
    }
    
    # Change to the OpenWRT directory
    safe_cd "${workspace_path}/openwrt" || {
        log_error "Failed to access OpenWRT directory"
        return 1
    }
    
    # Pre-create all necessary directories with proper permissions
    log_info "Creating OpenWRT build directories..."
    mkdir -p {feeds,tmp,staging_dir,build_dir,bin,logs,dl}
    mkdir -p feeds/{packages,luci,routing,telephony,video,base,management}
    mkdir -p tmp/{info,work,ipkg-info}
    
    # Set comprehensive permissions
    chmod -R u+w . 2>/dev/null || true
    chmod -R 755 feeds 2>/dev/null || true
    
    # Fix permissions for operations
    fix_docker_permissions "$(pwd)"
    
    # Prepare feeds environment
    prepare_feeds_environment "$(pwd)"
    
    log_info "Build environment prepared: $workspace_path"
    return 0
}

# =============================================================================
# INITIALIZATION FUNCTIONS
# =============================================================================

check_dependencies() {
    log_info "Checking system dependencies..."
    local deps=("git" "python3" "bc" "curl" "make" "gcc")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Please install missing dependencies and try again"
        return 1
    fi
    
    # Check Docker separately (optional)
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not available - will use direct build methods"
    else
        log_info "Docker available for containerized builds"
        # Check if user can run Docker without sudo
        if ! docker ps &>/dev/null; then
            log_warn "Docker requires sudo or user not in docker group"
            log_info "Add user to docker group: sudo usermod -aG docker $USER"
        fi
    fi
    
    log_info "All required dependencies satisfied"
}

setup_project_structure() {
    log_info "Setting up project structure..."
    
    local directories=(
        "$LOG_DIR"
        "$REPORTS_DIR"
        "$DOCKER_DIR"
        "$HELPERS_DIR"
        "${PROJECT_ROOT}/workspace"
        "${PROJECT_ROOT}/workspace/traditional"
        "${PROJECT_ROOT}/workspace/modern"
        "${PROJECT_ROOT}/builds"
        "${PROJECT_ROOT}/configs"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        log_debug "Created directory: $dir"
    done
    
    # Set proper permissions
    find "${HELPERS_DIR}" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
    
    log_info "Project structure setup complete"
}

# =============================================================================
# BUILD METHODS
# =============================================================================

build_traditional() {
    log_info "Starting traditional build approach..."
    start_timer "traditional_build"
    
    local workspace="${PROJECT_ROOT}/workspace/traditional"
    local original_dir="$(pwd)"
    
    # Prepare build environment
    prepare_build_environment "traditional" || {
        log_error "Failed to prepare traditional build environment"
        end_timer "traditional_build"
        return 1
    }
    
    update_progress "traditional" 5 1 "Setting up traditional OpenWRT repository"
    
    # Ensure we're in the correct directory
    safe_cd "${workspace}/openwrt" || {
        log_error "Failed to access OpenWRT directory"
        cd "$original_dir"
        end_timer "traditional_build"
        return 1
    }
    
    # Pre-create feeds directories and fix permissions
    log_info "Preparing feeds directories for traditional build..."
    prepare_feeds_environment "$(pwd)"
    
    update_progress "traditional" 5 2 "Updating feeds (traditional)"
    log_info "Updating package feeds..."
    
    # Run feeds update with comprehensive error handling
    local feeds_update_success=false
    if ./scripts/feeds update -a 2>&1 | tee "${LOG_DIR}/traditional_feeds.log"; then
        log_info "Feeds update completed successfully"
        feeds_update_success=true
    else
        log_warn "Feeds update had issues, attempting individual feeds..."
        # Try individual feed updates
        for feed in packages luci routing telephony; do
            log_info "Attempting individual update for feed: $feed"
            if ./scripts/feeds update "$feed" 2>/dev/null; then
                log_info "Successfully updated feed: $feed"
            else
                log_warn "Failed to update feed: $feed"
            fi
        done
        feeds_update_success=true  # Continue even if some feeds fail
    fi
    
    if [[ "$feeds_update_success" == "true" ]]; then
        log_info "Installing package feeds..."
        if ./scripts/feeds install -a 2>&1 | tee -a "${LOG_DIR}/traditional_feeds.log"; then
            log_info "Feeds install completed successfully"
        else
            log_warn "Feeds install had issues, attempting essential packages only..."
            # Install essential packages individually
            for pkg in base-files busybox kernel netifd opkg uci; do
                ./scripts/feeds install "$pkg" 2>/dev/null || log_warn "Failed to install: $pkg"
            done
        fi
    fi
    
    update_progress "traditional" 5 3 "Configuring traditional build"
    log_info "Setting up build configuration..."
    if [[ -f "${PROJECT_ROOT}/configs/traditional-config.conf" ]]; then
        cp "${PROJECT_ROOT}/configs/traditional-config.conf" .config
        log_info "Applied custom traditional configuration"
        make oldconfig < /dev/null 2>/dev/null || make defconfig
    else
        log_info "Using default configuration"
        make defconfig
    fi
    
    update_progress "traditional" 5 4 "Building with traditional method"
    log_info "Starting traditional build process..."
    if make -j"$BUILD_CORES" V=s 2>&1 | tee "${LOG_DIR}/traditional_build.log"; then
        log_info "Traditional build completed successfully"
        update_progress "traditional" 5 5 "Traditional build complete"
    else
        log_error "Traditional build failed"
        cd "$original_dir"
        end_timer "traditional_build"
        return 1
    fi
    
    # Return to original directory
    cd "$original_dir"
    end_timer "traditional_build"
    log_info "Traditional build approach completed"
}

build_modern() {
    log_info "Starting modern build approach..."
    start_timer "modern_build"
    
    local workspace="${PROJECT_ROOT}/workspace/modern"
    local original_dir="$(pwd)"
    
    # Prepare build environment
    prepare_build_environment "modern" || {
        log_error "Failed to prepare modern build environment"
        end_timer "modern_build"
        return 1
    }
    
    update_progress "modern" 6 1 "Setting up modern Git workflow"
    
    # Ensure we're in the correct directory
    safe_cd "${workspace}/openwrt" || {
        log_error "Failed to access OpenWRT directory"
        cd "$original_dir"
        end_timer "modern_build"
        return 1
    }
    
    # Set up Git workflow
    log_info "Setting up Git feature branch workflow..."
    setup_git_branch "feature/enhanced-netifd-$(date +%s)" true || {
        log_warn "Failed to create feature branch, using current branch"
    }
    
    update_progress "modern" 6 2 "Applying modern configurations"
    log_info "Setting up modern build configuration..."
    if [[ -f "${PROJECT_ROOT}/configs/modern-config.conf" ]]; then
        cp "${PROJECT_ROOT}/configs/modern-config.conf" .config
        log_info "Applied custom modern configuration"
        make oldconfig < /dev/null 2>/dev/null || make defconfig
    else
        log_info "Using default configuration"
        make defconfig
    fi
    
    update_progress "modern" 6 3 "Preparing Docker environment"
    # Check if Docker is available and build image if needed
    if command -v docker &> /dev/null; then
        if [[ -f "${DOCKER_DIR}/Dockerfile" ]]; then
            if ! docker images | grep -q prplos-dev; then
                log_info "Building Docker development environment..."
                cd "$original_dir"
                
                # Create a Dockerfile if it doesn't exist
                if [[ ! -f "${DOCKER_DIR}/Dockerfile" ]]; then
                    cat > "${DOCKER_DIR}/Dockerfile" << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    ccache \
    ecj \
    fastjar \
    file \
    g++ \
    gawk \
    gettext \
    git \
    java-propose-classpath \
    libelf-dev \
    libncurses5-dev \
    libncursesw5-dev \
    libssl-dev \
    python3 \
    python3-dev \
    python3-distutils \
    python3-setuptools \
    rsync \
    subversion \
    swig \
    time \
    unzip \
    wget \
    xsltproc \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Create build user
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g ${GROUP_ID} prplos && \
    useradd -m -u ${USER_ID} -g prplos prplos

WORKDIR /workspace
EOF
                fi
                
                docker build \
                    --build-arg USER_ID="${DOCKER_UID}" \
                    --build-arg GROUP_ID="${DOCKER_GID}" \
                    -f "${DOCKER_DIR}/Dockerfile" \
                    -t prplos-dev:latest . || {
                    log_warn "Docker build failed, will use direct build"
                }
                safe_cd "${workspace}/openwrt"
            else
                log_info "Docker development environment already available"
            fi
        else
            log_warn "Docker configuration not found, using direct build"
        fi
    else
        log_info "Docker not available, using direct build"
    fi
    
    update_progress "modern" 6 4 "Updating feeds (modern)"
    log_info "Updating package feeds in modern environment..."
    
    # Pre-create feeds directories and fix permissions
    prepare_feeds_environment "$(pwd)"
    fix_docker_permissions "$(pwd)"
    
    # Try containerized feeds update first, with comprehensive fallback
    local feeds_success=false
    if command -v docker &> /dev/null && docker images | grep -q prplos-dev; then
        log_info "Attempting containerized feeds update..."
        if run_docker_command "$(pwd)" "./scripts/feeds update -a && ./scripts/feeds install -a" false; then
            log_info "Containerized feeds update successful"
            feeds_success=true
        else
            log_warn "Containerized feeds update failed, trying direct method"
        fi
    fi
    
    # Direct feeds update if containerized failed or not available
    if [[ "$feeds_success" == "false" ]]; then
        log_info "Running feeds update directly..."
        if ./scripts/feeds update -a 2>&1 | tee "${LOG_DIR}/modern_feeds_direct.log"; then
            log_info "Direct feeds update successful"
            ./scripts/feeds install -a 2>&1 | tee -a "${LOG_DIR}/modern_feeds_direct.log" || {
                log_warn "Feeds install had issues, installing essential packages..."
                for pkg in base-files busybox kernel netifd opkg uci; do
                    ./scripts/feeds install "$pkg" 2>/dev/null || log_warn "Failed to install: $pkg"
                done
            }
        else
            log_warn "Direct feeds update failed, continuing anyway..."
        fi
    fi
    
    update_progress "modern" 6 5 "Building with modern approach"
    log_info "Starting modern build process..."
    
    # Try containerized build first, fallback to direct
    local build_success=false
    if command -v docker &> /dev/null && docker images | grep -q prplos-dev; then
        log_info "Attempting containerized build..."
        if run_docker_command "$(pwd)" "make -j$BUILD_CORES V=s" false; then
            log_info "Containerized build completed successfully"
            build_success=true
        else
            log_warn "Containerized build failed, trying direct build"
        fi
    fi
    
    # Direct build if containerized failed or not available
    if [[ "$build_success" == "false" ]]; then
        log_info "Running direct build..."
        if make -j"$BUILD_CORES" V=s 2>&1 | tee "${LOG_DIR}/modern_build.log"; then
            log_info "Direct modern build completed successfully"
            build_success=true
        else
            log_error "Modern build failed"
            cd "$original_dir"
            end_timer "modern_build"
            return 1
        fi
    fi
    
    if [[ "$build_success" == "true" ]]; then
        update_progress "modern" 6 6 "Modern build complete"
        log_info "Modern build approach completed successfully"
    fi
    
    # Return to original directory
    cd "$original_dir"
    end_timer "modern_build"
    log_info "Modern build approach completed"
}

build_comparison() {
    log_info "Running comparative build analysis..."
    start_timer "comparison_analysis"
    
    # Run both builds sequentially for fair comparison
    log_info "Starting traditional build for comparison..."
    if build_traditional; then
        log_info "Traditional build completed for comparison"
    else
        log_error "Traditional build failed in comparison"
    fi
    
    sleep 2
    
    log_info "Starting modern build for comparison..."
    if build_modern; then
        log_info "Modern build completed for comparison"
    else
        log_error "Modern build failed in comparison"
    fi
    
    # Generate text comparison report
    generate_text_comparison_report
    
    end_timer "comparison_analysis"
    log_info "Comparative analysis completed"
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

cleanup_environment() {
    log_info "Cleaning up build environment..."
    
    # Clean workspace
    if [[ -d "${PROJECT_ROOT}/workspace" ]]; then
        log_info "Cleaning workspace..."
        find "${PROJECT_ROOT}/workspace" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null || true
    fi
    
    # Clean builds
    if [[ -d "${PROJECT_ROOT}/builds" ]]; then
        log_info "Cleaning build artifacts..."
        rm -rf "${PROJECT_ROOT}/builds"/* 2>/dev/null || true
    fi
    
    # Clean Docker containers and images
    if command -v docker &> /dev/null; then
        log_info "Cleaning Docker resources..."
        docker container prune -f 2>/dev/null || true
        docker image prune -f 2>/dev/null || true
    fi
    
    # Archive logs
    if [[ -d "$LOG_DIR" ]] && [[ -n "$(ls -A "$LOG_DIR" 2>/dev/null)" ]]; then
        local archive_name="logs_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "${PROJECT_ROOT}/${archive_name}" -C "$LOG_DIR" . 2>/dev/null || {
            log_warn "Failed to archive logs"
        }
        if [[ -f "${PROJECT_ROOT}/${archive_name}" ]]; then
            log_info "Logs archived to: $archive_name"
            rm -f "${LOG_DIR}"/*.log 2>/dev/null || true
        fi
    fi
    
    log_info "Cleanup completed"
}

# =============================================================================
# REPORTING FUNCTIONS - TEXT FORMAT ONLY
# =============================================================================

generate_performance_report() {
    log_info "Generating performance report..."
    
    local report_file="${REPORTS_DIR}/performance_report_$(date +%Y%m%d_%H%M%S).txt"
    
    # Calculate total execution time
    if [[ -n "$TOTAL_START_TIME" ]] && [[ -n "$TOTAL_END_TIME" ]]; then
        local total_duration=$(echo "$TOTAL_END_TIME - $TOTAL_START_TIME" | bc -l 2>/dev/null || echo "0")
        BUILD_METRICS["total_execution"]="$total_duration"
    fi
    
    # Generate professional text report
    create_text_report "$report_file"
    
    log_info "Performance report generated: $report_file"
}

create_text_report() {
    local report_file="$1"
    
    cat > "$report_file" << EOF
================================================================================
                    PrplOS Build Performance Report
                 Enhanced Embedded Systems Development
================================================================================
Generated: $(date)
Version: 2.2.0 - Optimized for BCMSDK Integration

================================================================================
BUILD METRICS SUMMARY
================================================================================

EOF
    
    if [[ ${#BUILD_METRICS[@]} -gt 0 ]]; then
        # Sort metrics for better readability
        for metric in total_execution traditional_build modern_build comparison_analysis; do
            if [[ -n "${BUILD_METRICS[$metric]}" ]]; then
                printf "%-30s: %10.2f seconds\n" "$metric" "${BUILD_METRICS[$metric]}" >> "$report_file"
            fi
        done
        
        echo "" >> "$report_file"
        echo "Other Metrics:" >> "$report_file"
        for metric in "${!BUILD_METRICS[@]}"; do
            if [[ "$metric" != "total_execution" && "$metric" != "traditional_build" && "$metric" != "modern_build" && "$metric" != "comparison_analysis" ]]; then
                printf "%-30s: %10.2f seconds\n" "$metric" "${BUILD_METRICS[$metric]}" >> "$report_file"
            fi
        done
    else
        echo "No metrics available" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

================================================================================
BUILD ENVIRONMENT DETAILS
================================================================================

Host System Information:
- Operating System: $(uname -o)
- Kernel Version: $(uname -r)
- Architecture: $(uname -m)
- CPU Cores: $BUILD_CORES
- Total Memory: $(free -h | grep Mem | awk '{print $2}')
- Available Disk: $(df -h "${PROJECT_ROOT}" | tail -1 | awk '{print $4}')

Build Configuration:
- Repository: $PRPLOS_REPO
- Target Package: $TARGET_PACKAGE
- Docker Available: $(command -v docker &> /dev/null && echo "Yes" || echo "No")
- Build Cores Used: $BUILD_CORES

================================================================================
RECOMMENDATIONS
================================================================================

1. Build Performance:
   - Traditional builds provide stability and compatibility
   - Modern builds offer containerization and reproducibility
   - Choose based on your CI/CD requirements

2. BCMSDK Integration:
   - Ensure SDK dependencies are properly configured
   - Use modern build for better dependency isolation
   - Monitor resource usage during SDK compilation

3. Optimization Tips:
   - Increase BUILD_CORES if system resources allow
   - Use ccache for faster rebuilds
   - Consider distributed builds for large projects

================================================================================
END OF REPORT
================================================================================
EOF
    
    log_info "Text performance report created: $report_file"
}

generate_text_comparison_report() {
    log_info "Generating comparison report..."
    
    local report_file="${REPORTS_DIR}/comparison_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
================================================================================
                    PrplOS Build Methods Comparison
                      Traditional vs Modern Approach
================================================================================
Generated: $(date)

================================================================================
PERFORMANCE COMPARISON
================================================================================

EOF
    
    # Add timing comparisons
    if [[ -n "${BUILD_METRICS[traditional_build]}" ]] && [[ -n "${BUILD_METRICS[modern_build]}" ]]; then
        local trad_time="${BUILD_METRICS[traditional_build]}"
        local mod_time="${BUILD_METRICS[modern_build]}"
        local diff=$(echo "$trad_time - $mod_time" | bc -l 2>/dev/null || echo "0")
        
        cat >> "$report_file" << EOF
Build Time Comparison:
- Traditional Build: $(printf "%.2f" "$trad_time") seconds
- Modern Build: $(printf "%.2f" "$mod_time") seconds
- Time Difference: $(printf "%.2f" "$diff") seconds

Performance Analysis:
EOF
        
        if (( $(echo "$diff > 0" | bc -l) )); then
            echo "- Modern build is $(printf "%.2f" "$diff") seconds faster" >> "$report_file"
        else
            echo "- Traditional build is $(printf "%.2f" "$(echo "-1 * $diff" | bc -l)") seconds faster" >> "$report_file"
        fi
    else
        echo "Insufficient data for performance comparison" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

================================================================================
METHOD CHARACTERISTICS
================================================================================

Traditional Build Method:
- Uses standard OpenWRT build system
- Direct compilation on host system
- Quilt-based patch management
- Minimal dependencies
- Best for: Quick builds, legacy systems

Modern Build Method:
- Containerized build environment
- Git-based workflow
- Reproducible builds
- Isolated dependencies
- Best for: CI/CD pipelines, team development

================================================================================
RESOURCE USAGE
================================================================================

EOF
    
    # Add resource usage if available
    if [[ -f "${REPORTS_DIR}/resource_usage.txt" ]]; then
        echo "Peak Resource Usage:" >> "$report_file"
        tail -5 "${REPORTS_DIR}/resource_usage.txt" >> "$report_file" 2>/dev/null || echo "No resource data available" >> "$report_file"
    else
        echo "Resource usage data not available" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

================================================================================
RECOMMENDATIONS FOR BCMSDK INTEGRATION
================================================================================

1. For Development:
   - Use modern build for better isolation
   - Enable Docker for consistent environments
   - Implement proper version control

2. For Production:
   - Traditional build offers proven stability
   - Consider hybrid approach for critical components
   - Maintain build reproducibility

3. For BCMSDK Specific:
   - Ensure SDK licensing compliance
   - Configure proper cross-compilation
   - Monitor memory usage during SDK builds

================================================================================
END OF COMPARISON REPORT
================================================================================
EOF
    
    log_info "Comparison report generated: $report_file"
}

# =============================================================================
# MAIN MENU INTERFACE
# =============================================================================

show_menu() {
    clear
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    PrplOS Build Automation Suite v2.2.0                      ║
║              Enhanced for BCMSDK Integration - Docker Fixed                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

📋 Build Options:
  1) Traditional Build    - OpenWRT with Quilt patches (legacy approach)
  2) Modern Build        - Git + Docker workflow (recommended)
  3) Both Builds         - Sequential execution for comparison
  4) Comparative Analysis - Detailed performance comparison

🔧 Management Options:
  5) Generate Report     - Create text performance report
  6) System Status       - Check dependencies and system health
  7) Cleanup Environment - Clean workspace and reset environment
  8) Help & Documentation - View usage guide
  0) Exit                - Terminate application

EOF
    echo -n "Please select an option [0-8]: "
}

# =============================================================================
# MAIN EXECUTION LOGIC
# =============================================================================

main() {
    # Initialize global timing
    TOTAL_START_TIME=$(date +%s.%N)
    
    # Setup environment
    log_info "PrplOS Build Automation Suite v2.2.0 - Starting..."
    log_info "Optimized for BCMSDK Integration"
    
    # Check dependencies first
    if ! check_dependencies; then
        log_error "Dependency check failed, exiting"
        exit 1
    fi
    
    setup_project_structure
    
    # Main menu loop
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                log_info "User selected: Traditional Build"
                monitor_resources &
                local monitor_pid=$!
                if build_traditional; then
                    log_info "Traditional build completed successfully"
                else
                    log_error "Traditional build failed"
                fi
                kill $monitor_pid 2>/dev/null || true
                ;;
            2)
                log_info "User selected: Modern Build"
                monitor_resources &
                local monitor_pid=$!
                if build_modern; then
                    log_info "Modern build completed successfully"
                else
                    log_error "Modern build failed"
                fi
                kill $monitor_pid 2>/dev/null || true
                ;;
            3)
                log_info "User selected: Both Builds"
                monitor_resources &
                local monitor_pid=$!
                build_traditional
                sleep 2
                build_modern
                kill $monitor_pid 2>/dev/null || true
                ;;
            4)
                log_info "User selected: Comparative Analysis"
                monitor_resources &
                local monitor_pid=$!
                build_comparison
                kill $monitor_pid 2>/dev/null || true
                echo ""
                echo "Comparison reports generated in: $REPORTS_DIR"
                ;;
            5)
                log_info "User selected: Generate Report"
                generate_performance_report
                echo "Report generated in: $REPORTS_DIR"
                echo "Press Enter to continue..."
                read -r
                ;;
            6)
                log_info "User selected: System Status"
                echo ""
                echo "System Status Check:"
                echo "==================="
                check_dependencies || echo "Some dependencies may be missing"
                echo ""
                echo "System Information:"
                echo "- CPU Cores: $(nproc)"
                echo "- Total Memory: $(free -h | grep Mem | awk '{print $2}')"
                echo "- Available Disk: $(df -h "${PROJECT_ROOT}" | tail -1 | awk '{print $4}')"
                echo ""
                echo "Docker Status:"
                if command -v docker &> /dev/null; then
                    if docker ps &>/dev/null; then
                        echo "- Docker is available and accessible"
                    else
                        echo "- Docker installed but requires sudo or user not in docker group"
                    fi
                else
                    echo "- Docker not installed"
                fi
                echo ""
                echo "Press Enter to continue..."
                read -r
                ;;
            7)
                log_info "User selected: Cleanup Environment"
                cleanup_environment
                echo "Cleanup completed. Press Enter to continue..."
                read -r
                ;;
            8)
                log_info "User selected: Help & Documentation"
                cat << HELP_TEXT

PrplOS Build Automation Suite - Quick Guide
===========================================

This tool automates PrplOS/OpenWRT builds with two methodologies:

1. Traditional Build:
   - Uses standard OpenWRT build system
   - Direct compilation on host
   - Best for quick builds and legacy systems

2. Modern Build:
   - Containerized environment (if Docker available)
   - Git-based workflow
   - Best for reproducible builds and CI/CD

Docker Setup (Optional but Recommended):
   1. Install Docker: sudo apt-get install docker.io
   2. Add user to docker group: sudo usermod -aG docker \$USER
   3. Logout and login again for group changes

BCMSDK Integration:
   - Place SDK files in workspace before building
   - Configure SDK paths in build configs
   - Monitor memory usage during SDK compilation

Tips:
   - Run System Status (option 6) first
   - Try Traditional Build for testing
   - Use Modern Build for production
   - Generate reports for performance analysis

HELP_TEXT
                echo ""
                echo "Press Enter to continue..."
                read -r
                ;;
            0)
                log_info "User selected: Exit"
                TOTAL_END_TIME=$(date +%s.%N)
                generate_performance_report
                log_info "PrplOS Build Automation Suite terminated successfully"
                echo ""
                echo "Thank you for using PrplOS Build Automation Suite!"
                echo "Build logs are available in: $LOG_DIR"
                echo "Reports are available in: $REPORTS_DIR"
                exit 0
                ;;
            *)
                log_warn "Invalid option selected: $choice"
                echo "Invalid option. Please select a number between 0-8."
                sleep 2
                ;;
        esac
        
        echo
    done
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Trap for cleanup on script termination
trap 'cleanup_environment; exit 130' INT TERM

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# =============================================================================
# END OF SCRIPT - v2.2.0 - Docker/Sudo Fixed, Dashboard Removed, Text Reports
# =============================================================================