#!/usr/bin/env bash
#
# generate-secrets.sh
# Generates encrypted agenix secrets from a .env file
#
# If 'age' is not found, ensure nix profile is in PATH:
#   export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
#
# Usage:
#   ./scripts/generate-secrets.sh [path-to-env-file]
#
# The .env file should contain key=value pairs like:
#   TAILSCALE_AUTH_KEY=tskey-auth-xxxxx
#   CLOUDFLARE_API_TOKEN=xxxxx
#   etc.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$PROJECT_ROOT/secrets"
SECRETS_NIX="$PROJECT_ROOT/secrets.nix"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default .env file location
ENV_FILE="${1:-$PROJECT_ROOT/.env.secrets}"

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

# Check if agenix is available
check_agenix() {
    if ! command -v agenix &> /dev/null; then
        log_error "agenix not found. Please run 'nix develop' first."
        echo ""
        echo "Or ensure nix profile is in PATH:"
        echo "  export PATH=\"\$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:\$PATH\""
        echo ""
        exit 1
    fi
}

# Check if .env file exists
check_env_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Environment file not found: $ENV_FILE"
        echo ""
        echo "Create the secrets file by copying the template:"
        echo ""
        echo "  cp env.secrets.example .env.secrets"
        echo "  vim .env.secrets  # Fill in your values"
        echo "  ./scripts/generate-secrets.sh"
        echo ""
        exit 1
    fi
}

# Check if secrets.nix has valid keys
check_secrets_nix() {
    if [[ ! -f "$SECRETS_NIX" ]]; then
        log_error "secrets.nix not found at $SECRETS_NIX"
        exit 1
    fi

    # Check if there are placeholder keys (incomplete keys like "AAAA...") that are NOT commented out
    if grep -v '^\s*#' "$SECRETS_NIX" | grep -q 'ssh-ed25519 AAAA\.\.\.'; then
        log_error "secrets.nix contains placeholder SSH keys!"
        echo ""
        echo "Before generating secrets, you must either:"
        echo ""
        echo "Option 1: Add the server's SSH host key (recommended for deployment)"
        echo "   ssh-keyscan <server-ip> | grep ed25519"
        echo "   # Or on the server: cat /etc/ssh/ssh_host_ed25519_key.pub"
        echo ""
        echo "Option 2: Comment out the placeholder and use admin key only"
        echo "   # andromeda = \"ssh-ed25519 AAAA... root@andromeda\";"
        echo "   (You'll need to re-encrypt with host key later: agenix -r)"
        echo ""
        exit 1
    fi

    # Check if at least one valid key exists
    if ! grep -qE 'ssh-ed25519 [A-Za-z0-9+/]{68}' "$SECRETS_NIX"; then
        log_error "No valid SSH keys found in secrets.nix"
        echo ""
        echo "Add at least one SSH public key to secrets.nix"
        echo ""
        exit 1
    fi

    # Warn if no host key is configured
    if ! grep -qE '^\s*andromeda\s*=' "$SECRETS_NIX" || grep -qE '^\s*#\s*andromeda\s*=' "$SECRETS_NIX"; then
        log_warn "No host key configured - secrets encrypted with admin key only"
        log_warn "After server is up, add host key and run: agenix -r"
        echo ""
    fi
}

# Create a single encrypted secret
create_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local secret_file="$SECRETS_DIR/${secret_name}.age"

    if [[ -z "$secret_value" ]]; then
        log_warn "Skipping $secret_name (empty value)"
        return
    fi

    log_info "Creating $secret_name..."

    # Create the encrypted secret
    echo -n "$secret_value" | agenix -e "$secret_file" -i /dev/stdin 2>/dev/null || {
        # Fallback: use a temp file
        local tmp_file=$(mktemp)
        echo -n "$secret_value" > "$tmp_file"

        # Use age directly if agenix doesn't support stdin
        cd "$PROJECT_ROOT"
        echo -n "$secret_value" | age -R <(nix eval --raw -f secrets.nix --apply 'x: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (n: v: builtins.concatStringsSep "\n" v.publicKeys) x))' 2>/dev/null || echo "") -o "$secret_file" 2>/dev/null || {
            # Final fallback: create with agenix edit
            EDITOR="tee" agenix -e "$secret_file" <<< "$secret_value" > /dev/null 2>&1
        }

        rm -f "$tmp_file"
    }

    if [[ -f "$secret_file" ]]; then
        log_success "Created $secret_file"
    else
        log_error "Failed to create $secret_name"
    fi
}

# Load .env file and create secrets
generate_secrets() {
    log_info "Loading secrets from $ENV_FILE"
    echo ""

    # Create secrets directory if it doesn't exist
    mkdir -p "$SECRETS_DIR"

    # Source the .env file
    set -a
    source "$ENV_FILE"
    set +a

    # Map environment variables to secret files
    declare -A SECRET_MAP=(
        ["tailscale-auth-key"]="${TAILSCALE_AUTH_KEY:-}"
        ["cloudflare-api-token"]="${CLOUDFLARE_API_TOKEN:-}"
        ["cloudflare-zone-id"]="${CLOUDFLARE_ZONE_ID:-}"
        ["caddy-email"]="${CADDY_EMAIL:-}"
        ["domain-jellyfin"]="${DOMAIN_JELLYFIN:-}"
        ["domain-prowlarr"]="${DOMAIN_PROWLARR:-}"
        ["domain-vault"]="${DOMAIN_VAULT:-}"
        ["domain-request"]="${DOMAIN_REQUEST:-}"
        ["domain-auth"]="${DOMAIN_AUTH:-}"
        ["domain-streamystats"]="${DOMAIN_STREAMYSTATS:-}"
        ["vaultwarden-admin-token"]="${VAULTWARDEN_ADMIN_TOKEN:-}"
        ["gluetun-wireguard-key"]="${GLUETUN_WIREGUARD_KEY:-}"
        ["streamystats-session-secret"]="${STREAMYSTATS_SESSION_SECRET:-}"
        ["streamystats-postgres-password"]="${STREAMYSTATS_POSTGRES_PASSWORD:-}"
        ["media-postgres-password"]="${MEDIA_POSTGRES_PASSWORD:-}"
    )

    local created=0
    local skipped=0

    for secret_name in "${!SECRET_MAP[@]}"; do
        secret_value="${SECRET_MAP[$secret_name]}"

        if [[ -n "$secret_value" ]]; then
            create_secret "$secret_name" "$secret_value"
            ((created++))
        else
            log_warn "Skipping $secret_name (not set in .env)"
            ((skipped++))
        fi
    done

    echo ""
    log_info "Summary: $created secrets created, $skipped skipped"
}

# Alternative: Generate using age directly (more reliable)
generate_secrets_with_age() {
    log_info "Loading secrets from $ENV_FILE"
    echo ""

    mkdir -p "$SECRETS_DIR"

    # Source the .env file
    set -a
    source "$ENV_FILE"
    set +a

    # Extract public keys from secrets.nix and convert to age format
    log_info "Reading public keys from secrets.nix..."

    # Create a temporary recipients file with SSH public keys directly
    # age can natively encrypt/decrypt with SSH keys - no conversion needed
    RECIPIENTS_FILE=$(mktemp)

    # Extract SSH public keys from secrets.nix (excluding commented lines)
    # Use the SSH key format directly (age supports this natively)
    while read -r ssh_key; do
        echo "$ssh_key" >> "$RECIPIENTS_FILE"
    done < <(grep -v '^\s*#' "$SECRETS_NIX" | grep -oE 'ssh-ed25519 [A-Za-z0-9+/=]+' | sort -u)

    if [[ ! -s "$RECIPIENTS_FILE" ]]; then
        log_error "No valid SSH keys found in secrets.nix"
        rm -f "$RECIPIENTS_FILE"
        exit 1
    fi

    log_info "Found $(wc -l < "$RECIPIENTS_FILE") recipient key(s)"
    echo ""

    # Create each secret - using SSH public keys directly
    create_age_secret() {
        local name="$1"
        local value="$2"
        local file="$SECRETS_DIR/${name}.age"

        if [[ -z "$value" ]]; then
            log_warn "Skipping $name (empty value)"
            return 1
        fi

        # Build recipient arguments for each SSH key
        local recipient_args=""
        while read -r key; do
            recipient_args="$recipient_args -r '$key'"
        done < "$RECIPIENTS_FILE"

        # Create the encrypted file using SSH public keys directly
        eval "echo -n '$value' | age $recipient_args -o '$file'" 2>/dev/null

        if [[ -f "$file" ]]; then
            log_success "Created $name.age"
            return 0
        else
            log_error "Failed to create $name.age"
            return 1
        fi
    }

    local created=0
    local skipped=0

    # Helper to track success/failure without triggering set -e
    try_create() {
        if create_age_secret "$1" "$2"; then
            ((created++)) || true
        else
            ((skipped++)) || true
        fi
    }

    # Tailscale
    try_create "tailscale-auth-key" "${TAILSCALE_AUTH_KEY:-}"

    # Cloudflare
    try_create "cloudflare-api-token" "${CLOUDFLARE_API_TOKEN:-}"
    try_create "cloudflare-zone-id" "${CLOUDFLARE_ZONE_ID:-}"

    # Caddy
    try_create "caddy-email" "${CADDY_EMAIL:-}"

    # Domains
    try_create "domain-jellyfin" "${DOMAIN_JELLYFIN:-}"
    try_create "domain-prowlarr" "${DOMAIN_PROWLARR:-}"
    try_create "domain-vault" "${DOMAIN_VAULT:-}"
    try_create "domain-request" "${DOMAIN_REQUEST:-}"
    try_create "domain-auth" "${DOMAIN_AUTH:-}"
    try_create "domain-streamystats" "${DOMAIN_STREAMYSTATS:-}"

    # Vaultwarden
    try_create "vaultwarden-admin-token" "${VAULTWARDEN_ADMIN_TOKEN:-}"

    # VPN
    try_create "gluetun-wireguard-key" "${GLUETUN_WIREGUARD_KEY:-}"

    # Streamystats
    try_create "streamystats-session-secret" "${STREAMYSTATS_SESSION_SECRET:-}"
    try_create "streamystats-postgres-password" "${STREAMYSTATS_POSTGRES_PASSWORD:-}"

    # Media PostgreSQL (Sonarr, Radarr, Prowlarr)
    try_create "media-postgres-password" "${MEDIA_POSTGRES_PASSWORD:-}"

    # Cleanup
    rm -f "$RECIPIENTS_FILE"

    echo ""
    log_info "Summary: $created secrets created, $skipped skipped"
    echo ""

    if [[ $created -gt 0 ]]; then
        log_success "Secrets generated successfully!"
        echo ""
        echo "Next steps:"
        echo "  1. git add secrets/*.age"
        echo "  2. git commit -m 'Add encrypted secrets'"
        echo "  3. git push"
        echo ""
    fi
}

# Main
main() {
    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║     Agenix Secrets Generator              ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""

    check_env_file
    check_secrets_nix

    # Check if age is available (more reliable than agenix for scripting)
    if command -v age &> /dev/null; then
        generate_secrets_with_age
    else
        log_error "age not found in PATH"
        echo ""
        echo "Ensure nix profile is in your PATH:"
        echo "  export PATH=\"\$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:\$PATH\""
        echo ""
        echo "Or install age with:"
        echo "  nix profile install nixpkgs#age"
        echo ""
        exit 1
    fi
}

main "$@"
