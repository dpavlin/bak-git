#!/bin/bash

set -e

echo "Setting up test environment..."
TEST_DIR=$(mktemp -d)
BACKUP_DIR="$TEST_DIR/backup"
CLIENT_DIR="$TEST_DIR/client"
PORT=9002
HOST="localhost"

mkdir -p "$BACKUP_DIR"
mkdir -p "$CLIENT_DIR"

cd "$BACKUP_DIR"
git init > /dev/null

# Patch server to use test port and allow 127.0.0.1
SERVER_SCRIPT="$TEST_DIR/bak-git-server-test.pl"
sed "s/9001/$PORT/g" /home/dpavlin/bak-git/bak-git-server.pl > "$SERVER_SCRIPT"
sed -i 's/10\\\.200\\\.100\\\./127\\\.0\\\.0\\\.1|10\\\.200\\\.100\\\./' "$SERVER_SCRIPT"
chmod +x "$SERVER_SCRIPT"

# Start server
"$SERVER_SCRIPT" "$BACKUP_DIR" 127.0.0.1 > "$TEST_DIR/server.log" 2>&1 &
SERVER_PID=$!

# Ensure server is killed on exit
cleanup() {
    echo "Cleaning up..."
    kill -TERM $SERVER_PID 2>/dev/null || true
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Wait for server to start
sleep 2

# Check if server is listening
if ! ss -tpln | grep -q $PORT; then
    echo "FAIL: Server failed to start on port $PORT"
    cat "$TEST_DIR/server.log"
    exit 1
fi

# Define bak wrapper
bak() {
    # Match original client exactly: echo "$USER/$SUDO_USER `hostname -s` `pwd` $*"
    echo "dpavlin/ $HOST $(pwd) $*" | nc -w 5 127.0.0.1 $PORT
}

# --- TESTS ---

echo "Running tests..."

cd "$CLIENT_DIR"
mkdir -p test_dir

# 1. Test add
echo "Test 1: add"
echo "hello world" > test_dir/file1.txt
bak add test_dir/file1.txt
sleep 1

# Verify it's staged in the backup dir
cd "$BACKUP_DIR"
if ! git ls-files | grep -q "$HOST.*test_dir/file1.txt"; then
    echo "FAIL: file1.txt not added to git"
    exit 1
fi
cd "$CLIENT_DIR"
echo "PASS: add"

# 2. Test commit with timestamp
echo "Test 2: commit with timestamp"
touch -d '2025-05-05 15:30:00' test_dir/file1.txt
bak commit test_dir/file1.txt "Test commit file1"
sleep 1

# Verify commit timestamp
cd "$BACKUP_DIR"
COMMIT_DATE=$(git log -1 --format="%ai" "$HOST$CLIENT_DIR/test_dir/file1.txt")
if [[ "$COMMIT_DATE" != *"2025-05-05 15:30:00"* ]]; then
    echo "FAIL: commit timestamp not preserved: $COMMIT_DATE"
    cat "$TEST_DIR/server.log"
    exit 1
fi
cd "$CLIENT_DIR"
echo "PASS: commit with timestamp"

# 3. Test ls-files relative
echo "Test 3: ls-files relative"
cd "$CLIENT_DIR/test_dir"
LS_OUT=$(bak ls-files | tr -d '\r')
if [[ "$LS_OUT" != "file1.txt" ]]; then
    echo "FAIL: ls-files relative output incorrect. Got: [$LS_OUT]"
    exit 1
fi
echo "PASS: ls-files relative"

# 4. Test ls-files absolute / with host
echo "Test 4: ls-files absolute"
LS_OUT2=$(bak ls-files $HOST: | tr -d '\r')
if [[ "$LS_OUT2" != "file1.txt" ]]; then
    echo "FAIL: ls-files with host output incorrect. Got: [$LS_OUT2]"
    exit 1
fi
cd "$CLIENT_DIR"
echo "PASS: ls-files absolute"

# 5. Test /mnt/host translation
echo "Test 5: /mnt/host translation"
# Fake the path being added
FAKE_MNT_PATH="/mnt/$HOST$CLIENT_DIR/test_dir/file2.txt"
echo "file 2" > test_dir/file2.txt
bak add "$FAKE_MNT_PATH"
sleep 1
cd "$BACKUP_DIR"
if ! git ls-files | grep -q "$HOST.*test_dir/file2.txt"; then
    echo "FAIL: /mnt/host file2.txt not added"
    exit 1
fi
cd "$CLIENT_DIR"
bak commit "$FAKE_MNT_PATH" "Commit file2"
sleep 1
echo "PASS: /mnt/host translation"

# 6. Test multiple spaces and tabs (backward compatibility)
echo "Test 6: command parsing with multiple spaces"
echo -e "dpavlin/	$HOST	$(pwd)   add   test_dir/file1.txt" | nc -w 5 127.0.0.1 $PORT
sleep 1
echo "PASS: multiple spaces"

# 7. Test cat
echo "Test 7: cat"
CAT_OUT=$(bak cat test_dir/file1.txt)
if [[ "$CAT_OUT" != "hello world" ]]; then
    echo "FAIL: cat output incorrect. Got: [$CAT_OUT]"
    exit 1
fi
echo "PASS: cat"

# 8. Test ls
echo "Test 8: ls"
LS_OUT3=$(bak ls test_dir/file1.txt)
if [[ "$LS_OUT3" != *"test_dir/file1.txt"* ]]; then
    echo "FAIL: ls output incorrect. Got: [$LS_OUT3]"
    exit 1
fi
echo "PASS: ls"

# 9. Test grep
echo "Test 9: grep"
# Note: bak grep runs `git grep` on the server which searches in tracked files.
# It expects the search term.
GREP_OUT=$(bak grep "hello")
if [[ "$GREP_OUT" != *"hello"* ]]; then
    echo "FAIL: grep output incorrect. Got: [$GREP_OUT]"
    exit 1
fi
echo "PASS: grep"

# 10. Test diff
echo "Test 10: diff"
echo "diff text" >> test_dir/file1.txt
bak diff test_dir/file1.txt > "$TEST_DIR/diff.out" || true
# wait for rsync to complete
sleep 1
if ! grep -q "diff text" "$TEST_DIR/diff.out"; then
    echo "FAIL: diff output incorrect or missing"
    cat "$TEST_DIR/diff.out"
    exit 1
fi
echo "PASS: diff"

# 11. Test revert
echo "Test 11: revert"
bak revert test_dir/file1.txt
sleep 1
if [[ "$(cat test_dir/file1.txt)" != "hello world" ]]; then
    echo "FAIL: revert failed to restore file"
    exit 1
fi
echo "PASS: revert"

echo "All tests passed successfully!"
