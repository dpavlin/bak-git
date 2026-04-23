#!/bin/bash
set -e

# Make sure working directory is clean
if [ -n "$(git status --porcelain)" ]; then
    echo "Working directory is not clean. Please commit or stash your changes first."
    exit 1
fi

CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != "master" ]; then
    echo "This script must be run from the master branch."
    exit 1
fi

LATEST_MSG=$(git log -1 --pretty=%B)

# Check if main branch exists, if not create it as an orphan
if ! git show-ref --verify --quiet refs/heads/main; then
    git checkout --orphan main
    git rm -rf .
else
    git checkout main
    # Clean the working tree so we can sync perfectly with master
    git rm -rf . >/dev/null 2>&1 || true
fi

# Bring all files from master into the main branch working tree
git checkout master -- .

# Exclude the sanitization script itself from the public branch
if [ -f update-main.sh ]; then
    git reset HEAD update-main.sh >/dev/null 2>&1 || true
    rm update-main.sh
fi

# Exclude any temporary or untracked files that might have slipped in
if [ -f whitelist.txt ]; then
    git reset HEAD whitelist.txt >/dev/null 2>&1 || true
    rm whitelist.txt
fi
if [ -f final_host_ips.txt ]; then
    git reset HEAD final_host_ips.txt >/dev/null 2>&1 || true
    rm final_host_ips.txt
fi

# Sanitize files
FILES=$(git ls-files | grep -v 'update-main.sh' | grep -v 'whitelist.txt' | grep -v 'final_host_ips.txt')

for f in $FILES; do
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
done

# Handle file renames (klin.sh -> server-a.sh)
if [ -f "klin.sh" ]; then
    mv klin.sh server-a.sh
    git rm -f klin.sh
    git add server-a.sh
fi

git add .
git commit -m "Sanitized release: $LATEST_MSG"

echo "====================================="
echo "Sanitized 'main' branch updated successfully."
echo "You can now safely push the 'main' branch to your public repository."
echo "Switching back to 'master'..."
git checkout master
echo "Back on master."
