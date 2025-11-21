#!/bin/bash
# Build script for Selkies-Coder Docker image

set -e

# Configuration
REGISTRY=${REGISTRY:-"ghcr.io"}
NAMESPACE=${NAMESPACE:-"$(git config user.name | tr '[:upper:]' '[:lower:]')"}
IMAGE_NAME=${IMAGE_NAME:-"selkies-64"}
TAG=${TAG:-"latest"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH=true
            shift
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --push          Push image to registry after building"
            echo "  --no-cache      Build without using cache"
            echo "  --tag TAG       Image tag (default: latest)"
            echo "  --namespace NS  Registry namespace (default: git username)"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed"
    exit 1
fi

# Build image name
FULL_IMAGE="${REGISTRY}/${NAMESPACE}/${IMAGE_NAME}:${TAG}"

print_info "Building Selkies-Coder Docker image"
print_info "Image: ${FULL_IMAGE}"
print_info "Build options: ${NO_CACHE}"

# Build the image
print_info "Starting Docker build..."
if docker build ${NO_CACHE} -t "${FULL_IMAGE}" . ; then
    print_info "Build successful!"

    # Show image info
    print_info "Image details:"
    docker images "${FULL_IMAGE}"

    # Calculate image size
    SIZE=$(docker images "${FULL_IMAGE}" --format "{{.Size}}")
    print_info "Image size: ${SIZE}"
else
    print_error "Build failed!"
    exit 1
fi

# Push if requested
if [ "${PUSH}" = true ]; then
    print_info "Pushing image to registry..."

    # Check if logged in to registry
    if ! docker info 2>/dev/null | grep -q "${REGISTRY}"; then
        print_warn "Not logged in to ${REGISTRY}"
        print_info "Attempting login..."

        if [ "${REGISTRY}" = "ghcr.io" ]; then
            if [ -z "${GITHUB_TOKEN}" ]; then
                print_error "GITHUB_TOKEN environment variable not set"
                print_error "Please run: export GITHUB_TOKEN=your_token"
                exit 1
            fi
            echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${NAMESPACE}" --password-stdin
        else
            docker login "${REGISTRY}"
        fi
    fi

    # Push the image
    if docker push "${FULL_IMAGE}"; then
        print_info "Push successful!"
        print_info "Image available at: ${FULL_IMAGE}"
    else
        print_error "Push failed!"
        exit 1
    fi
else
    print_info "Image built locally. Use --push to upload to registry"
fi

# Offer to test locally
echo ""
print_info "To test locally, run:"
echo "  docker run -d -p 8080:8080 --name selkies-test ${FULL_IMAGE}"
echo "  # Access at http://localhost:8080"
echo "  docker stop selkies-test && docker rm selkies-test"

# Update Terraform template
echo ""
print_info "To use in Coder, update main.tf:"
echo "  default image_registry = \"${NAMESPACE}\""
echo "  default image_tag = \"${TAG}\""

print_info "Build complete!"