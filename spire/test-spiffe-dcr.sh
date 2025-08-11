#!/bin/bash

# SPIFFE DCR SPI Test Script
# Tests the Keycloak SPIFFE Dynamic Client Registration endpoint

set -e

# Generate a random UUID for workload identification
generate_workload_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        # Fallback UUID generation using /dev/urandom
        printf '%08x-%04x-%04x-%04x-%012x\n' \
            $((RANDOM * RANDOM)) \
            $((RANDOM % 65536)) \
            $(((RANDOM % 4096) | 16384)) \
            $(((RANDOM % 16384) | 32768)) \
            $((RANDOM * RANDOM * RANDOM % 281474976710656))
    fi
}

# Generate workload UUID and set default SPIFFE ID
WORKLOAD_UUID=$(generate_workload_uuid)

# Configuration (modify these variables for your environment)
KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL:-http://localhost:8080}"
REALM_NAME="${REALM_NAME:-mcp-realm}"
TRUST_DOMAIN="${TRUST_DOMAIN:-example.org}"
PARENT_SPIFFE_ID="${PARENT_SPIFFE_ID:-spiffe://example.org/agent}"
SPIFFE_ID="${SPIFFE_ID:-spiffe://${TRUST_DOMAIN}/${WORKLOAD_UUID}}"
CLIENT_NAME="${CLIENT_NAME:-Test SPIFFE Service}"
JWKS_URL="${JWKS_URL:-https://test-service:8443/.well-known/jwks}"
JWT_SVID_TTL="${JWT_SVID_TTL:-60}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to prompt for continuation
prompt_continue() {
    if [ "$AUTO_CONTINUE" != true ]; then
        read -r -p "Continue (Y/n)? " response
        response=${response:-Y}
        if [[ "$response" =~ ^[Nn]$ ]]; then
            echo "Aborting."
            exit 1
        fi
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --keycloak-url URL       Keycloak base URL (default: http://localhost:8080)"
    echo "  --realm REALM            Realm name (default: spiffe-realm)"
    echo "  --trust-domain DOMAIN    SPIFFE trust domain (default: example.org)"
    echo "  --parent-id ID           Parent SPIFFE ID (default: spiffe://example.org/agent)"
    echo "  --spiffe-id ID           SPIFFE ID for testing (default: auto-generated with UUID)"
    echo "  --client-name NAME       Client name (default: Test SPIFFE Service)"
    echo "  --jwks-url URL           JWKS URL (default: https://test-service:8443/.well-known/jwks)"
    echo "  --jwt-ttl SECONDS        JWT SVID TTL in seconds (default: 60)"
    echo "  --software-statement JWT Use provided JWT instead of generating one"
    echo "  --use-mock-jwt           Use mock JWT instead of SPIRE agent (default: false)"
    echo "  --no-auto-register       Skip automatic workload registration"
    echo "  --auto-continue          Don't prompt for continuation"
    echo "  --verbose                Enable verbose output"
    echo "  --help                   Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  KEYCLOAK_BASE_URL        Keycloak base URL"
    echo "  REALM_NAME               Realm name"
    echo "  TRUST_DOMAIN             SPIFFE trust domain"
    echo "  PARENT_SPIFFE_ID         Parent SPIFFE ID"
    echo "  SPIFFE_ID                SPIFFE ID"
    echo "  CLIENT_NAME              Client name"
    echo "  JWKS_URL                 JWKS URL"
    echo "  JWT_SVID_TTL             JWT SVID TTL in seconds"
    echo ""
    echo "Examples:"
    echo "  $0 --keycloak-url https://keycloak.example.com --realm production"
    echo "  $0 --trust-domain production.com --parent-id spiffe://production.com/node"
    echo "  $0 --use-mock-jwt --spiffe-id spiffe://example.org/workload/my-service"
    echo "  $0 --software-statement 'eyJhbGciOiJSUzI1NiIs...'"
}

# Function to check if docker and SPIRE containers are available
check_spire_environment() {
    print_status "Checking SPIRE environment..."
    
    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not available. Please install Docker."
        return 1
    fi
    
    # Check if SPIRE server container is running
    if ! docker ps | grep -q "spire-server"; then
        print_error "SPIRE server container is not running. Please start it with 'docker compose up -d spire-server' or 'docker run'"
        print_error "Looking for container with 'spire-server' in the name"
        return 1
    fi
    
    # Check if SPIRE agent container is running
    if ! docker ps | grep -q "spire-agent"; then
        print_error "SPIRE agent container is not running. Please start it with 'docker compose up -d spire-agent' or 'docker run'"
        print_error "Looking for container with 'spire-agent' in the name"
        return 1
    fi
    
    print_success "SPIRE environment is ready"
    print_status "Found running containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(spire-server|spire-agent)" || true
    return 0
}

# Function to check and register SPIRE workload entry
check_and_register_workload() {
    print_status "Checking/Registering SPIRE workload entry..."
    print_status "SPIFFE ID: $SPIFFE_ID"
    print_status "Parent ID: $PARENT_SPIFFE_ID"
    
    # Get the SPIRE server container name
    local spire_server_container=$(docker ps --format "{{.Names}}" | grep spire-server | head -n1)
    if [ -z "$spire_server_container" ]; then
        print_error "Could not find SPIRE server container name"
        return 1
    fi
    
    print_status "Using SPIRE server container: $spire_server_container"
    
    # Check if workload entry exists
    if docker exec "$spire_server_container" /opt/spire/bin/spire-server entry show -spiffeID "$SPIFFE_ID" 2>/dev/null | grep -q "Entry ID"; then
        print_success "Workload entry already exists."
        return 0
    fi
    
    print_status "Registering workload entry..."
    if docker exec "$spire_server_container" /opt/spire/bin/spire-server entry create \
        -parentID "$PARENT_SPIFFE_ID" \
        -spiffeID "$SPIFFE_ID" \
        -jwtSVIDTTL "$JWT_SVID_TTL" \
        -selector unix:uid:0; then
        print_success "Workload entry created successfully."
        return 0
    else
        print_error "Failed to create workload entry."
        return 1
    fi
}

# Function to get SVID from SPIRE agent using docker exec
get_spire_jwt_svid() {
    local audience="${KEYCLOAK_BASE_URL}/realms/${REALM_NAME}"
    print_status "Fetching JWT SVID from SPIRE..." >&2
    print_status "Audience: $audience" >&2
    print_status "SPIFFE ID: $SPIFFE_ID" >&2
    
    # Get the SPIRE agent container name
    local spire_agent_container=$(docker ps --format "{{.Names}}" | grep spire-agent | head -n1)
    if [ -z "$spire_agent_container" ]; then
        print_error "Could not find SPIRE agent container name" >&2
        return 1
    fi
    
    print_status "Using SPIRE agent container: $spire_agent_container" >&2
    
    # Retry logic - sometimes the agent needs time to sync with the server
    local max_retries=10
    local retry_delay=2
    local attempt=1
    local jwt_output
    
    while [ $attempt -le $max_retries ]; do
        print_status "Attempt $attempt/$max_retries: Fetching JWT SVID..." >&2
        
        if jwt_output=$(docker exec "$spire_agent_container" /opt/spire/bin/spire-agent api fetch jwt \
            --audience "$audience" \
            --spiffeID "$SPIFFE_ID" \
            --socketPath /opt/spire/sockets/workload_api.sock 2>/dev/null); then
            
            # Check if we got a valid response (not empty and contains token info)
            if [ -n "$jwt_output" ] && echo "$jwt_output" | grep -q "token"; then
                print_success "Successfully obtained JWT SVID on attempt $attempt" >&2
                break
            else
                print_warning "Got empty or invalid response on attempt $attempt" >&2
            fi
        else
            print_warning "Failed to fetch JWT SVID on attempt $attempt" >&2
        fi
        
        if [ $attempt -lt $max_retries ]; then
            print_status "Waiting ${retry_delay} seconds before retry..." >&2
            sleep $retry_delay
        fi
        
        attempt=$((attempt + 1))
    done
    
    # Check if we succeeded after all retries
    if [ $attempt -gt $max_retries ]; then
        print_error "Failed to get JWT SVID after $max_retries attempts" >&2
        print_status "This can happen if:" >&2
        echo "  - The workload entry hasn't synced to the agent yet" >&2
        echo "  - The SPIFFE ID doesn't match exactly" >&2
        echo "  - The parent-child relationship is incorrect" >&2
        echo "  - The agent isn't properly connected to the server" >&2
        return 1
    fi
    
    # Process the successful response
    if [ -n "$jwt_output" ]; then
        
        if [ "$VERBOSE" = true ]; then
            print_status "SPIRE JWT Output:" >&2
            echo "$jwt_output" >&2
        fi
        
        # Extract JWT token from output
        local jwt_token
        jwt_token=$(echo "$jwt_output" | awk '/^token\(/ {getline; gsub(/^[[:space:]]+/, ""); gsub(/[[:space:]]+$/, ""); print $0}')
        
        # Debug the extraction
        if [ "$VERBOSE" = true ]; then
            print_status "Raw JWT extraction result: '$jwt_token'" >&2
            print_status "JWT length: ${#jwt_token}" >&2
        fi
        
        if [ -z "$jwt_token" ]; then
            print_error "Failed to extract JWT token from SPIRE output" >&2
            print_status "Trying alternative extraction methods..." >&2
            
            # Try alternative extraction - look for lines that look like JWTs
            jwt_token=$(echo "$jwt_output" | grep -E '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' | head -n1 | tr -d ' \t\n\r')
            
            if [ -z "$jwt_token" ]; then
                print_error "Alternative extraction also failed" >&2
                print_status "SPIRE output for debugging:" >&2
                echo "$jwt_output" | cat -n >&2
                return 1
            else
                print_success "Alternative extraction succeeded" >&2
            fi
        fi
        
        print_success "JWT SVID obtained successfully (length: ${#jwt_token} characters)" >&2
        echo "$jwt_token"
        return 0
    else
        print_error "Failed to get JWT SVID from SPIRE agent" >&2
        return 1
    fi
}

# Function to generate a mock JWT for testing
generate_mock_jwt() {
    local iss="spiffe://${TRUST_DOMAIN}"
    local sub="${SPIFFE_ID}"
    local aud="${KEYCLOAK_BASE_URL}/realms/${REALM_NAME}"
    local current_time=$(date +%s)
    local exp_time=$((current_time + 3600)) # 1 hour from now
    
    print_status "Generating mock JWT software statement..."
    
    # JWT Header
    local header='{"alg":"RS256","typ":"JWT"}'
    local header_b64=$(echo -n "$header" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    # JWT Payload
    local payload=$(cat <<EOF
{
  "iss": "$iss",
  "sub": "$sub", 
  "aud": "$aud",
  "jwks_url": "$JWKS_URL",
  "client_auth": "private_key_jwt",
  "exp": $exp_time,
  "iat": $current_time
}
EOF
)
    local payload_b64=$(echo -n "$payload" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    # Mock signature (this won't validate, but useful for endpoint testing)
    local signature="mock_signature_for_testing_only"
    local signature_b64=$(echo -n "$signature" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    local mock_jwt="${header_b64}.${payload_b64}.${signature_b64}"
    print_success "Mock JWT generated (length: ${#mock_jwt} characters)" >&2
    echo "$mock_jwt"
}

# Function to decode and display JWT
decode_jwt() {
    local jwt="$1"
    local header_b64=$(echo "$jwt" | cut -d. -f1)
    local payload_b64=$(echo "$jwt" | cut -d. -f2)
    
    # Add padding if needed for header
    local header_padding=$((4 - ${#header_b64} % 4))
    if [ $header_padding -ne 4 ]; then
        header_b64="${header_b64}$(printf '=%.0s' $(seq 1 $header_padding))"
    fi
    local header=$(echo "$header_b64" | tr '_-' '/+' | base64 -d 2>/dev/null || echo "Could not decode header")
    
    # Add padding if needed for payload
    local payload_padding=$((4 - ${#payload_b64} % 4))
    if [ $payload_padding -ne 4 ]; then
        payload_b64="${payload_b64}$(printf '=%.0s' $(seq 1 $payload_padding))"
    fi
    local payload=$(echo "$payload_b64" | tr '_-' '/+' | base64 -d 2>/dev/null || echo "Could not decode payload")
    
    echo "Header:"
    echo "$header" | jq '.' 2>/dev/null || echo "$header"
    echo "Claims:"
    echo "$payload" | jq '.' 2>/dev/null || echo "$payload"
}

# Function to validate JWT structure
validate_jwt_structure() {
    local jwt="$1"
    
    # Clean the JWT of any whitespace/newlines
    jwt=$(echo "$jwt" | tr -d ' \t\n\r')
    
    if [ "$VERBOSE" = true ]; then
        print_status "Validating JWT: '${jwt:0:50}...'"
        print_status "JWT length after cleaning: ${#jwt}"
    fi
    
    if [[ ! "$jwt" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
        print_error "Invalid JWT format. Expected format: header.payload.signature"
        print_error "Received: '${jwt:0:100}...'"
        return 1
    fi
    
    if [ "$VERBOSE" = true ]; then
        print_status "JWT Structure Validation:"
        decode_jwt "$jwt"
    fi
    
    return 0
}

# Function to make the DCR request
make_dcr_request() {
    local software_statement="$1"
    local endpoint="${KEYCLOAK_BASE_URL}/realms/${REALM_NAME}/clients-registrations/spiffe-dcr/register"
    
    print_status "Making DCR request to: $endpoint"
    
    # Prepare request body
    local request_body=$(cat <<EOF
{
  "software_statement": "$software_statement",
  "client_name": "$CLIENT_NAME",
  "grant_types": ["client_credentials"],
  "scope": "spiffe:workload"
}
EOF
)
    
    if [ "$VERBOSE" = true ]; then
        print_status "Request body:"
        echo "$request_body" | jq '.'
    fi
    
    # Make the request
    local response
    local http_code
    
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$request_body" \
        "$endpoint")
    
    http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    print_status "HTTP Status Code: $http_code"
    
    if [ "$http_code" = "201" ]; then
        print_success "Client registration successful!"
        echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        return 0
    else
        print_error "Client registration failed!"
        echo "Response body:"
        echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        return 1
    fi
}

# Function to test endpoint availability
test_endpoint_availability() {
    local base_endpoint="${KEYCLOAK_BASE_URL}/realms/${REALM_NAME}"
    
    print_status "Testing Keycloak endpoint availability..."
    
    if curl -s -f "$base_endpoint" > /dev/null; then
        print_success "Keycloak realm endpoint is accessible"
    else
        print_error "Cannot reach Keycloak realm endpoint: $base_endpoint"
        print_warning "Please check:"
        echo "  - Keycloak is running and accessible"
        echo "  - Realm name is correct: $REALM_NAME"
        echo "  - URL is correct: $KEYCLOAK_BASE_URL"
        return 1
    fi
}

# Function to run pre-flight checks
run_preflight_checks() {
    print_status "Running pre-flight checks..."
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. JSON output will not be formatted."
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not found. Please install curl."
        return 1
    fi
    
    # Test endpoint availability
    test_endpoint_availability || return 1
    
    print_success "Pre-flight checks passed"
}

# Parse command line arguments
VERBOSE=false
USE_SPIRE_AGENT=true
CUSTOM_SOFTWARE_STATEMENT=""
AUTO_CONTINUE=false
NO_AUTO_REGISTER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --keycloak-url)
            KEYCLOAK_BASE_URL="$2"
            shift 2
            ;;
        --realm)
            REALM_NAME="$2"
            shift 2
            ;;
        --trust-domain)
            TRUST_DOMAIN="$2"
            shift 2
            ;;
        --parent-id)
            PARENT_SPIFFE_ID="$2"
            shift 2
            ;;
        --spiffe-id)
            SPIFFE_ID="$2"
            shift 2
            ;;
        --client-name)
            CLIENT_NAME="$2"
            shift 2
            ;;
        --jwks-url)
            JWKS_URL="$2"
            shift 2
            ;;
        --jwt-ttl)
            JWT_SVID_TTL="$2"
            shift 2
            ;;
        --software-statement)
            CUSTOM_SOFTWARE_STATEMENT="$2"
            shift 2
            ;;
        --use-mock-jwt)
            USE_SPIRE_AGENT=false
            shift
            ;;
        --no-auto-register)
            NO_AUTO_REGISTER=true
            shift
            ;;
        --auto-continue)
            AUTO_CONTINUE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main script execution
main() {
    echo "=== SPIFFE DCR SPI Test Script ==="
    echo ""
    
    print_status "Configuration:"
    echo "  Keycloak URL: $KEYCLOAK_BASE_URL"
    echo "  Realm: $REALM_NAME"
    echo "  Trust Domain: $TRUST_DOMAIN"
    echo "  Parent SPIFFE ID: $PARENT_SPIFFE_ID"
    echo "  SPIFFE ID: $SPIFFE_ID"
    echo "  Client Name: $CLIENT_NAME"
    echo "  JWKS URL: $JWKS_URL"
    echo "  JWT TTL: $JWT_SVID_TTL seconds"
    echo "  Use SPIRE Agent: $USE_SPIRE_AGENT"
    echo "  Auto Register: $([ "$NO_AUTO_REGISTER" = true ] && echo "false" || echo "true")"
    echo ""
    
    # Run pre-flight checks
    print_status "Step 1: Running pre-flight checks"
    run_preflight_checks || exit 1
    print_success "Pre-flight checks completed successfully"
    prompt_continue
    echo ""
    
    # Check and register SPIRE workload entry (if using SPIRE and not disabled)
    if [ "$USE_SPIRE_AGENT" = true ] && [ "$NO_AUTO_REGISTER" != true ] && [ -z "$CUSTOM_SOFTWARE_STATEMENT" ]; then
        print_status "Step 2: SPIRE Environment & Workload Registration"
        check_spire_environment || exit 1
        check_and_register_workload || exit 1
        print_success "SPIRE workload registration completed"
        prompt_continue
        echo ""
    elif [ "$NO_AUTO_REGISTER" = true ]; then
        print_warning "Skipping automatic workload registration due to --no-auto-register flag."
        prompt_continue
        echo ""
    fi
    
    # Get or generate software statement
    local software_statement
    
    if [ -n "$CUSTOM_SOFTWARE_STATEMENT" ]; then
        print_status "Step 3: Using provided software statement"
        software_statement="$CUSTOM_SOFTWARE_STATEMENT"
        print_success "Using custom software statement provided"
        prompt_continue
    elif [ "$USE_SPIRE_AGENT" = true ]; then
        print_status "Step 3: Fetching JWT SVID from SPIRE agent"
        software_statement=$(get_spire_jwt_svid) || exit 1
        
        echo ""
        print_status "Decoded SPIRE JWT:"
        decode_jwt "$software_statement"
        
        prompt_continue
    else
        print_status "Step 3: Generating mock software statement"
        software_statement=$(generate_mock_jwt)
        print_warning "Using mock JWT - this will likely fail signature validation"
        print_warning "Use default behavior for real SPIRE SVID or --software-statement with valid JWT"
        prompt_continue
    fi
    
    echo ""
    
    # Validate JWT structure
    print_status "Step 4: Validating JWT structure"
    validate_jwt_structure "$software_statement" || exit 1
    print_success "JWT structure validation passed"
    prompt_continue
    echo ""
    
    # Make DCR request
    print_status "Step 5: Making Dynamic Client Registration request"
    make_dcr_request "$software_statement"
    local exit_code=$?
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        print_success "🎉 Test completed successfully!"
        print_status "The SPIFFE workload has been registered and DCR request succeeded."
    else
        print_error "❌ Test failed. Check the error messages above."
        print_status "Common issues:"
        echo "  - SPIRE containers not running"
        echo "  - Keycloak SPIFFE DCR SPI not configured"
        echo "  - Network connectivity issues"
        echo "  - JWT signature validation failures"
    fi
    
    exit $exit_code
}

# Run main function
main "$@" 