#!/bin/bash
set -e

# Make sure working directory is clean
if [ -n "$(git status --porcelain)" ]; then
    echo "Working directory is not clean. Please commit or stash your changes first."
    exit 1
fi

# Ensure we are on master branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "master" ]; then
    echo "This script must be run from the master branch."
    exit 1
fi

# Find new commits on master since last publish
NEW_COMMITS=$(git log --reverse --format="%H" published-to-main..HEAD)

if [ -z "$NEW_COMMITS" ]; then
    echo "No new commits to publish to main."
    exit 0
fi

# Switch to main branch
git checkout main

# Process each new commit
for commit in $NEW_COMMITS; do
    echo "Publishing commit: $commit"
    
    # Cherry-pick the commit
    # We use -Xtheirs or just standard cherry pick. If conflicts, we'll abort.
    if ! git cherry-pick "$commit"; then
        echo "Merge conflict during cherry-pick of $commit. Please resolve manually, commit, and update the 'published-to-main' tag on master."
        exit 1
    fi
    
    # Scrub the files that were changed in this commit
    FILES=$(git diff-tree --no-commit-id --name-only -r HEAD | grep -v 'whitelist.txt' || true)
    
    if [ -n "$FILES" ]; then
        for f in $FILES; do
            if [ -f "$f" ]; then
                # IP Addresses
                sed -i 's/10\.60\.0\.92/192.168.1.1/g' "$f"
                sed -i 's/10\.200\.100\.92/192.168.2.1/g' "$f"
                sed -i 's/10\.200\.100\.40/192.168.2.40/g' "$f"
                sed -i 's/10\.13\.37\.[0-9]\+/192.168.3.x/g' "$f"
                sed -i 's/10\.13\.37\.x/192.168.3.x/g' "$f"
                sed -i 's/192\.168\.42\.42/192.168.10.10/g' "$f"
                
                # Emails and Users
                sed -i 's/dpavlin@rot13\.org/admin@example.com/g' "$f"
                sed -i 's/dpavlin/user/g' "$f"
                
                # Hostnames & Domains
                sed -i 's/klin/server-a/g' "$f"
                sed -i 's/nuc/client-a/g' "$f"
                sed -i 's/mjesec/gateway/g' "$f"
                sed -i 's/webgui/web-admin/g' "$f"
                sed -i 's/saturn\.ffzg\.hr/public.example.com/g' "$f"
                sed -i 's/ffzg\.hr/example.com/g' "$f"
                
                # Project Names
                sed -i 's/MAXXO/PROJECT_X/g' "$f"
                sed -i 's/calyx/p2p_net/g' "$f"
            fi
        done
        
        # Add the scrubbed files
        git add -u
        
        # Amend the commit if changes were made
        if ! git diff-index --quiet HEAD; then
            git commit --amend --no-edit
        fi
    fi
done

# Switch back to master
git checkout master

# Update the sync marker tag
git tag -f -a "published-to-main" -m "Marker for commits already synchronized and scrubbed to main" HEAD

echo "====================================="
echo "Successfully published new commits to the 'main' branch."
echo "You can now safely push the 'main' branch to your public repository:"
echo "  git push github main"
echo "  git push github --tags"
echo "====================================="
