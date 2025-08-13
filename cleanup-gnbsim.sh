#!/bin/bash

# Script to cleanup gNBSim Docker containers, network and images
# Equivalent to the Ansible playbook for gNBSim cleanup/teardown

set -e

# Load environment variables from .env file
if [ -f .env ]; then
    source .env
    echo "✓ Variables loaded from .env file"
else
    echo "⚠️  .env file not found, using default values"
    # Default values
    GNBSIM_IMAGE=${GNBSIM_IMAGE:-omecproject/gnbsim:latest}
    GNBSIM_CONTAINER_PREFIX=${GNBSIM_CONTAINER_PREFIX:-gnbsim}
    GNBSIM_CONTAINER_COUNT=${GNBSIM_CONTAINER_COUNT:-1}
    GNBSIM_NETWORK_NAME=${GNBSIM_NETWORK_NAME:-gnbsim-macvlan}
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

# Function to check if Docker is available and running
check_docker_availability() {
    print_step "Checking Docker availability..."
    
    # Check if docker command exists
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker service."
        exit 1
    fi
    
    print_status "Docker is available and running"
}

# Function to list current gNBSim resources
list_current_resources() {
    print_step "Listing current gNBSim resources..."
    
    # List containers
    local containers=$(docker ps -a --filter "name=${GNBSIM_CONTAINER_PREFIX}-" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$containers" ]; then
        print_status "Found containers:"
        echo "$containers" | sed 's/^/  - /'
    else
        print_status "No gNBSim containers found"
    fi
    
    # Check network
    if docker network ls | grep -q "$GNBSIM_NETWORK_NAME" 2>/dev/null; then
        print_status "Found network: $GNBSIM_NETWORK_NAME"
    else
        print_status "Network $GNBSIM_NETWORK_NAME not found"
    fi
    
    # Check image
    if docker images | grep -q "$(echo $GNBSIM_IMAGE | cut -d: -f1)" 2>/dev/null; then
        print_status "Found image: $GNBSIM_IMAGE"
    else
        print_status "Image $GNBSIM_IMAGE not found"
    fi
    
    echo
}

# Function to delete gNBSim containers
delete_gnbsim_containers() {
    print_step "Deleting gNBSim containers..."
    
    local containers_deleted=0
    local containers_failed=0
    
    # Delete containers in a loop based on count
    for i in $(seq 1 $GNBSIM_CONTAINER_COUNT); do
        local container_name="${GNBSIM_CONTAINER_PREFIX}-${i}"
        
        # Check if container exists
        if docker ps -a --filter "name=^${container_name}$" --format "{{.Names}}" | grep -q "^${container_name}$"; then
            print_status "Deleting container: $container_name"
            
            # Stop container if running
            if docker ps --filter "name=^${container_name}$" --format "{{.Names}}" | grep -q "^${container_name}$"; then
                print_status "Stopping running container: $container_name"
                if docker stop "$container_name" &>/dev/null; then
                    print_status "Container stopped: $container_name"
                else
                    print_warning "Failed to stop container: $container_name"
                fi
            fi
            
            # Remove container
            if docker rm "$container_name" &>/dev/null; then
                print_status "Successfully deleted container: $container_name"
                ((containers_deleted++))
            else
                print_error "Failed to delete container: $container_name"
                ((containers_failed++))
            fi
        else
            print_status "Container not found: $container_name"
        fi
    done
    
    # Also clean up any additional containers with the prefix
    local additional_containers=$(docker ps -aq --filter "name=${GNBSIM_CONTAINER_PREFIX}-" 2>/dev/null || true)
    if [ -n "$additional_containers" ]; then
        print_status "Found additional containers with prefix ${GNBSIM_CONTAINER_PREFIX}-, cleaning up..."
        echo "$additional_containers" | while read container_id; do
            local container_name=$(docker inspect --format='{{.Name}}' "$container_id" 2>/dev/null | sed 's/^.//' || echo "unknown")
            print_status "Stopping and removing: $container_name"
            docker stop "$container_id" &>/dev/null || true
            docker rm "$container_id" &>/dev/null || true
        done
    fi
    
    print_status "Container cleanup summary: $containers_deleted deleted, $containers_failed failed"
}

# Function to delete macvlan network
delete_macvlan_network() {
    print_step "Deleting macvlan network: $GNBSIM_NETWORK_NAME"
    
    # Check if network exists
    if docker network ls --filter "name=^${GNBSIM_NETWORK_NAME}$" --format "{{.Name}}" | grep -q "^${GNBSIM_NETWORK_NAME}$"; then
        print_status "Network found: $GNBSIM_NETWORK_NAME"
        
        # Check for connected containers
        local connected_containers=$(docker network inspect "$GNBSIM_NETWORK_NAME" --format "{{range .Containers}}{{.Name}} {{end}}" 2>/dev/null || true)
        if [ -n "$connected_containers" ]; then
            print_warning "Network has connected containers: $connected_containers"
            print_status "Attempting to disconnect containers..."
            
            # Disconnect containers from network
            for container in $connected_containers; do
                print_status "Disconnecting container: $container"
                docker network disconnect "$GNBSIM_NETWORK_NAME" "$container" --force &>/dev/null || true
            done
        fi
        
        # Remove network with force
        if docker network rm "$GNBSIM_NETWORK_NAME" &>/dev/null; then
            print_status "Successfully deleted network: $GNBSIM_NETWORK_NAME"
        else
            print_error "Failed to delete network: $GNBSIM_NETWORK_NAME"
            print_status "Attempting force removal..."
            # Try with prune to clean up unused networks
            docker network prune -f &>/dev/null || true
            if docker network rm "$GNBSIM_NETWORK_NAME" &>/dev/null; then
                print_status "Successfully force deleted network: $GNBSIM_NETWORK_NAME"
            else
                print_error "Failed to force delete network: $GNBSIM_NETWORK_NAME"
            fi
        fi
    else
        print_status "Network not found: $GNBSIM_NETWORK_NAME"
    fi
}

# Function to remove gNBSim Docker image
remove_gnbsim_image() {
    print_step "Removing gNBSim Docker image: $GNBSIM_IMAGE"
    
    # Check if image exists
    if docker images --filter "reference=${GNBSIM_IMAGE}" --format "{{.Repository}}:{{.Tag}}" | grep -q "^${GNBSIM_IMAGE}$"; then
        print_status "Image found: $GNBSIM_IMAGE"
        
        # Check for running containers using this image
        local running_containers=$(docker ps --filter "ancestor=${GNBSIM_IMAGE}" --format "{{.Names}}" 2>/dev/null || true)
        if [ -n "$running_containers" ]; then
            print_warning "Found running containers using this image:"
            echo "$running_containers" | sed 's/^/  - /'
            print_warning "Please stop these containers before removing the image"
            return 1
        fi
        
        # Check for stopped containers using this image
        local stopped_containers=$(docker ps -a --filter "ancestor=${GNBSIM_IMAGE}" --format "{{.Names}}" 2>/dev/null || true)
        if [ -n "$stopped_containers" ]; then
            print_warning "Found stopped containers using this image:"
            echo "$stopped_containers" | sed 's/^/  - /'
            print_status "These containers will prevent image removal"
        fi
        
        # Remove image with force
        if docker rmi --force "$GNBSIM_IMAGE" &>/dev/null; then
            print_status "Successfully removed image: $GNBSIM_IMAGE"
        else
            print_error "Failed to remove image: $GNBSIM_IMAGE"
            print_status "Attempting to remove unused images..."
            docker image prune -f &>/dev/null || true
            if docker rmi --force "$GNBSIM_IMAGE" &>/dev/null; then
                print_status "Successfully force removed image: $GNBSIM_IMAGE"
            else
                print_error "Failed to force remove image: $GNBSIM_IMAGE"
            fi
        fi
    else
        print_status "Image not found: $GNBSIM_IMAGE"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    print_step "Verifying cleanup..."
    
    # Check for remaining containers
    local remaining_containers=$(docker ps -a --filter "name=${GNBSIM_CONTAINER_PREFIX}-" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$remaining_containers" ]; then
        print_warning "Remaining containers found:"
        echo "$remaining_containers" | sed 's/^/  - /'
    else
        print_status "✓ No containers remaining"
    fi
    
    # Check for network
    if docker network ls --filter "name=^${GNBSIM_NETWORK_NAME}$" --format "{{.Name}}" | grep -q "^${GNBSIM_NETWORK_NAME}$"; then
        print_warning "✗ Network still exists: $GNBSIM_NETWORK_NAME"
    else
        print_status "✓ Network removed: $GNBSIM_NETWORK_NAME"
    fi
    
    # Check for image
    if docker images --filter "reference=${GNBSIM_IMAGE}" --format "{{.Repository}}:{{.Tag}}" | grep -q "^${GNBSIM_IMAGE}$"; then
        print_warning "✗ Image still exists: $GNBSIM_IMAGE"
    else
        print_status "✓ Image removed: $GNBSIM_IMAGE"
    fi
}

# Function to show cleanup statistics
show_cleanup_stats() {
    print_step "Cleanup statistics:"
    
    # Show current Docker resource usage
    print_status "Current Docker resource usage:"
    echo "  Containers: $(docker ps -a --format "{{.Names}}" | wc -l)"
    echo "  Images: $(docker images --format "{{.Repository}}" | wc -l)"
    echo "  Networks: $(docker network ls --format "{{.Name}}" | grep -v "bridge\|host\|none" | wc -l)"
    echo "  Volumes: $(docker volume ls --format "{{.Name}}" | wc -l)"
}

# Function to prompt for confirmation
confirm_cleanup() {
    echo
    print_warning "This will delete the following gNBSim resources:"
    print_warning "  - Containers: ${GNBSIM_CONTAINER_PREFIX}-1 to ${GNBSIM_CONTAINER_PREFIX}-${GNBSIM_CONTAINER_COUNT}"
    print_warning "  - Network: $GNBSIM_NETWORK_NAME"
    print_warning "  - Image: $GNBSIM_IMAGE"
    echo
    
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Cleanup cancelled by user"
        exit 0
    fi
}

# Main function
main() {
    echo "================================================"
    echo "  gNBSim Docker Cleanup Script"
    echo "================================================"
    echo
    
    # Display configuration
    print_status "Cleanup configuration:"
    print_status "  - Image: $GNBSIM_IMAGE"
    print_status "  - Container prefix: $GNBSIM_CONTAINER_PREFIX"
    print_status "  - Container count: $GNBSIM_CONTAINER_COUNT"
    print_status "  - Network name: $GNBSIM_NETWORK_NAME"
    echo
    
    # Pre-flight checks
    check_docker_availability
    list_current_resources
    
    # Confirm cleanup
    if [[ "${1:-}" != "--force" ]]; then
        confirm_cleanup
    else
        print_status "Force mode enabled, skipping confirmation"
    fi
    
    # Execute cleanup tasks
    delete_gnbsim_containers
    delete_macvlan_network
    remove_gnbsim_image
    
    # Post-cleanup verification
    verify_cleanup
    show_cleanup_stats
    
    echo
    print_status "================================================"
    print_status "  gNBSim cleanup completed!"
    print_status "================================================"
    
    # Suggest additional cleanup if needed
    echo
    print_status "Additional cleanup commands (if needed):"
    echo "  - Remove all unused containers: docker container prune -f"
    echo "  - Remove all unused networks: docker network prune -f"
    echo "  - Remove all unused images: docker image prune -a -f"
    echo "  - Remove all unused volumes: docker volume prune -f"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Execute main function with all arguments
    main "$@"
fi
