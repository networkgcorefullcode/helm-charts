#!/bin/bash

# Script para instalar Docker en Ubuntu
# Equivalente al playbook de Ansible proporcionado

set -e

# Cargar variables del archivo .env
if [ -f .env ]; then
    source .env
    echo "✓ Variables loaded from .env"
else
    echo "⚠️  .env file not found, using default values"
    TARGET_USER=${TARGET_USER:-ubuntu}
    DOCKER_TEST_IMAGE=${DOCKER_TEST_IMAGE:-hello-world}
    DOCKER_GPG_URL=${DOCKER_GPG_URL:-https://download.docker.com/linux/ubuntu/gpg}
fi

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Función para verificar si docker está instalado
check_docker_installed() {
    print_status "Verificando si Docker está instalado..."
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        print_status "Docker ya está instalado: $DOCKER_VERSION"
        return 0
    else
        print_warning "Docker no está instalado"
        return 1
    fi
}

# Función para obtener la arquitectura del sistema
get_architecture() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        *)
            echo $ARCH
            ;;
    esac
}

# Función principal de instalación
install_docker() {
    print_status "Starting Docker installation..."
    
    # Update apt cache
    print_status "Updating apt cache..."
    sudo apt update
    
    # Remove previous Docker sources
    print_status "Removing previous Docker configurations..."
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/sources.list.d/download_docker_com_linux_ubuntu.list
    
    # Install required packages
    print_status "Installing required system packages..."
    sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        software-properties-common \
        python3-pip \
        virtualenv \
        python3-setuptools
    
    # Create directory for Docker GPG key
    print_status "Creating directory for GPG keys..."
    sudo mkdir -p /etc/apt/keyrings
    sudo chmod 755 /etc/apt/keyrings
    
    # Download Docker GPG key
    print_status "Downloading Docker GPG key..."
    curl -fsSL $DOCKER_GPG_URL | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
    sudo chmod 644 /etc/apt/keyrings/docker.asc
    sudo chown root:root /etc/apt/keyrings/docker.asc
    
    # Get system information
    ARCHITECTURE=$(get_architecture)
    CODENAME=$(lsb_release -cs)
    
    print_status "Detected architecture: $ARCHITECTURE"
    print_status "Detected codename: $CODENAME"
    
    # Add Docker repository
    print_status "Adding Docker repository..."
    echo "deb [arch=$ARCHITECTURE signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $CODENAME stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update apt cache again
    print_status "Updating apt cache with new repository..."
    sudo apt update
    
    # Install Docker CE
    print_status "Installing Docker CE..."
    sudo apt install -y docker-ce
    
    # Get Ubuntu version
    UBUNTU_VERSION=$(lsb_release -rs)
    print_status "Detected Ubuntu version: $UBUNTU_VERSION"
    
    # Install Docker module for Python based on Ubuntu version
    if [ "$(echo "$UBUNTU_VERSION < 24.04" | bc -l)" -eq 1 ]; then
        print_status "Installing docker module for Python (Ubuntu < 24.04)..."
        sudo pip3 install docker
    else
        print_status "Installing python3-docker package (Ubuntu >= 24.04)..."
        sudo apt install -y python3-docker
    fi
    
    # Create docker group and add user
    print_status "Configuring docker group..."
    sudo groupadd -f docker
    sudo usermod -aG docker $TARGET_USER
    
    # Hack to allow docker to run without sudo
    print_status "Configuring Docker socket permissions..."
    sudo chown $TARGET_USER /var/run/docker.sock
    
    print_status "Docker installed successfully!"
}

# Function to test Docker
test_docker() {
    print_status "Testing Docker installation..."
    
    # Download test image
    print_status "Downloading test image: $DOCKER_TEST_IMAGE"
    sudo docker pull $DOCKER_TEST_IMAGE
    
    # Run test container
    print_status "Running test container..."
    sudo docker run --rm $DOCKER_TEST_IMAGE
    
    print_status "Docker test completed successfully!"
}

# Main function
main() {
    echo "=========================================="
    echo "  Docker Installation Script"
    echo "=========================================="
    echo
    
    # Check if already installed
    if check_docker_installed; then
        read -p "Docker is already installed. Do you want to continue with tests? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            test_docker
        fi
        exit 0
    fi
    
    # Check if running on Ubuntu
    if ! command -v lsb_release &> /dev/null || [ "$(lsb_release -si)" != "Ubuntu" ]; then
        print_error "This script is designed for Ubuntu"
        exit 1
    fi
    
    # Check sudo permissions
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo permissions"
        exit 1
    fi
    
    # Install Docker
    install_docker
    
    # Test Docker
    test_docker
    
    echo
    print_status "=========================================="
    print_status "  Instalación completada exitosamente"
    print_status "=========================================="
    print_warning "NOTA: Es posible que necesites cerrar sesión y volver a iniciar"
    print_warning "      para que los cambios de grupo surtan efecto."
}

# Verificar si bc está instalado (para comparación de versiones)
if ! command -v bc &> /dev/null; then
    sudo apt update && sudo apt install -y bc
fi

# Ejecutar función principal
main "$@"
