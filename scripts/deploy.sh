#!/usr/bin/env bash
#
# deploy.sh - Quick deployment script for Andromeda
#
# This script handles subsequent deployments after initial setup.
# For first-time installation, use install.sh instead.
#
# Usage:
#   ./scripts/deploy.sh [options]
#
# Options:
#   --server-ip <ip>       Server IP address (default: 192.168.0.26)
#   --server-user <user>   SSH user (default: admin)
#   --tailscale            Use Tailscale hostname instead of IP
#   --build-only           Only build, don't deploy
#   --boot                 Set as boot configuration (don't switch immediately)
#   --test                 Test configuration (don't make permanent)
#   --rollback             Rollback to previous generation
#   --help                 Show this help message
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
SERVER_IP="${SERVER_IP:-192.168.0.26}"
SERVER_USER="${SERVER_USER:-cvictor}"
USE_TAILSCALE=false
TAILSCALE_HOSTNAME="andromeda"
BUILD_ONLY=false
DEPLOY_ACTION="switch"
DO_ROLLBACK=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Parse Arguments
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --server-ip)
                SERVER_IP="$2"
                shift 2
                ;;
            --server-user)
                SERVER_USER="$2"
                shift 2
                ;;
            --tailscale)
                USE_TAILSCALE=true
                shift
                ;;
            --build-only)
                BUILD_ONLY=true
                shift
                ;;
            --boot)
                DEPLOY_ACTION="boot"
                shift
                ;;
            --test)
                DEPLOY_ACTION="test"
                shift
                ;;
            --rollback)
                DO_ROLLBACK=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << 'EOF'

Andromeda Quick Deploy Script

Usage:
  ./scripts/deploy.sh [options]

Options:
  --server-ip <ip>       Server IP address (default: 192.168.0.26)
  --server-user <user>   SSH user (default: admin)
  --tailscale            Use Tailscale hostname instead of IP
  --build-only           Only build, don't deploy
  --boot                 Set as boot configuration (don't switch immediately)
  --test                 Test configuration (don't make permanent)
  --rollback             Rollback to previous generation
  --help                 Show this help message

Examples:
  # Standard deployment
  ./scripts/deploy.sh

  # Deploy via Tailscale
  ./scripts/deploy.sh --tailscale

  # Test configuration first
  ./scripts/deploy.sh --test

  # Build only (check for errors)
  ./scripts/deploy.sh --build-only

  # Rollback to previous
  ./scripts/deploy.sh --rollback

EOF
}

# =============================================================================
# Rollback
# =============================================================================

do_rollback() {
    local target_host
    if [[ "$USE_TAILSCALE" == "true" ]]; then
        target_host="${SERVER_USER}@${TAILSCALE_HOSTNAME}"
    else
        target_host="${SERVER_USER}@${SERVER_IP}"
    fi

    log_info "Rolling back to previous generation on $target_host..."

    ssh "$target_host" "sudo nixos-rebuild switch --rollback"

    log_success "Rollback completed"
}

# =============================================================================
# Build
# =============================================================================

build_configuration() {
    log_info "Building NixOS configuration..."

    cd "$PROJECT_ROOT"

    if nix build ".#nixosConfigurations.andromeda.config.system.build.toplevel" --show-trace; then
        log_success "Build completed successfully"
        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

# =============================================================================
# Deploy
# =============================================================================

deploy_configuration() {
    local target_host
    local use_sudo=""

    if [[ "$USE_TAILSCALE" == "true" ]]; then
        target_host="${SERVER_USER}@${TAILSCALE_HOSTNAME}"
        log_info "Using Tailscale: $target_host"
    else
        target_host="${SERVER_USER}@${SERVER_IP}"
        log_info "Using direct IP: $target_host"
    fi

    if [[ "$SERVER_USER" != "root" ]]; then
        use_sudo="--use-remote-sudo"
    fi

    log_info "Deploying with action: $DEPLOY_ACTION"

    cd "$PROJECT_ROOT"

    local start_time=$(date +%s)

    if nixos-rebuild "$DEPLOY_ACTION" \
        --flake ".#andromeda" \
        --target-host "$target_host" \
        $use_sudo \
        --show-trace; then

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        echo ""
        log_success "Deployment completed in ${duration}s"

        case "$DEPLOY_ACTION" in
            switch)
                log_info "Configuration activated and set as default boot"
                ;;
            boot)
                log_warn "Configuration set for next boot (not active yet)"
                log_info "Reboot the server to activate: ssh $target_host 'sudo reboot'"
                ;;
            test)
                log_warn "Configuration activated but NOT set as default"
                log_info "Reboot will revert to previous configuration"
                ;;
        esac

        return 0
    else
        log_error "Deployment failed"
        return 1
    fi
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

preflight_checks() {
    local errors=0

    # Check if flake.nix exists
    if [[ ! -f "$PROJECT_ROOT/flake.nix" ]]; then
        log_error "flake.nix not found in $PROJECT_ROOT"
        ((errors++))
    fi

    # Check for placeholder in secrets.nix
    if grep -q 'ssh-ed25519 AAAA\.\.\.' "$PROJECT_ROOT/secrets.nix" 2>/dev/null; then
        log_error "secrets.nix contains placeholder host key - run install.sh first"
        ((errors++))
    fi

    # Quick connectivity test (unless build-only)
    if [[ "$BUILD_ONLY" != "true" ]]; then
        local target
        if [[ "$USE_TAILSCALE" == "true" ]]; then
            target="$TAILSCALE_HOSTNAME"
        else
            target="$SERVER_IP"
        fi

        if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${SERVER_USER}@${target}" "true" 2>/dev/null; then
            log_error "Cannot connect to ${SERVER_USER}@${target}"
            log_info "Check that:"
            log_info "  - Server is running"
            log_info "  - SSH key is configured"
            log_info "  - Network is accessible"
            ((errors++))
        else
            log_success "Server connectivity OK"
        fi
    fi

    return $errors
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  🚀 Andromeda Deployment${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    parse_args "$@"

    # Handle rollback after all arguments are parsed
    if [[ "$DO_ROLLBACK" == "true" ]]; then
        do_rollback
        exit 0
    fi

    # Show configuration
    if [[ "$USE_TAILSCALE" == "true" ]]; then
        log_info "Target: ${SERVER_USER}@${TAILSCALE_HOSTNAME} (Tailscale)"
    else
        log_info "Target: ${SERVER_USER}@${SERVER_IP}"
    fi
    log_info "Action: $DEPLOY_ACTION"
    echo ""

    # Pre-flight checks
    if ! preflight_checks; then
        log_error "Pre-flight checks failed"
        exit 1
    fi

    # Build
    if [[ "$BUILD_ONLY" == "true" ]]; then
        if build_configuration; then
            log_success "Build successful - ready to deploy"
            echo ""
            echo "To deploy, run:"
            echo "  ./scripts/deploy.sh"
        fi
        exit $?
    fi

    # Deploy
    if deploy_configuration; then
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  ✅ Deployment Successful${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    else
        exit 1
    fi
}

main "$@"
