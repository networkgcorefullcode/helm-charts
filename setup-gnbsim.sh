#!/bin/bash

# Script to setup gNBSim Docker containers with macvlan networking
# Equivalent to the Ansible playbook for gNBSim deployment

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
    GNBSIM_PARENT_INTERFACE=${GNBSIM_PARENT_INTERFACE:-gnbaccess}
    GNBSIM_SUBNET_PREFIX=${GNBSIM_SUBNET_PREFIX:-192.168.100}
    GNBSIM_GATEWAY_SUFFIX=${GNBSIM_GATEWAY_SUFFIX:-1}
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
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker service."
        exit 1
    fi
    
    print_status "Docker is available and running"
}

# Function to check if parent interface exists
check_parent_interface() {
    print_step "Checking parent interface: $GNBSIM_PARENT_INTERFACE"
    
    # Check if the parent interface exists
    if ! ip link show $GNBSIM_PARENT_INTERFACE &> /dev/null; then
        print_warning "Parent interface '$GNBSIM_PARENT_INTERFACE' does not exist"
        print_warning "Available interfaces:"
        ip link show | grep "^[0-9]" | cut -d: -f2 | sed 's/^ */  - /'
        
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Aborted by user"
            exit 1
        fi
    else
        print_status "Parent interface '$GNBSIM_PARENT_INTERFACE' found"
    fi
}

# Function to pull the gNBSim Docker image
pull_gnbsim_image() {
    print_step "Pulling gNBSim Docker image: $GNBSIM_IMAGE"
    
    # Pull the Docker image from registry
    if docker pull "$GNBSIM_IMAGE"; then
        print_status "Successfully pulled image: $GNBSIM_IMAGE"
    else
        print_error "Failed to pull image: $GNBSIM_IMAGE"
        exit 1
    fi
}

# Function to get the node index (simulates Ansible index_of lookup)
get_node_index() {
    # For standalone deployment, return 1 as default
    # In a multi-node setup, this could be passed as parameter
    echo "1"
}

# Function to create macvlan network
create_macvlan_network() {
    print_step "Creating macvlan network: $GNBSIM_NETWORK_NAME"
    
    # Calculate network address based on node index
    local node_index=$(get_node_index)
    local subnet="${GNBSIM_SUBNET_PREFIX}.${node_index}.0/24"
    local gateway="${GNBSIM_SUBNET_PREFIX}.${node_index}.${GNBSIM_GATEWAY_SUFFIX}"
    
    print_status "Network configuration:"
    print_status "  - Network name: $GNBSIM_NETWORK_NAME"
    print_status "  - Driver: macvlan"
    print_status "  - Parent interface: $GNBSIM_PARENT_INTERFACE"
    print_status "  - Subnet: $subnet"
    print_status "  - Gateway: $gateway"
    
    # Check if network already exists
    if docker network ls | grep -q "$GNBSIM_NETWORK_NAME"; then
        print_warning "Network '$GNBSIM_NETWORK_NAME' already exists"
        read -p "Do you want to remove and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Removing existing network..."
            docker network rm "$GNBSIM_NETWORK_NAME" || true
        else
            print_status "Using existing network"
            return 0
        fi
    fi
    
    # Create the macvlan network
    if docker network create \
        --driver macvlan \
        --opt parent="$GNBSIM_PARENT_INTERFACE" \
        --subnet="$subnet" \
        --gateway="$gateway" \
        "$GNBSIM_NETWORK_NAME"; then
        print_status "Successfully created macvlan network: $GNBSIM_NETWORK_NAME"
    else
        print_error "Failed to create macvlan network"
        exit 1
    fi
}

# Function to stop and remove existing containers
cleanup_existing_containers() {
    print_step "Checking for existing gNBSim containers..."
    
    # Find containers with the specified prefix
    local existing_containers=$(docker ps -a --filter "name=${GNBSIM_CONTAINER_PREFIX}-" --format "{{.Names}}" || true)
    
    if [ -n "$existing_containers" ]; then
        print_warning "Found existing containers:"
        echo "$existing_containers" | sed 's/^/  - /'
        
        read -p "Do you want to stop and remove them? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Stopping and removing existing containers..."
            echo "$existing_containers" | xargs -r docker stop
            echo "$existing_containers" | xargs -r docker rm
            print_status "Cleanup completed"
        else
            print_warning "Existing containers will remain. This may cause conflicts."
        fi
    else
        print_status "No existing containers found"
    fi
}

# Function to create gNBSim containers
create_gnbsim_containers() {
    print_step "Creating $GNBSIM_CONTAINER_COUNT gNBSim container(s)..."
    
    # Create containers in a loop
    for i in $(seq 1 $GNBSIM_CONTAINER_COUNT); do
        local container_name="${GNBSIM_CONTAINER_PREFIX}-${i}"
        
        print_status "Creating container: $container_name"
        
        # Create and start the container
        if docker run -d \
            --name "$container_name" \
            --network "$GNBSIM_NETWORK_NAME" \
            "$GNBSIM_IMAGE" \
            sleep infinity; then
            print_status "Successfully created container: $container_name"
        else
            print_error "Failed to create container: $container_name"
            exit 1
        fi
    done
    
    print_status "All containers created successfully"
}

# Function to verify container status
verify_containers() {
    print_step "Verifying container status..."
    
    print_status "Container status:"
    docker ps --filter "name=${GNBSIM_CONTAINER_PREFIX}-" --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}"
    
    # Check if all containers are running
    local running_count=$(docker ps --filter "name=${GNBSIM_CONTAINER_PREFIX}-" --format "{{.Names}}" | wc -l)
    
    if [ "$running_count" -eq "$GNBSIM_CONTAINER_COUNT" ]; then
        print_status "All $GNBSIM_CONTAINER_COUNT containers are running successfully"
    else
        print_warning "Expected $GNBSIM_CONTAINER_COUNT containers, but found $running_count running"
    fi
}

# Function to display network information
show_network_info() {
    print_step "Network information:"
    
    # Show network details
    docker network inspect "$GNBSIM_NETWORK_NAME" --format "{{json .IPAM.Config}}" | \
        python3 -m json.tool 2>/dev/null || \
        docker network inspect "$GNBSIM_NETWORK_NAME"
}

# Function to show usage instructions
show_usage_instructions() {
    print_step "Usage instructions:"
    echo
    print_status "To access a container:"
    echo "  docker exec -it ${GNBSIM_CONTAINER_PREFIX}-1 /bin/bash"
    echo
    print_status "To view container logs:"
    echo "  docker logs ${GNBSIM_CONTAINER_PREFIX}-1"
    echo
    print_status "To stop all containers:"
    echo "  docker stop \$(docker ps -q --filter \"name=${GNBSIM_CONTAINER_PREFIX}-\")"
    echo
    print_status "To remove all containers:"
    echo "  docker rm \$(docker ps -aq --filter \"name=${GNBSIM_CONTAINER_PREFIX}-\")"
    echo
    print_status "To remove the network:"
    echo "  docker network rm $GNBSIM_NETWORK_NAME"
}

# Main function
main() {
    echo "================================================"
    echo "  gNBSim Docker Container Setup Script"
    echo "================================================"
    echo
    
    # Display configuration
    print_status "Configuration:"
    print_status "  - Image: $GNBSIM_IMAGE"
    print_status "  - Container prefix: $GNBSIM_CONTAINER_PREFIX"
    print_status "  - Container count: $GNBSIM_CONTAINER_COUNT"
    print_status "  - Network name: $GNBSIM_NETWORK_NAME"
    print_status "  - Parent interface: $GNBSIM_PARENT_INTERFACE"
    print_status "  - Subnet prefix: $GNBSIM_SUBNET_PREFIX"
    echo
    
    # Pre-flight checks
    check_docker_availability
    check_parent_interface
    
    # Execute main tasks
    pull_gnbsim_image
    cleanup_existing_containers
    create_macvlan_network
    create_gnbsim_containers
    
    # Post-deployment verification
    verify_containers
    show_network_info
    show_usage_instructions
    
    echo
    print_status "================================================"
    print_status "  gNBSim setup completed successfully!"
    print_status "================================================"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Execute main function with all arguments
    main "$@"
fi
