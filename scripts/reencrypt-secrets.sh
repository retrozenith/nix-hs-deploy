#!/usr/bin/env bash
#
# reencrypt-secrets.sh
# Re-encrypts all existing .age secrets with updated keys from secrets.nix
#
# This is useful when:
#   - You add a new SSH key (e.g., server host key)
#   - You remove an SSH key
#   - You want to ensure all secrets are encrypted with current keys
#
# Usage:
#   ./scripts/reencrypt-secrets.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$PROJECT_ROOT/secrets"
SECRETS_NIX="$PROJECT_ROOT/secrets.nix"
IDENTITY_FILE="${SSH_IDENTITY:-$HOME/.ssh/andromeda_deploy}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if age is available
check_age() {
    if ! command -v age &> /dev/null; then
        log_error "age not found in PATH"
        echo ""
        echo "Ensure nix profile is in your PATH:"
        echo "  export PATH=\"\$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:\$PATH\""
        echo ""
        echo "Or run from nix-shell:"
        echo "  nix develop"
        echo ""
        exit 1
    fi
}

# Check if identity file exists
check_identity() {
    if [[ ! -f "$IDENTITY_FILE" ]]; then
        log_error "Identity file not found: $IDENTITY_FILE"
        echo ""
        echo "Specify your SSH private key with:"
        echo "  export SSH_IDENTITY=~/.ssh/your_key"
        echo "  ./scripts/reencrypt-secrets.sh"
        echo ""
        exit 1
    fi

    log_info "Using identity: $IDENTITY_FILE"
}

# Check if secrets.nix exists and has valid keys
check_secrets_nix() {
    if [[ ! -f "$SECRETS_NIX" ]]; then
        log_error "secrets.nix not found at $SECRETS_NIX"
        exit 1
    fi

    # Check for valid SSH keys
    if ! grep -qE 'ssh-ed25519 [A-Za-z0-9+/]{68}' "$SECRETS_NIX"; then
        log_error "No valid SSH keys found in secrets.nix"
        exit 1
    fi
}

# Extract SSH public keys from secrets.nix
extract_recipients() {
    local recipients_file="$1"

    # Extract all SSH public keys (excluding commented lines)
    grep -v '^\s*#' "$SECRETS_NIX" | grep -oE 'ssh-ed25519 [A-Za-z0-9+/=]+' | sort -u > "$recipients_file"

    if [[ ! -s "$recipients_file" ]]; then
        log_error "No valid SSH keys found in secrets.nix"
        return 1
    fi

    local count=$(wc -l < "$recipients_file")
    log_info "Found $count recipient key(s) in secrets.nix"

    # Display the keys for verification
    echo ""
    log_info "Recipient keys:"
    while IFS= read -r key; do
        echo "  - ${key:0:20}...${key: -20}"
    done < "$recipients_file"
    echo ""
}

# Re-encrypt a single secret
reencrypt_secret() {
    local secret_file="$1"
    local recipients_file="$2"
    local secret_name=$(basename "$secret_file")

    # Skip non-.age files
    if [[ "$secret_name" != *.age ]]; then
        return 0
    fi

    # Skip secrets.nix if it's in the secrets directory
    if [[ "$secret_name" == "secrets.nix" ]]; then
        return 0
    fi

    log_info "Re-encrypting: $secret_name"

    # Create temporary file for decrypted content
    local tmp_decrypted=$(mktemp)
    local tmp_encrypted=$(mktemp)

    # Decrypt the secret
    if ! age -d -i "$IDENTITY_FILE" "$secret_file" > "$tmp_decrypted" 2>/dev/null; then
        log_error "Failed to decrypt $secret_name (wrong key or corrupted file)"
        rm -f "$tmp_decrypted" "$tmp_encrypted"
        return 1
    fi

    # Build recipient arguments
    local recipient_args=""
    while IFS= read -r key; do
        recipient_args="$recipient_args -r '$key'"
    done < "$recipients_file"

    # Re-encrypt with all recipient keys
    if eval "age $recipient_args -o '$tmp_encrypted' < '$tmp_decrypted'" 2>/dev/null; then
        # Replace the original file
        mv "$tmp_encrypted" "$secret_file"
        log_success "✓ Re-encrypted $secret_name"
        rm -f "$tmp_decrypted"
        return 0
    else
        log_error "Failed to re-encrypt $secret_name"
        rm -f "$tmp_decrypted" "$tmp_encrypted"
        return 1
    fi
}

# Main re-encryption logic
reencrypt_all() {
    local recipients_file=$(mktemp)

    # Extract recipients from secrets.nix
    if ! extract_recipients "$recipients_file"; then
        rm -f "$recipients_file"
        exit 1
    fi

    # Ask for confirmation
    echo -e "${YELLOW}This will re-encrypt all secrets with the keys from secrets.nix${NC}"
    echo -e "${YELLOW}Make sure you have the correct identity file: $IDENTITY_FILE${NC}"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Cancelled by user"
        rm -f "$recipients_file"
        exit 0
    fi

    echo ""
    log_info "Starting re-encryption..."
    echo ""

    local total=0
    local success=0
    local failed=0

    # Process each .age file in the secrets directory
    for secret_file in "$SECRETS_DIR"/*.age; do
        if [[ -f "$secret_file" ]]; then
            ((total++)) || true
            if reencrypt_secret "$secret_file" "$recipients_file"; then
                ((success++)) || true
            else
                ((failed++)) || true
            fi
        fi
    done

    # Cleanup
    rm -f "$recipients_file"

    # Summary
    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║           Re-encryption Summary           ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""
    echo "  Total secrets:    $total"
    echo "  Successfully re-encrypted: $success"
    echo "  Failed:           $failed"
    echo ""

    if [[ $failed -eq 0 ]]; then
        log_success "All secrets re-encrypted successfully!"
        echo ""
        echo "Next steps:"
        echo "  1. Test decryption on the server"
        echo "  2. git add secrets/*.age"
        echo "  3. git commit -m 'Re-encrypt secrets with updated keys'"
        echo ""
    else
        log_error "Some secrets failed to re-encrypt"
        exit 1
    fi
}

# Main
main() {
    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║     Agenix Secrets Re-encryption Tool     ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""

    check_age
    check_identity
    check_secrets_nix

    cd "$PROJECT_ROOT"
    reencrypt_all
}

main "$@"
