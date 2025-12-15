#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Running code quality checks..."

# Get list of staged Swift files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' || true)

if [ -z "$STAGED_FILES" ]; then
    echo "${GREEN}✓ No Swift files to check${NC}"
    exit 0
fi

ERRORS=0

echo ""
echo "Checking for prohibited patterns..."

# Check for force casts (as!)
echo -n "  Checking for force casts... "
FORCE_CASTS=$(echo "$STAGED_FILES" | xargs grep -n " as! " 2>/dev/null || true)
if [ -n "$FORCE_CASTS" ]; then
    echo "${RED}✗ Found force casts (as!)${NC}"
    echo "$FORCE_CASTS"
    echo ""
    echo "${YELLOW}Use conditional casting (as?) with proper error handling instead.${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo "${GREEN}✓${NC}"
fi

# Check for force unwraps (!) except for IBOutlets and implicitly unwrapped optionals in declarations
echo -n "  Checking for dangerous force unwraps... "
FORCE_UNWRAPS=$(echo "$STAGED_FILES" | xargs grep -n "[^!]![^=!]" 2>/dev/null | grep -v "@IBOutlet" | grep -v "// swiftlint:disable:next force_unwrapping" || true)
if [ -n "$FORCE_UNWRAPS" ]; then
    echo "${YELLOW}⚠ Found potential force unwraps${NC}"
    echo "$FORCE_UNWRAPS"
    echo ""
    echo "${YELLOW}Review these carefully. Use optional binding instead where possible.${NC}"
    # Don't fail for this - it's a warning
else
    echo "${GREEN}✓${NC}"
fi

# Check for @unchecked Sendable
echo -n "  Checking for @unchecked Sendable... "
UNCHECKED_SENDABLE=$(echo "$STAGED_FILES" | xargs grep -n "@unchecked Sendable" 2>/dev/null || true)
if [ -n "$UNCHECKED_SENDABLE" ]; then
    echo "${YELLOW}⚠ Found @unchecked Sendable${NC}"
    echo "$UNCHECKED_SENDABLE"
    echo ""
    echo "${YELLOW}Ensure this is documented and truly necessary. Consider using actors instead.${NC}"
    # Don't fail - just warn
else
    echo "${GREEN}✓${NC}"
fi

# Check for nonisolated(unsafe)
echo -n "  Checking for nonisolated(unsafe)... "
NONISOLATED_UNSAFE=$(echo "$STAGED_FILES" | xargs grep -n "nonisolated(unsafe)" 2>/dev/null || true)
if [ -n "$NONISOLATED_UNSAFE" ]; then
    echo "${YELLOW}⚠ Found nonisolated(unsafe)${NC}"
    echo "$NONISOLATED_UNSAFE"
    echo ""
    echo "${YELLOW}Ensure this is documented and truly necessary. Consider using thread-safe alternatives.${NC}"
    # Don't fail - just warn
else
    echo "${GREEN}✓${NC}"
fi

# Check for underscore-prefixed properties (anti-pattern in modern Swift)
echo -n "  Checking for underscore-prefixed properties... "
UNDERSCORE_PROPS=$(echo "$STAGED_FILES" | xargs grep -n "^[[:space:]]*var _[a-zA-Z]" 2>/dev/null || true)
if [ -n "$UNDERSCORE_PROPS" ]; then
    echo "${YELLOW}⚠ Found underscore-prefixed properties${NC}"
    echo "$UNDERSCORE_PROPS"
    echo ""
    echo "${YELLOW}Use standard Swift naming conventions. Consider lazy var or direct initialization.${NC}"
    # Don't fail - just warn
else
    echo "${GREEN}✓${NC}"
fi

echo ""

if [ $ERRORS -gt 0 ]; then
    echo "${RED}❌ Pre-commit checks failed with $ERRORS error(s)${NC}"
    echo ""
    echo "Fix the issues above or use 'git commit --no-verify' to skip checks (not recommended)."
    exit 1
fi

echo "${GREEN}✅ All code quality checks passed!${NC}"
exit 0
