#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Flutter Autopilot Setup${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}=> $1${NC}"
}

print_success() {
    echo -e "${GREEN}   $1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

check_prerequisites() {
    print_step "Checking prerequisites..."

    # Check Node.js
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js v16 or higher."
        exit 1
    fi

    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 16 ]; then
        print_error "Node.js v16+ required. Found: $(node -v)"
        exit 1
    fi
    print_success "Node.js $(node -v)"

    # Check npm
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed."
        exit 1
    fi
    print_success "npm $(npm -v)"
}

build_fap_client() {
    print_step "Building fap_client..."
    cd "$SCRIPT_DIR/fap_client"
    npm install --silent
    npm run build
    print_success "fap_client built successfully"
}

build_fap_mcp() {
    print_step "Building fap_mcp..."
    cd "$SCRIPT_DIR/fap_mcp"
    npm install --silent
    npm run build
    print_success "fap_mcp built successfully"
}

configure_claude() {
    MCP_PATH="$SCRIPT_DIR/fap_mcp/dist/index.js"

    echo ""
    print_step "Claude Code MCP Configuration"

    # Check if claude CLI exists
    if ! command -v claude &> /dev/null; then
        echo ""
        echo -e "   Claude CLI not found. To configure manually, run:"
        echo -e "   ${BLUE}claude mcp add flutter-agent -- node \"$MCP_PATH\"${NC}"
        return
    fi

    echo ""
    echo -n "   Configure Claude Code MCP server now? [Y/n] "
    read -r response

    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo ""
        echo "   Skipped. To configure later, run:"
        echo -e "   ${BLUE}claude mcp add flutter-agent -- node \"$MCP_PATH\"${NC}"
    else
        echo ""
        claude mcp add flutter-agent -- node "$MCP_PATH"
        print_success "Claude Code MCP configured"
    fi
}

print_summary() {
    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}  Setup Complete!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Add fap_agent to your Flutter app:"
    echo -e "   ${BLUE}dependencies:"
    echo "     fap_agent:"
    echo "       git:"
    echo -e "         url: https://github.com/mkritter3/flutter-autopilot.git"
    echo -e "         path: fap_agent${NC}"
    echo ""
    echo "2. Initialize in your app's main.dart:"
    echo -e "   ${BLUE}import 'package:fap_agent/fap_agent.dart';"
    echo ""
    echo "   void main() {"
    echo "     FapAgent.init(const FapConfig(port: 9001, enabled: true));"
    echo "     runApp(const MyApp());"
    echo -e "   }${NC}"
    echo ""
    echo "3. Run your Flutter app, then in Claude Code run:"
    echo -e "   ${BLUE}/fap-setup${NC}"
    echo ""
}

main() {
    print_header
    check_prerequisites
    build_fap_client
    build_fap_mcp
    configure_claude
    print_summary
}

main "$@"
