#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[REPO]${NC} $1"; }

# Load .env file if exists
if [ -f ".env" ]; then
    log "Loading configuration from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "You can either:"
    echo "  1. Use a .env file (recommended)"
    echo "  2. Pass parameters via command line"
    echo ""
    echo "Command line usage:"
    echo "  $0 <github-repo> <github-token> <your-name> <your-email> [projects-folder] [filter-email] [since-date]"
    echo ""
    echo "Example:"
    echo "  $0 username/work-contributions ghp_xxxxx \"Your Name\" your.personal@gmail.com"
    echo "  $0 username/work-contributions ghp_xxxxx \"Your Name\" your.personal@gmail.com ~/projects"
    echo "  $0 username/work-contributions ghp_xxxxx \"Your Name\" your.personal@gmail.com ~/projects email@work.com 2024-01-01"
    echo ""
    echo "Using .env file:"
    echo "  Create a .env file with the following variables:"
    echo "    GITHUB_REPO=username/work-contributions"
    echo "    GITHUB_TOKEN=ghp_xxxxx"
    echo "    AUTHOR_NAME=\"Your Name\""
    echo "    AUTHOR_EMAIL=your.personal@gmail.com"
    echo "    PROJECTS_DIR=~/work-projects              # Optional"
    echo "    FILTER_EMAIL=your.work@company.com        # Optional"
    echo "    SINCE_DATE=2024-01-01                     # Optional (YYYY-MM-DD)"
    echo ""
    echo "Then simply run: $0"
    echo ""
    exit 1
}

# Get parameters from command line or environment variables
if [ $# -gt 0 ]; then
    # Command line parameters override .env
    GITHUB_REPO="$1"
    GITHUB_TOKEN="$2"
    AUTHOR_NAME="$3"
    AUTHOR_EMAIL="$4"
    PROJECTS_DIR="${5:-${PROJECTS_DIR:-.}}"
    FILTER_EMAIL="${6:-${FILTER_EMAIL:-}}"
    SINCE_DATE="${7:-${SINCE_DATE:-}}"
else
    # Use environment variables from .env
    GITHUB_REPO="${GITHUB_REPO:-}"
    GITHUB_TOKEN="${GITHUB_TOKEN:-}"
    AUTHOR_NAME="${AUTHOR_NAME:-}"
    AUTHOR_EMAIL="${AUTHOR_EMAIL:-}"
    PROJECTS_DIR="${PROJECTS_DIR:-.}"
    FILTER_EMAIL="${FILTER_EMAIL:-}"
    SINCE_DATE="${SINCE_DATE:-}"
fi

# Validate required parameters
if [ -z "$GITHUB_REPO" ] || [ -z "$GITHUB_TOKEN" ] || [ -z "$AUTHOR_NAME" ] || [ -z "$AUTHOR_EMAIL" ]; then
    show_usage
fi

# Convert to absolute path
PROJECTS_DIR="$(cd "$PROJECTS_DIR" && pwd)"

# Verify directory exists
[ ! -d "$PROJECTS_DIR" ] && error "Directory $PROJECTS_DIR does not exist"

# Validate author parameters
[ -z "$AUTHOR_NAME" ] && error "Author name cannot be empty"
[ -z "$AUTHOR_EMAIL" ] && error "Author email cannot be empty"

log "Detected configuration:"
log "  Name: $AUTHOR_NAME"
log "  Email: $AUTHOR_EMAIL"
log "  Folder: $PROJECTS_DIR"
if [ ! -z "$FILTER_EMAIL" ]; then
    log "  Filter Email: Only commits from $FILTER_EMAIL"
fi
if [ ! -z "$SINCE_DATE" ]; then
    log "  Since Date: Only commits from $SINCE_DATE onwards"
fi
warn "⚠️  Make sure $AUTHOR_EMAIL is verified on GitHub!"
echo ""

GITHUB_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git"

# Create temporary directory
TEMP_DIR="/tmp/multi-mirror-$(date +%s)"
mkdir -p "$TEMP_DIR"

log "Searching for repositories in $PROJECTS_DIR..."
REPO_COUNT=0
TOTAL_COMMITS=0

# File to accumulate all commits
COMMITS_FILE="$TEMP_DIR/all_commits.txt"
REPOS_FILE="$TEMP_DIR/repos_info.txt"
touch "$COMMITS_FILE"
touch "$REPOS_FILE"

# Iterate through all folders
for DIR in "$PROJECTS_DIR"/*; do
    if [ -d "$DIR/.git" ]; then
        REPO_NAME=$(basename "$DIR")
        REPO_COUNT=$((REPO_COUNT + 1))
        
        info "Processing: $REPO_NAME"
        
        cd "$DIR"
        
        # Get repository information
        BRANCH_COUNT=$(git branch -a 2>/dev/null | wc -l)
        
        # Build git log command with optional filters
        GIT_LOG_CMD="git log --all"
        
        # Add date filter if specified
        if [ ! -z "$SINCE_DATE" ]; then
            GIT_LOG_CMD="$GIT_LOG_CMD --since=\"$SINCE_DATE\""
        fi
        
        # Extract commits
        if [ ! -z "$FILTER_EMAIL" ]; then
            COMMITS=$(eval "$GIT_LOG_CMD --author=\"$FILTER_EMAIL\" --format=\"%aI|%s|$REPO_NAME\"" 2>/dev/null || echo "")
            # Check emails in the repo
            REPO_EMAILS=$(git log --all --format="%ae" 2>/dev/null | sort -u)
        else
            COMMITS=$(eval "$GIT_LOG_CMD --format=\"%aI|%s|$REPO_NAME\"" 2>/dev/null || echo "")
        fi
        
        if [ ! -z "$COMMITS" ]; then
            REPO_COMMITS=$(echo "$COMMITS" | wc -l)
            TOTAL_COMMITS=$((TOTAL_COMMITS + REPO_COMMITS))
            echo "$COMMITS" >> "$COMMITS_FILE"
            echo "$REPO_NAME: $REPO_COMMITS commits" >> "$REPOS_FILE"
            log "  ✓ $REPO_COMMITS commits found"
        else
            warn "  ⚠ No commits found"
            if [ ! -z "$FILTER_EMAIL" ] && [ ! -z "$REPO_EMAILS" ]; then
                warn "     Emails in this repo: $(echo "$REPO_EMAILS" | tr '\n' ', ' | sed 's/,$//')"
            fi
        fi
    fi
done

echo ""
log "========================================="
log "Summary:"
log "  Repositories found: $REPO_COUNT"
log "  Total commits: $TOTAL_COMMITS"
log "========================================="
echo ""

if [ $TOTAL_COMMITS -eq 0 ]; then
    error "No commits found. Check the email or repositories."
fi

# Sort commits by date
sort "$COMMITS_FILE" -o "$COMMITS_FILE"

# Create mirror repository
log "Creating mirror repository..."
cd "$TEMP_DIR"
mkdir mirror
cd mirror

git init
git config user.name "$AUTHOR_NAME"
git config user.email "$AUTHOR_EMAIL"

# Create README with statistics
cat > README.md << EOF
# 📊 Work Contributions Mirror

This repository mirrors my development activity on work projects.

## 📈 Statistics

- **Total commits**: $TOTAL_COMMITS
- **Repositories**: $REPO_COUNT
- **Period**: $(head -1 "$COMMITS_FILE" | cut -d'|' -f1 | cut -d'T' -f1) → $(tail -1 "$COMMITS_FILE" | cut -d'|' -f1 | cut -d'T' -f1)

## 📦 Included projects

\`\`\`
$(cat "$REPOS_FILE")
\`\`\`

---

*This is a mirror repository to keep my work contribution history visible.*

**Note**: The commits here are temporal markers that reflect real activity in private work repositories.
EOF

git add README.md
git commit -m "📊 Initial commit - Work contributions mirror"

# Create mirror commits
log "Creating mirror commits (this may take a moment)..."
COUNTER=0
CURRENT_DATE=""

while IFS='|' read -r DATE MESSAGE REPO; do
    COUNTER=$((COUNTER + 1))
    
    # Show progress every 100 commits
    if [ $((COUNTER % 100)) -eq 0 ]; then
        PERCENT=$((COUNTER * 100 / TOTAL_COMMITS))
        log "Progress: $COUNTER/$TOTAL_COMMITS ($PERCENT%)"
    fi
    
    # Use short date to group commits from the same day
    SHORT_DATE=$(echo "$DATE" | cut -d'T' -f1)
    
    # Create commit with original date and specified author
    GIT_AUTHOR_NAME="$AUTHOR_NAME" \
    GIT_AUTHOR_EMAIL="$AUTHOR_EMAIL" \
    GIT_COMMITTER_NAME="$AUTHOR_NAME" \
    GIT_COMMITTER_EMAIL="$AUTHOR_EMAIL" \
    GIT_AUTHOR_DATE="$DATE" \
    GIT_COMMITTER_DATE="$DATE" \
    git commit --allow-empty -m "🔄 [$REPO] Activity" --quiet
    
done < "$COMMITS_FILE"

log "✅ Created $COUNTER mirror commits"
echo ""

# Push to GitHub
log "Uploading to GitHub..."
git remote add origin "$GITHUB_URL"
git branch -M main

# Push with retry
MAX_RETRIES=3
RETRY=0
until git push -u origin main --force || [ $RETRY -eq $MAX_RETRIES ]; do
    RETRY=$((RETRY + 1))
    warn "Retrying push... ($RETRY/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY -eq $MAX_RETRIES ]; then
    error "Could not push after $MAX_RETRIES attempts"
fi

echo ""
log "========================================="
log "✅ Process completed successfully!"
log "========================================="
log ""
log "📊 Final summary:"
log "  • Repositories processed: $REPO_COUNT"
log "  • Total commits: $TOTAL_COMMITS"
log "  • GitHub repository: https://github.com/${GITHUB_REPO}"
log ""
warn "⏰ Contributions may take up to 24 hours to appear"
log ""
log "🔍 To verify:"
log "  1. Go to: https://github.com/$GITHUB_REPO"
log "  2. Check that the README shows the correct statistics"
log "  3. Check your profile in 24 hours: https://github.com/$(echo $GITHUB_REPO | cut -d'/' -f1)"
echo ""

# Cleanup
cd /
rm -rf "$TEMP_DIR"

log "✨ Done!"
