#!/bin/bash

# Roundtrip Translation Comparison Script
# This script compares roundtrip translations with the original English strings.xml

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 Roundtrip Translation Comparison Tool${NC}"
echo "================================================"

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 is required but not installed${NC}"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default paths
ORIGINAL_FILE="$PROJECT_ROOT/app/src/main/res/values/strings.xml"
ROUNDTRIP_DIR="$SCRIPT_DIR"

echo -e "${YELLOW}📁 Project root: $PROJECT_ROOT${NC}"
echo -e "${YELLOW}📄 Original file: $ORIGINAL_FILE${NC}"
echo -e "${YELLOW}📁 Roundtrip directory: $ROUNDTRIP_DIR${NC}"
echo

# Check if original file exists
if [ ! -f "$ORIGINAL_FILE" ]; then
    echo -e "${RED}❌ Original strings.xml not found at: $ORIGINAL_FILE${NC}"
    echo -e "${YELLOW}💡 Make sure you're running this from the project root${NC}"
    exit 1
fi

# Run the Python comparison script
echo -e "${GREEN}🚀 Running comparison...${NC}"
echo

# If no --modules flag is provided, default to per-module draft comparison
DEFAULT_FLAGS=()
case " $* " in
  *" --modules "*) : ;; # user provided modules
  *) DEFAULT_FLAGS+=(--modules app shared wear --use-draft) ;;
esac

python3 "$SCRIPT_DIR/compare_roundtrip.py" \
    --original "$ORIGINAL_FILE" \
    --roundtrip-dir "$ROUNDTRIP_DIR" \
    "${DEFAULT_FLAGS[@]}" \
    "$@"

# If HTML report was generated, offer to open it
if [[ "$*" == *"--html"* ]] && [ -f "$SCRIPT_DIR/roundtrip_report.html" ]; then
    echo
    echo -e "${BLUE}📖 HTML report generated successfully!${NC}"
    echo -e "${YELLOW}Would you like to open it in your browser? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        if command -v open &> /dev/null; then
            open "$SCRIPT_DIR/roundtrip_report.html"
        elif command -v xdg-open &> /dev/null; then
            xdg-open "$SCRIPT_DIR/roundtrip_report.html"
        else
            echo -e "${YELLOW}Please open the file manually: $SCRIPT_DIR/roundtrip_report.html${NC}"
        fi
    fi
fi

echo
echo -e "${BLUE}✨ Comparison complete!${NC}"
