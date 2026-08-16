#!/bin/bash

# Open HTML Report Script
# This script opens the generated HTML report in the default browser

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📖 Opening Roundtrip Translation Report${NC}"
echo "=============================================="

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE="$SCRIPT_DIR/roundtrip_report.html"

# Check if report exists
if [ ! -f "$REPORT_FILE" ]; then
    echo -e "${RED}❌ HTML report not found: $REPORT_FILE${NC}"
    echo -e "${YELLOW}💡 Generate the report first with: ./compare.sh --html${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found report: $REPORT_FILE${NC}"

# Try to open the report
if command -v open &> /dev/null; then
    echo -e "${BLUE}🚀 Opening in default browser...${NC}"
    open "$REPORT_FILE"
elif command -v xdg-open &> /dev/null; then
    echo -e "${BLUE}🚀 Opening in default browser...${NC}"
    xdg-open "$REPORT_FILE"
elif command -v start &> /dev/null; then
    echo -e "${BLUE}🚀 Opening in default browser...${NC}"
    start "$REPORT_FILE"
else
    echo -e "${YELLOW}⚠️  Could not automatically open the report.${NC}"
    echo -e "${YELLOW}Please open manually: $REPORT_FILE${NC}"
    echo
    echo -e "${BLUE}You can also:${NC}"
    echo -e "  • Double-click the file in your file manager"
    echo -e "  • Drag and drop it into your browser"
    echo -e "  • Copy the path and paste it in your browser's address bar"
fi

echo
echo -e "${GREEN}✨ Done!${NC}"
