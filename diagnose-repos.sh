#!/bin/bash

# Diagnostic script to see which repos have which emails

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Load .env file if exists
if [ -f ".env" ]; then
    echo -e "${GREEN}[INFO]${NC} Loading configuration from .env file..."
    export $(grep -v '^#' .env | xargs)
    echo ""
fi

# Show usage
show_usage() {
    echo "Usage: $0 [projects-folder] [filter-email] [since-date]"
    echo ""
    echo "You can either:"
    echo "  1. Use a .env file (recommended)"
    echo "  2. Pass parameters via command line"
    echo ""
    echo "Command line usage:"
    echo "  $0                                            # Use current directory"
    echo "  $0 ~/projects                                 # Specify projects folder"
    echo "  $0 ~/projects your.work@company.com           # With email filter"
    echo "  $0 ~/projects your.work@company.com 2024-01-01 # With date filter"
    echo ""
    echo "Using .env file:"
    echo "  Set these variables in your .env file:"
    echo "    PROJECTS_DIR=~/work-projects         # Optional"
    echo "    FILTER_EMAIL=your.work@company.com   # Optional"
    echo "    SINCE_DATE=2024-01-01                # Optional (YYYY-MM-DD)"
    echo ""
    echo "Then simply run: $0"
    echo ""
}

# Get parameters from command line or environment variables
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

if [ $# -gt 0 ]; then
    # Command line parameters override .env
    PROJECTS_DIR="${1:-.}"
    FILTER_EMAIL="${2:-${FILTER_EMAIL:-}}"
    SINCE_DATE="${3:-${SINCE_DATE:-}}"
else
    # Use environment variables from .env
    PROJECTS_DIR="${PROJECTS_DIR:-.}"
    FILTER_EMAIL="${FILTER_EMAIL:-}"
    SINCE_DATE="${SINCE_DATE:-}"
fi

# Convert to absolute path
PROJECTS_DIR="$(cd "$PROJECTS_DIR" 2>/dev/null && pwd)"

# Verify directory exists
if [ ! -d "$PROJECTS_DIR" ]; then
    echo -e "${RED}[ERROR]${NC} Directory $PROJECTS_DIR does not exist"
    exit 1
fi

echo -e "${GREEN}Repository diagnostics in: $PROJECTS_DIR${NC}"
if [ ! -z "$FILTER_EMAIL" ]; then
    echo -e "${GREEN}Filter Email: Only showing commits from $FILTER_EMAIL${NC}"
fi
if [ ! -z "$SINCE_DATE" ]; then
    echo -e "${GREEN}Since Date: Only showing commits from $SINCE_DATE onwards${NC}"
fi
echo ""

TOTAL_REPOS=0
REPOS_WITH_COMMITS=0
REPOS_WITH_FILTER=0

for DIR in "$PROJECTS_DIR"/*; do
    if [ -d "$DIR/.git" ]; then
        REPO_NAME=$(basename "$DIR")
        TOTAL_REPOS=$((TOTAL_REPOS + 1))
        
        cd "$DIR"
        
        # Build git log command with optional date filter
        GIT_LOG_BASE="git log --all"
        if [ ! -z "$SINCE_DATE" ]; then
            GIT_LOG_BASE="$GIT_LOG_BASE --since=\"$SINCE_DATE\""
        fi
        
        TOTAL_COMMITS=$(eval "$GIT_LOG_BASE --oneline" 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$TOTAL_COMMITS" -gt 0 ]; then
            REPOS_WITH_COMMITS=$((REPOS_WITH_COMMITS + 1))
            
            echo -e "${BLUE}📦 $REPO_NAME${NC}"
            echo "   Total commits: $TOTAL_COMMITS"
            
            # Show unique emails
            EMAILS=$(git log --all --format="%ae" 2>/dev/null | sort -u)
            echo "   Emails:"
            echo "$EMAILS" | while read -r email; do
                COUNT=$(eval "$GIT_LOG_BASE --author=\"$email\" --oneline" 2>/dev/null | wc -l | tr -d ' ')
                echo "     • $email ($COUNT commits)"
            done
            
            # If there's a filter, verify
            if [ ! -z "$FILTER_EMAIL" ]; then
                FILTER_COMMITS=$(eval "$GIT_LOG_BASE --author=\"$FILTER_EMAIL\" --oneline" 2>/dev/null | wc -l | tr -d ' ')
                if [ "$FILTER_COMMITS" -gt 0 ]; then
                    REPOS_WITH_FILTER=$((REPOS_WITH_FILTER + 1))
                    echo -e "   ${GREEN}✓ Has commits from $FILTER_EMAIL: $FILTER_COMMITS${NC}"
                else
                    echo -e "   ${YELLOW}✗ No commits from $FILTER_EMAIL${NC}"
                fi
            fi
            
            echo ""
        fi
    fi
done

echo "========================================="
echo "Summary:"
echo "  Total repositories: $TOTAL_REPOS"
echo "  With commits: $REPOS_WITH_COMMITS"
if [ ! -z "$FILTER_EMAIL" ]; then
    echo "  With commits from $FILTER_EMAIL: $REPOS_WITH_FILTER"
fi
echo "========================================="
