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
echo "localhost" > whitelist.txt

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

# 12. Test diff --stat
echo "Test 12: diff --stat"
echo "another line" >> test_dir/file1.txt
bak diff --stat > "$TEST_DIR/diff_stat.out"
sleep 1
if ! grep -q "1 file changed" "$TEST_DIR/diff_stat.out"; then
    echo "FAIL: diff --stat output incorrect"
    cat "$TEST_DIR/diff_stat.out"
    exit 1
fi
# Check server log for rsync errors involving --stat
if grep -q "rsync.*--stat" "$TEST_DIR/server.log"; then
    echo "FAIL: server tried to rsync --stat"
    grep "rsync.*--stat" "$TEST_DIR/server.log"
    exit 1
fi
echo "PASS: diff --stat"

# 13. Test diff without arguments (current directory)
echo "Test 13: diff without arguments"
# We have changes in test_dir/file1.txt from Test 12.
# Let's add a change in a different directory.
echo "top level change" >> top_level.txt
bak add top_level.txt
echo "another top level change" >> top_level.txt

cd test_dir
bak diff > "$TEST_DIR/diff_no_args.out"
if grep -q "top_level.txt" "$TEST_DIR/diff_no_args.out"; then
    echo "FAIL: diff without args showed changes outside current directory"
    cat "$TEST_DIR/diff_no_args.out"
    exit 1
fi
if ! grep -q "another line" "$TEST_DIR/diff_no_args.out"; then
    echo "FAIL: diff without args missed changes in current directory"
    cat "$TEST_DIR/diff_no_args.out"
    exit 1
fi
cd ..
echo "PASS: diff without arguments"

# 14. Test diff --stat /
echo "Test 14: diff --stat /"
# Run from subdir but target root
cd test_dir
bak diff --stat / > "$TEST_DIR/diff_stat_root.out"
if ! grep -q "top_level.txt" "$TEST_DIR/diff_stat_root.out"; then
    echo "FAIL: diff --stat / missed top-level changes"
    cat "$TEST_DIR/server.log"
    cat "$TEST_DIR/diff_stat_root.out"
    exit 1
fi
cd ..
echo "PASS: diff --stat /"

# 15. Test Absolute Paths
echo "Test 15: absolute paths"
ABS_FILE="$CLIENT_DIR/abs_file.txt"
echo "absolute content" > "$ABS_FILE"

# add with absolute path
bak add "$ABS_FILE"
cd "$BACKUP_DIR"
ABS_BACKUP_PATH=$(echo "$HOST$ABS_FILE" | sed 's,//,/,g')
if ! git ls-files | grep -q "$ABS_BACKUP_PATH"; then
    echo "FAIL: absolute file not added"
    exit 1
fi
cd "$CLIENT_DIR"

# commit with absolute path
bak commit "$ABS_FILE" "Commit absolute"
cd "$BACKUP_DIR"
ABS_BACKUP_PATH=$(echo "$HOST$ABS_FILE" | sed 's,//,/,g')
if ! git log -1 --format="%s" "$ABS_BACKUP_PATH" | grep -q "Commit absolute"; then
    echo "FAIL: absolute file not committed"
    exit 1
fi
cd "$CLIENT_DIR"

# cat with absolute path
CAT_ABS=$(bak cat "$ABS_FILE")
if [[ "$CAT_ABS" != "absolute content" ]]; then
    echo "FAIL: cat absolute incorrect. Got: [$CAT_ABS]"
    exit 1
fi

# ls with absolute path
LS_ABS=$(bak ls "$ABS_FILE")
if [[ "$LS_ABS" != *"$ABS_FILE"* ]]; then
    echo "FAIL: ls absolute incorrect. Got: [$LS_ABS]"
    exit 1
fi

# diff with absolute path
echo "change" >> "$ABS_FILE"
DIFF_ABS=$(bak diff "$ABS_FILE")
if ! echo "$DIFF_ABS" | grep -q "change"; then
    echo "FAIL: diff absolute incorrect"
    exit 1
fi

echo "PASS: absolute paths"

# 16. Test host:/path syntax
echo "Test 16: host:/path syntax"
OTHER_HOST="other_host"
mkdir -p "$BACKUP_DIR/$OTHER_HOST"
cd "$BACKUP_DIR"
# Add a file directly to the other host in the backup repo
mkdir -p "$OTHER_HOST$CLIENT_DIR"
echo "other host content" > "$OTHER_HOST$CLIENT_DIR/other_file.txt"
git add "$OTHER_HOST$CLIENT_DIR/other_file.txt"
git commit -m "Add file to other host" > /dev/null
cd "$CLIENT_DIR"

# Test cat host:/path
CAT_OTHER=$(bak cat "$OTHER_HOST:$CLIENT_DIR/other_file.txt")
if [[ "$CAT_OTHER" != "other host content" ]]; then
    echo "FAIL: cat host:/path incorrect. Got: [$CAT_OTHER]"
    exit 1
fi

# Test ls host:/path
LS_OTHER=$(bak ls "$OTHER_HOST:$CLIENT_DIR/other_file.txt")
if [[ "$LS_OTHER" != *"/other_file.txt"* ]]; then
    echo "FAIL: ls host:/path incorrect. Got: [$LS_OTHER]"
    exit 1
fi

# Test ls-files host:
LS_FILES_OTHER=$(bak ls-files "$OTHER_HOST:")
# tr -d '\r' to handle possible network line endings
LS_FILES_OTHER=$(echo "$LS_FILES_OTHER" | tr -d '\r')
if ! echo "$LS_FILES_OTHER" | grep -q "other_file.txt"; then
    echo "FAIL: ls-files host: incorrect. Got: [$LS_FILES_OTHER]"
    exit 1
fi

# Test diff host:/path (compares localhost file with other_host file)
# We need to use the same path on both hosts for side-by-side diff
# So we add the file at the same location on localhost
mkdir -p "$(dirname "$CLIENT_DIR/other_file.txt")"
echo "local content" > "$CLIENT_DIR/other_file.txt"
bak add "$CLIENT_DIR/other_file.txt"
bak commit "$CLIENT_DIR/other_file.txt" "Add local file at same path"

DIFF_HOST=$(bak diff "$OTHER_HOST:$CLIENT_DIR/other_file.txt")
if ! echo "$DIFF_HOST" | grep -q "+other host content"; then
    echo "FAIL: diff host:/path incorrect"
    echo "DEBUG: DIFF_HOST:"
    echo "$DIFF_HOST"
    exit 1
fi

# Test revert host:/path (restores file from other_host to localhost)
bak revert "$OTHER_HOST:$CLIENT_DIR/other_file.txt"
if [[ "$(cat "$CLIENT_DIR/other_file.txt")" != "other host content" ]]; then
    echo "FAIL: revert host:/path failed"
    exit 1
fi

echo "PASS: host:/path syntax"

# 17. Test whitelist enforcement
echo "Test 17: whitelist enforcement"
# 'localhost' is in whitelist.txt. Let's try 'denied_host'
# We use raw nc because bak() wrapper uses $HOST (localhost)
DENIED_OUT=$(echo "dpavlin/ denied_host $(pwd) ls" | nc -w 5 127.0.0.1 $PORT | tr -d '\r')
if [[ "$DENIED_OUT" != "hostname denied_host not in whitelist" ]]; then
    echo "FAIL: whitelist enforcement failed. Got: [$DENIED_OUT]"
    exit 1
fi
echo "PASS: whitelist enforcement"

echo "All tests passed successfully!"
