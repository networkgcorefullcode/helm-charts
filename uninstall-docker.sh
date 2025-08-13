#!/bin/bash

# Script to completely uninstall Docker from Ubuntu 22.04 server
# This script removes Docker Engine, Docker Compose, and all related components

set -e

# Load environment variables from .env file if available
if [ -f .env ]; then
    source .env
    echo "✓ Variables loaded from .env file"
fi

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to print error messages
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to print step headers
print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if Docker is installed
check_docker_installed() {
    print_step "Checking if Docker is installed..."
    
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version 2>/dev/null || echo "Unknown version")
        print_status "Docker is installed: $docker_version"
        return 0
    else
        print_status "Docker is not installed"
        return 1
    fi
}

# Function to check system requirements
check_system_requirements() {
    print_step "Checking system requirements..."
    
    # Check if running on Ubuntu
    if ! command -v lsb_release &> /dev/null || [ "$(lsb_release -si)" != "Ubuntu" ]; then
        print_error "This script is designed for Ubuntu systems"
        exit 1
    fi
    
    # Check Ubuntu version
    local ubuntu_version=$(lsb_release -rs)
    print_status "Ubuntu version detected: $ubuntu_version"
    
    if [ "$(echo "$ubuntu_version != 22.04" | bc -l 2>/dev/null || echo 1)" -eq 1 ]; then
        print_warning "This script is optimized for Ubuntu 22.04"
        print_warning "Current version: $ubuntu_version"
        
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Aborted by user"
            exit 1
        fi
    fi
    
    # Check for sudo privileges
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        exit 1
    fi
    
    print_status "System requirements check passed"
}

# Function to show current Docker resources
show_current_docker_resources() {
    print_step "Checking current Docker resources..."
    
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        print_status "Current Docker resources:"
        
        # Show running containers
        local running_containers=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l)
        echo "  - Running containers: $running_containers"
        
        # Show all containers
        local all_containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null | wc -l)
        echo "  - Total containers: $all_containers"
        
        # Show images
        local images=$(docker images --format "{{.Repository}}" 2>/dev/null | wc -l)
        echo "  - Images: $images"
        
        # Show networks
        local networks=$(docker network ls --format "{{.Name}}" 2>/dev/null | grep -v "bridge\|host\|none" | wc -l)
        echo "  - Custom networks: $networks"
        
        # Show volumes
        local volumes=$(docker volume ls --format "{{.Name}}" 2>/dev/null | wc -l)
        echo "  - Volumes: $volumes"
        
        if [ "$all_containers" -gt 0 ] || [ "$images" -gt 0 ] || [ "$networks" -gt 0 ] || [ "$volumes" -gt 0 ]; then
            print_warning "Docker resources exist and will be removed!"
        fi
    else
        print_status "Docker is not running or not accessible"
    fi
}

# Function to stop all Docker containers
stop_all_docker_containers() {
    print_step "Stopping all Docker containers..."
    
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        # Get all running containers
        local running_containers=$(docker ps -q 2>/dev/null || true)
        
        if [ -n "$running_containers" ]; then
            print_status "Stopping running containers..."
            echo "$running_containers" | xargs docker stop &>/dev/null || true
            print_status "All containers stopped"
        else
            print_status "No running containers found"
        fi
    else
        print_status "Docker is not accessible, skipping container stop"
    fi
}

# Function to remove all Docker resources
remove_all_docker_resources() {
    print_step "Removing all Docker resources..."
    
    if command -v docker &> /dev/null; then
        # Remove all containers
        print_status "Removing all containers..."
        docker container prune -f &>/dev/null || true
        local all_containers=$(docker ps -aq 2>/dev/null || true)
        if [ -n "$all_containers" ]; then
            echo "$all_containers" | xargs docker rm -f &>/dev/null || true
        fi
        
        # Remove all images
        print_status "Removing all images..."
        docker image prune -a -f &>/dev/null || true
        local all_images=$(docker images -q 2>/dev/null || true)
        if [ -n "$all_images" ]; then
            echo "$all_images" | xargs docker rmi -f &>/dev/null || true
        fi
        
        # Remove all networks
        print_status "Removing all networks..."
        docker network prune -f &>/dev/null || true
        
        # Remove all volumes
        print_status "Removing all volumes..."
        docker volume prune -f &>/dev/null || true
        
        print_status "Docker resources cleanup completed"
    else
        print_status "Docker command not available, skipping resource cleanup"
    fi
}

# Function to stop Docker services
stop_docker_services() {
    print_step "Stopping Docker services..."
    
    # Stop Docker service
    if systemctl is-active --quiet docker 2>/dev/null; then
        print_status "Stopping Docker service..."
        sudo systemctl stop docker
        print_status "Docker service stopped"
    else
        print_status "Docker service is not running"
    fi
    
    # Stop Docker socket
    if systemctl is-active --quiet docker.socket 2>/dev/null; then
        print_status "Stopping Docker socket..."
        sudo systemctl stop docker.socket
        print_status "Docker socket stopped"
    else
        print_status "Docker socket is not running"
    fi
    
    # Stop containerd
    if systemctl is-active --quiet containerd 2>/dev/null; then
        print_status "Stopping containerd service..."
        sudo systemctl stop containerd
        print_status "Containerd service stopped"
    else
        print_status "Containerd service is not running"
    fi
}

# Function to disable Docker services
disable_docker_services() {
    print_step "Disabling Docker services..."
    
    # Disable Docker service
    if systemctl is-enabled --quiet docker 2>/dev/null; then
        print_status "Disabling Docker service..."
        sudo systemctl disable docker
        print_status "Docker service disabled"
    else
        print_status "Docker service is not enabled"
    fi
    
    # Disable Docker socket
    if systemctl is-enabled --quiet docker.socket 2>/dev/null; then
        print_status "Disabling Docker socket..."
        sudo systemctl disable docker.socket
        print_status "Docker socket disabled"
    else
        print_status "Docker socket is not enabled"
    fi
    
    # Disable containerd
    if systemctl is-enabled --quiet containerd 2>/dev/null; then
        print_status "Disabling containerd service..."
        sudo systemctl disable containerd
        print_status "Containerd service disabled"
    else
        print_status "Containerd service is not enabled"
    fi
}

# Function to uninstall Docker packages
uninstall_docker_packages() {
    print_step "Uninstalling Docker packages..."
    
    # List of Docker-related packages to remove
    local docker_packages=(
        "docker-ce"
        "docker-ce-cli"
        "containerd.io"
        "docker-buildx-plugin"
        "docker-compose-plugin"
        "docker.io"
        "docker-doc"
        "docker-compose"
        "podman-docker"
        "containerd"
        "runc"
    )
    
    print_status "Removing Docker packages..."
    
    # Remove packages with apt
    for package in "${docker_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package" 2>/dev/null; then
            print_status "Removing package: $package"
            sudo apt remove --purge -y "$package" &>/dev/null || true
        fi
    done
    
    # Remove any remaining Docker-related packages
    print_status "Removing any remaining Docker packages..."
    sudo apt autoremove -y &>/dev/null || true
    
    print_status "Docker packages removal completed"
}

# Function to remove Docker repositories and GPG keys
remove_docker_repositories() {
    print_step "Removing Docker repositories and GPG keys..."
    
    # Remove Docker APT repository sources
    local repo_files=(
        "/etc/apt/sources.list.d/docker.list"
        "/etc/apt/sources.list.d/download_docker_com_linux_ubuntu.list"
    )
    
    for repo_file in "${repo_files[@]}"; do
        if [ -f "$repo_file" ]; then
            print_status "Removing repository file: $repo_file"
            sudo rm -f "$repo_file"
        fi
    done
    
    # Remove Docker GPG key
    if [ -f "/etc/apt/keyrings/docker.asc" ]; then
        print_status "Removing Docker GPG key..."
        sudo rm -f "/etc/apt/keyrings/docker.asc"
    fi
    
    # Remove old GPG key locations
    if [ -f "/usr/share/keyrings/docker-archive-keyring.gpg" ]; then
        print_status "Removing old Docker GPG key..."
        sudo rm -f "/usr/share/keyrings/docker-archive-keyring.gpg"
    fi
    
    print_status "Docker repositories and GPG keys removed"
}

# Function to remove Docker directories and data
remove_docker_directories() {
    print_step "Removing Docker directories and data..."
    
    # List of Docker directories to remove
    local docker_dirs=(
        "/var/lib/docker"
        "/var/lib/containerd"
        "/etc/docker"
        "/var/run/docker"
        "/var/run/docker.sock"
        "/usr/local/bin/docker-compose"
        "$HOME/.docker"
    )
    
    for dir in "${docker_dirs[@]}"; do
        if [ -e "$dir" ]; then
            print_status "Removing directory/file: $dir"
            sudo rm -rf "$dir" 2>/dev/null || true
        fi
    done
    
    # Remove Docker from user groups
    print_status "Removing users from docker group..."
    
    # Get all users in docker group
    if getent group docker &>/dev/null; then
        local docker_users=$(getent group docker | cut -d: -f4 | tr ',' ' ')
        if [ -n "$docker_users" ]; then
            for user in $docker_users; do
                print_status "Removing user '$user' from docker group"
                sudo gpasswd -d "$user" docker &>/dev/null || true
            done
        fi
        
        # Remove docker group
        print_status "Removing docker group..."
        sudo groupdel docker &>/dev/null || true
    fi
    
    print_status "Docker directories and data removal completed"
}

# Function to clean up APT cache
cleanup_apt_cache() {
    print_step "Cleaning up APT cache..."
    
    print_status "Updating APT package list..."
    sudo apt update &>/dev/null || true
    
    print_status "Cleaning APT cache..."
    sudo apt autoclean &>/dev/null || true
    sudo apt autoremove -y &>/dev/null || true
    
    print_status "APT cache cleanup completed"
}

# Function to verify Docker removal
verify_docker_removal() {
    print_step "Verifying Docker removal..."
    
    # Check if docker command exists
    if command -v docker &> /dev/null; then
        print_warning "✗ Docker command still available"
        print_warning "  Path: $(which docker)"
    else
        print_status "✓ Docker command removed"
    fi
    
    # Check for Docker packages
    local remaining_packages=$(dpkg -l | grep -i docker | grep "^ii" | wc -l)
    if [ "$remaining_packages" -gt 0 ]; then
        print_warning "✗ Docker packages still installed:"
        dpkg -l | grep -i docker | grep "^ii" | awk '{print "  - " $2}'
    else
        print_status "✓ No Docker packages found"
    fi
    
    # Check for Docker services
    local active_services=$(systemctl list-units --all | grep -i docker | grep active | wc -l)
    if [ "$active_services" -gt 0 ]; then
        print_warning "✗ Docker services still active:"
        systemctl list-units --all | grep -i docker | grep active | awk '{print "  - " $1}'
    else
        print_status "✓ No active Docker services"
    fi
    
    # Check for Docker directories
    local remaining_dirs=()
    for dir in "/var/lib/docker" "/etc/docker" "/var/run/docker.sock"; do
        if [ -e "$dir" ]; then
            remaining_dirs+=("$dir")
        fi
    done
    
    if [ ${#remaining_dirs[@]} -gt 0 ]; then
        print_warning "✗ Docker directories still exist:"
        printf "  - %s\n" "${remaining_dirs[@]}"
    else
        print_status "✓ Docker directories removed"
    fi
    
    # Check for docker group
    if getent group docker &>/dev/null; then
        print_warning "✗ Docker group still exists"
    else
        print_status "✓ Docker group removed"
    fi
}

# Function to show system status after removal
show_system_status() {
    print_step "System status after Docker removal:"
    
    # Show system resources
    print_status "System resources:"
    echo "  - Available disk space: $(df -h / | awk 'NR==2 {print $4}')"
    echo "  - Memory usage: $(free -h | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
    
    # Show services status
    print_status "Related services status:"
    for service in "docker" "containerd"; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            local status=$(systemctl is-active $service 2>/dev/null || echo "not-found")
            echo "  - $service: $status"
        fi
    done
}

# Function to show cleanup recommendations
show_cleanup_recommendations() {
    print_step "Additional cleanup recommendations:"
    
    print_status "Optional cleanup commands:"
    echo "  - Remove Python Docker module: pip3 uninstall docker"
    echo "  - Remove snap Docker: snap remove docker"
    echo "  - Clean package cache: sudo apt clean"
    echo "  - Update system: sudo apt update && sudo apt upgrade"
    
    print_status "Verification commands:"
    echo "  - Check for Docker processes: ps aux | grep docker"
    echo "  - Check listening ports: netstat -tlnp | grep docker"
    echo "  - Check mounted filesystems: mount | grep docker"
}

# Function to prompt for confirmation
confirm_uninstallation() {
    echo
    print_warning "This will completely remove Docker from your system including:"
    print_warning "  - All Docker containers, images, networks, and volumes"
    print_warning "  - Docker Engine and related packages"
    print_warning "  - Docker configuration files and data"
    print_warning "  - Docker repositories and GPG keys"
    print_warning "  - Docker user groups and permissions"
    echo
    print_error "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    read -p "Are you sure you want to completely uninstall Docker? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Docker uninstallation cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Type 'UNINSTALL' to confirm: " confirmation
    if [ "$confirmation" != "UNINSTALL" ]; then
        print_status "Docker uninstallation cancelled - confirmation failed"
        exit 0
    fi
}

# Main function
main() {
    echo "================================================"
    echo "  Docker Complete Uninstallation Script"
    echo "  Ubuntu 22.04 Server"
    echo "================================================"
    echo
    
    # Pre-flight checks
    check_system_requirements
    
    # Check if Docker is installed
    if ! check_docker_installed; then
        print_status "Docker is not installed, nothing to uninstall"
        exit 0
    fi
    
    # Show current resources
    show_current_docker_resources
    
    # Confirm uninstallation
    if [[ "${1:-}" != "--force" ]]; then
        confirm_uninstallation
    else
        print_status "Force mode enabled, skipping confirmation"
    fi
    
    echo
    print_status "Starting Docker uninstallation process..."
    
    # Execute uninstallation steps
    stop_all_docker_containers
    remove_all_docker_resources
    stop_docker_services
    disable_docker_services
    uninstall_docker_packages
    remove_docker_repositories
    remove_docker_directories
    cleanup_apt_cache
    
    # Post-uninstallation verification
    verify_docker_removal
    show_system_status
    show_cleanup_recommendations
    
    echo
    print_status "================================================"
    print_status "  Docker uninstallation completed!"
    print_status "================================================"
    print_status "Please reboot your system to ensure all changes take effect"
}

# Install bc if not available (for version comparison)
if ! command -v bc &> /dev/null; then
    sudo apt update && sudo apt install -y bc &>/dev/null || true
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Execute main function with all arguments
    main "$@"
fi
