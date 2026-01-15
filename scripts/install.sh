#!/usr/bin/env bash
#
# install.sh - Andromeda Home Media Server Installation & First Deployment
#
# This script handles:
#   1. Prerequisites checking
#   2. Server preparation (SSH, host key retrieval)
#   3. Disk formatting and MergerFS setup
#   4. Secrets generation
#   5. Hardware configuration generation
#   6. First deployment
#
# Usage:
#   ./scripts/install.sh [options]
#
# Options:
#   --server-ip <ip>       Server IP address (default: 192.168.0.26)
#   --server-user <user>   SSH user on server (default: root for install, admin after)
#   --skip-disks           Skip disk formatting step
#   --skip-secrets         Skip secrets generation step
#   --skip-deploy          Skip deployment step (prepare only)
#   --help                 Show this help message
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$PROJECT_ROOT/secrets"
HOSTS_DIR="$PROJECT_ROOT/hosts/andromeda"

# Default values
SERVER_IP="${SERVER_IP:-192.168.0.26}"
SERVER_USER="${SERVER_USER:-root}"
SKIP_DISKS=false
SKIP_SECRETS=false
SKIP_DEPLOY=false

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

log_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

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

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local yn

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -r -p "$prompt" yn
    yn="${yn:-$default}"

    [[ "$yn" =~ ^[Yy] ]]
}

press_enter() {
    read -r -p "Press Enter to continue..."
}

run_on_server() {
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "${SERVER_USER}@${SERVER_IP}" "$@"
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
            --skip-disks)
                SKIP_DISKS=true
                shift
                ;;
            --skip-secrets)
                SKIP_SECRETS=true
                shift
                ;;
            --skip-deploy)
                SKIP_DEPLOY=true
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

Andromeda Installation Script

Usage:
  ./scripts/install.sh [options]

Options:
  --server-ip <ip>       Server IP address (default: 192.168.0.26)
  --server-user <user>   SSH user on server (default: root)
  --skip-disks           Skip disk formatting step
  --skip-secrets         Skip secrets generation step
  --skip-deploy          Skip deployment step (prepare only)
  --help                 Show this help message

Examples:
  # Full installation with defaults
  ./scripts/install.sh

  # Specify server IP
  ./scripts/install.sh --server-ip 192.168.1.100

  # Prepare only (no deploy)
  ./scripts/install.sh --skip-deploy

  # Re-run deployment only
  ./scripts/install.sh --skip-disks --skip-secrets

EOF
}

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log_header "Checking Prerequisites"

    local missing=()

    # Check for required commands
    for cmd in ssh ssh-keyscan nix git age; do
        if command -v "$cmd" &> /dev/null; then
            log_success "$cmd is installed"
        else
            log_error "$cmd is NOT installed"
            missing+=("$cmd")
        fi
    done

    # Check for Nix flakes
    if nix flake --help &> /dev/null 2>&1; then
        log_success "Nix flakes enabled"
    else
        log_error "Nix flakes not enabled"
        echo ""
        echo "Add to ~/.config/nix/nix.conf or /etc/nix/nix.conf:"
        echo "  experimental-features = nix-command flakes"
        echo ""
        missing+=("nix-flakes")
    fi

    # Check for SSH key
    if [[ -f ~/.ssh/id_ed25519 ]] || [[ -f ~/.ssh/id_rsa ]]; then
        log_success "SSH key found"
    else
        log_warn "No SSH key found - you may need to set one up"
    fi

    # Check for .env.secrets
    if [[ -f "$PROJECT_ROOT/.env.secrets" ]]; then
        log_success ".env.secrets file exists"
    else
        log_warn ".env.secrets not found - will need to create it"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        log_error "Missing prerequisites: ${missing[*]}"
        echo ""
        echo "Please install missing dependencies and try again."
        exit 1
    fi

    log_success "All prerequisites met!"
}

# =============================================================================
# Server Connection Test
# =============================================================================

test_server_connection() {
    log_header "Testing Server Connection"

    log_step "Attempting SSH connection to ${SERVER_USER}@${SERVER_IP}..."

    if run_on_server "echo 'Connection successful'" 2>/dev/null; then
        log_success "SSH connection successful"
    else
        log_error "Cannot connect to server"
        echo ""
        echo "Please ensure:"
        echo "  1. Server is running and accessible at $SERVER_IP"
        echo "  2. SSH is enabled on the server"
        echo "  3. Your SSH key is authorized on the server"
        echo ""
        echo "For a fresh NixOS install, you may need to:"
        echo "  - Boot from NixOS ISO"
        echo "  - Set a root password: passwd"
        echo "  - Enable SSH: systemctl start sshd"
        echo ""
        exit 1
    fi

    # Get server info
    log_info "Server information:"
    run_on_server "uname -a" || true
    echo ""
}

# =============================================================================
# Retrieve Host Key
# =============================================================================

retrieve_host_key() {
    log_header "Retrieving Server SSH Host Key"

    log_step "Fetching SSH host key from $SERVER_IP..."

    local host_key
    host_key=$(ssh-keyscan -t ed25519 "$SERVER_IP" 2>/dev/null | grep ed25519 | awk '{print $2 " " $3}')

    if [[ -z "$host_key" ]]; then
        log_error "Could not retrieve SSH host key"
        echo ""
        echo "Trying to get it directly from the server..."
        host_key=$(run_on_server "cat /etc/ssh/ssh_host_ed25519_key.pub" 2>/dev/null | awk '{print $1 " " $2}')
    fi

    if [[ -z "$host_key" ]]; then
        log_error "Failed to retrieve host key"
        exit 1
    fi

    log_success "Retrieved host key: ${host_key:0:50}..."
    echo ""

    # Update secrets.nix
    log_step "Updating secrets.nix with host key..."

    local secrets_nix="$PROJECT_ROOT/secrets.nix"

    if grep -q 'ssh-ed25519 AAAA\.\.\.' "$secrets_nix"; then
        # Replace placeholder
        sed -i.bak "s|ssh-ed25519 AAAA\.\.\. root@andromeda|${host_key} root@andromeda|g" "$secrets_nix"
        rm -f "${secrets_nix}.bak"
        log_success "Updated secrets.nix with server host key"
    elif grep -q "$host_key" "$secrets_nix"; then
        log_info "Host key already present in secrets.nix"
    else
        log_warn "Could not auto-update secrets.nix"
        echo ""
        echo "Please manually update secrets.nix with:"
        echo "  andromeda = \"${host_key} root@andromeda\";"
        echo ""
        press_enter
    fi
}

# =============================================================================
# Disk Setup
# =============================================================================

setup_disks() {
    if [[ "$SKIP_DISKS" == "true" ]]; then
        log_info "Skipping disk setup (--skip-disks)"
        return
    fi

    log_header "Storage Disk Setup"

    echo "This step will help you identify and format storage disks for MergerFS."
    echo ""
    echo -e "${YELLOW}WARNING: This will DESTROY all data on the selected disks!${NC}"
    echo ""

    if ! confirm "Do you want to set up storage disks?"; then
        log_info "Skipping disk setup"
        return
    fi

    # List available disks
    log_step "Listing available disks on server..."
    echo ""

    run_on_server "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL | grep -E 'disk|NAME'" || true

    echo ""
    log_info "Disk IDs (use these for reliable mounting):"
    run_on_server "ls -la /dev/disk/by-id/ | grep -E 'ata-|nvme-' | grep -v part" || true

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Collect disks to format
    local disks_to_format=()
    local disk_configs=()

    while true; do
        echo "Enter a disk device to format for storage (e.g., sdb, sdc)"
        echo "Or press Enter when done adding disks."
        read -r -p "Disk device: " disk_device

        if [[ -z "$disk_device" ]]; then
            break
        fi

        # Verify disk exists
        if run_on_server "test -b /dev/${disk_device}" 2>/dev/null; then
            local disk_size
            disk_size=$(run_on_server "lsblk -dn -o SIZE /dev/${disk_device}" 2>/dev/null || echo "unknown")

            echo ""
            log_warn "You are about to format /dev/${disk_device} (${disk_size})"

            if confirm "Are you SURE you want to format this disk? ALL DATA WILL BE LOST!"; then
                disks_to_format+=("$disk_device")
                log_success "Added $disk_device to format list"
            else
                log_info "Skipped $disk_device"
            fi
        else
            log_error "Disk /dev/${disk_device} does not exist"
        fi
        echo ""
    done

    if [[ ${#disks_to_format[@]} -eq 0 ]]; then
        log_info "No disks selected for formatting"
        return
    fi

    echo ""
    log_step "Disks to format: ${disks_to_format[*]}"
    echo ""

    if ! confirm "Final confirmation - format ${#disks_to_format[@]} disk(s)?"; then
        log_info "Aborted disk formatting"
        return
    fi

    # Format each disk
    local disk_num=1
    for disk in "${disks_to_format[@]}"; do
        log_step "Formatting /dev/${disk} as disk${disk_num}..."

        run_on_server "
            set -e
            # Unmount if mounted
            umount /dev/${disk}* 2>/dev/null || true

            # Create GPT partition table
            parted -s /dev/${disk} mklabel gpt

            # Create single partition
            parted -s /dev/${disk} mkpart primary ext4 0% 100%

            # Wait for partition to appear
            sleep 2

            # Format with ext4
            mkfs.ext4 -m 0 -T largefile4 -L disk${disk_num} /dev/${disk}1

            echo 'Disk formatted successfully'
        "

        log_success "Formatted /dev/${disk} as disk${disk_num}"

        # Get the disk ID
        local disk_id
        disk_id=$(run_on_server "ls -la /dev/disk/by-id/ | grep '${disk}1' | grep -E 'ata-|nvme-' | head -1 | awk '{print \$9}'" 2>/dev/null || echo "")

        if [[ -n "$disk_id" ]]; then
            disk_configs+=("disk${disk_num}=/dev/disk/by-id/${disk_id}")
            log_info "Disk ID: $disk_id"
        else
            log_warn "Could not determine disk ID for ${disk}"
        fi

        ((disk_num++))
        echo ""
    done

    # Generate disk configuration
    if [[ ${#disk_configs[@]} -gt 0 ]]; then
        echo ""
        log_step "Generated disk configuration for default.nix:"
        echo ""
        echo "storage.mergerfs.disks = {"

        for config in "${disk_configs[@]}"; do
            local name="${config%%=*}"
            local device="${config#*=}"
            echo "  ${name} = {"
            echo "    device = \"${device}\";"
            echo "    fsType = \"ext4\";"
            echo "  };"
        done

        echo "};"
        echo ""

        if confirm "Would you like to update the configuration file automatically?"; then
            update_disk_config "${disk_configs[@]}"
        else
            log_info "Please update hosts/andromeda/default.nix manually"
        fi
    fi
}

update_disk_config() {
    local configs=("$@")
    local config_file="$HOSTS_DIR/default.nix"

    log_step "Updating disk configuration in $config_file..."

    # Build the new disks block
    local disks_block="disks = {\n"
    for config in "${configs[@]}"; do
        local name="${config%%=*}"
        local device="${config#*=}"
        disks_block+="      ${name} = {\n"
        disks_block+="        device = \"${device}\";\n"
        disks_block+="        fsType = \"ext4\";\n"
        disks_block+="      };\n"
    done
    disks_block+="    };"

    # Create a temp file with the updated config
    local temp_file=$(mktemp)

    # Use awk to replace the disks block
    awk -v new_block="$disks_block" '
        /disks = \{/ {
            print "    " new_block
            # Skip until closing brace at same level
            brace_count = 1
            while (brace_count > 0 && (getline > 0)) {
                if ($0 ~ /\{/) brace_count++
                if ($0 ~ /\}/) brace_count--
            }
            next
        }
        { print }
    ' "$config_file" > "$temp_file"

    mv "$temp_file" "$config_file"
    log_success "Updated disk configuration"
}

# =============================================================================
# Generate Hardware Configuration
# =============================================================================

generate_hardware_config() {
    log_header "Hardware Configuration"

    local hw_config="$HOSTS_DIR/hardware-configuration.nix"

    echo "The hardware configuration file needs to be generated on the server."
    echo ""

    if confirm "Generate hardware configuration from the server?"; then
        log_step "Generating hardware configuration..."

        local temp_hw_config=$(mktemp)

        if run_on_server "nixos-generate-config --show-hardware-config" > "$temp_hw_config" 2>/dev/null; then
            # Backup existing
            if [[ -f "$hw_config" ]]; then
                cp "$hw_config" "${hw_config}.backup"
            fi

            mv "$temp_hw_config" "$hw_config"
            log_success "Hardware configuration generated"
            log_info "Saved to: $hw_config"
        else
            log_warn "Could not generate hardware config automatically"
            log_info "You may need to generate it manually on the server:"
            echo "  nixos-generate-config --show-hardware-config > hardware-configuration.nix"
            rm -f "$temp_hw_config"
        fi
    else
        log_info "Skipping hardware configuration generation"
    fi
}

# =============================================================================
# Generate Secrets
# =============================================================================

generate_secrets() {
    if [[ "$SKIP_SECRETS" == "true" ]]; then
        log_info "Skipping secrets generation (--skip-secrets)"
        return
    fi

    log_header "Secrets Setup"

    local env_file="$PROJECT_ROOT/.env.secrets"

    if [[ ! -f "$env_file" ]]; then
        log_warn ".env.secrets file not found"
        echo ""
        echo "Please create .env.secrets with your secrets:"
        echo "  cp env.secrets.example .env.secrets"
        echo "  vim .env.secrets"
        echo ""

        if [[ -f "$PROJECT_ROOT/env.secrets.example" ]]; then
            if confirm "Would you like to create .env.secrets from template now?"; then
                cp "$PROJECT_ROOT/env.secrets.example" "$env_file"
                log_success "Created .env.secrets from template"
                echo ""
                echo "Please edit .env.secrets and fill in your values."
                echo "When done, save the file and press Enter."
                press_enter

                # Open in editor if available
                if command -v "${EDITOR:-vim}" &> /dev/null; then
                    "${EDITOR:-vim}" "$env_file"
                fi
            else
                log_info "Skipping secrets generation"
                return
            fi
        else
            log_error "env.secrets.example not found"
            return
        fi
    fi

    # Run secrets generation script
    log_step "Generating encrypted secrets..."

    if [[ -x "$SCRIPT_DIR/generate-secrets.sh" ]]; then
        "$SCRIPT_DIR/generate-secrets.sh" "$env_file"
    else
        log_error "generate-secrets.sh not found or not executable"
        return
    fi

    # Verify secrets were created
    local secret_count
    secret_count=$(find "$SECRETS_DIR" -name "*.age" -type f 2>/dev/null | wc -l)

    if [[ "$secret_count" -gt 0 ]]; then
        log_success "Generated $secret_count secret file(s)"
    else
        log_warn "No secret files generated"
    fi
}

# =============================================================================
# Pre-deployment Validation
# =============================================================================

validate_configuration() {
    log_header "Validating Configuration"

    local errors=0

    # Check secrets.nix for placeholder key
    if grep -q 'ssh-ed25519 AAAA\.\.\.' "$PROJECT_ROOT/secrets.nix" 2>/dev/null; then
        log_error "secrets.nix still contains placeholder host key"
        ((errors++))
    else
        log_success "secrets.nix has valid host key"
    fi

    # Check for required secret files
    local required_secrets=(
        "tailscale-auth-key.age"
        "cloudflare-api-token.age"
        "cloudflare-zone-id.age"
    )

    for secret in "${required_secrets[@]}"; do
        if [[ -f "$SECRETS_DIR/$secret" ]]; then
            log_success "Found $secret"
        else
            log_warn "Missing $secret (optional but recommended)"
        fi
    done

    # Check hardware configuration
    if [[ -f "$HOSTS_DIR/hardware-configuration.nix" ]]; then
        if grep -q 'by-label/nixos' "$HOSTS_DIR/hardware-configuration.nix"; then
            log_success "Hardware configuration present"
        else
            log_warn "Hardware configuration may need customization"
        fi
    else
        log_error "Hardware configuration missing"
        ((errors++))
    fi

    # Validate flake
    log_step "Validating Nix flake..."
    if (cd "$PROJECT_ROOT" && nix flake check --no-build 2>&1); then
        log_success "Flake validation passed"
    else
        log_warn "Flake validation had warnings (may still work)"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "$errors critical error(s) found"
        echo ""
        echo "Please fix the errors above before deploying."
        return 1
    fi

    log_success "Configuration validation complete"
    return 0
}

# =============================================================================
# Deploy
# =============================================================================

deploy() {
    if [[ "$SKIP_DEPLOY" == "true" ]]; then
        log_info "Skipping deployment (--skip-deploy)"
        return
    fi

    log_header "Deployment"

    echo "Ready to deploy NixOS configuration to $SERVER_IP"
    echo ""
    echo "This will:"
    echo "  1. Build the NixOS configuration"
    echo "  2. Copy it to the server"
    echo "  3. Activate the new configuration"
    echo ""

    if ! confirm "Proceed with deployment?"; then
        log_info "Deployment cancelled"
        return
    fi

    # Determine deployment user
    local deploy_user="$SERVER_USER"
    local use_sudo=""

    if [[ "$deploy_user" != "root" ]]; then
        use_sudo="--use-remote-sudo"
    fi

    log_step "Building and deploying NixOS configuration..."
    echo ""

    # Run nixos-rebuild
    cd "$PROJECT_ROOT"

    if nixos-rebuild switch \
        --flake ".#andromeda" \
        --target-host "${deploy_user}@${SERVER_IP}" \
        $use_sudo \
        --show-trace; then

        echo ""
        log_success "Deployment completed successfully!"
    else
        echo ""
        log_error "Deployment failed"
        echo ""
        echo "Check the error messages above for details."
        echo "Common issues:"
        echo "  - Secret decryption failures (check host key in secrets.nix)"
        echo "  - Missing hardware configuration"
        echo "  - Network configuration mismatch"
        exit 1
    fi
}

# =============================================================================
# Post-deployment
# =============================================================================

post_deployment() {
    log_header "Post-Deployment"

    echo "Deployment complete! Here's what to do next:"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. VERIFY SERVICES"
    echo "   ssh admin@${SERVER_IP}"
    echo "   systemctl status jellyfin sonarr radarr prowlarr jellyseerr"
    echo "   podman ps  # Check containers"
    echo ""
    echo "2. ACCESS WEB INTERFACES (Local)"
    echo "   Jellyfin:    http://${SERVER_IP}:8096"
    echo "   Sonarr:      http://${SERVER_IP}:8989"
    echo "   Radarr:      http://${SERVER_IP}:7878"
    echo "   Prowlarr:    http://${SERVER_IP}:9696"
    echo "   Jellyseerr:  http://${SERVER_IP}:5055"
    echo "   qBittorrent: http://${SERVER_IP}:8080"
    echo ""
    echo "3. INITIAL SETUP"
    echo "   - Complete Jellyfin setup wizard"
    echo "   - Configure Sonarr/Radarr download clients"
    echo "   - Add indexers to Prowlarr"
    echo "   - Connect Jellyseerr to Jellyfin"
    echo ""
    echo "4. TAILSCALE (if configured)"
    echo "   Check connection: tailscale status"
    echo "   Access via: http://andromeda:PORT"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Commit changes if git repo
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        echo "Don't forget to commit your changes:"
        echo "  git add -A"
        echo "  git commit -m 'Initial deployment configuration'"
        echo "  git push"
        echo ""
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                           ║"
    echo "║         🚀 Andromeda Home Media Server Installation                       ║"
    echo "║                                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    parse_args "$@"

    echo "Configuration:"
    echo "  Server IP:    $SERVER_IP"
    echo "  Server User:  $SERVER_USER"
    echo "  Skip Disks:   $SKIP_DISKS"
    echo "  Skip Secrets: $SKIP_SECRETS"
    echo "  Skip Deploy:  $SKIP_DEPLOY"
    echo ""

    # Run installation steps
    check_prerequisites
    test_server_connection
    retrieve_host_key
    setup_disks
    generate_hardware_config
    generate_secrets

    if validate_configuration; then
        deploy
        post_deployment
    else
        echo ""
        log_warn "Configuration validation failed. Please fix issues and re-run."
        echo "  ./scripts/install.sh --skip-disks --skip-secrets"
    fi

    echo ""
    log_success "Installation script completed!"
    echo ""
}

main "$@"
