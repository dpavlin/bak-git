# Changes to bak-git

## 2026-03-02

### New Features
- `bak commit` now preserves the original file modification time (`mtime`) in the git commit date. This ensures the git history reflects when the file was actually changed on the client.

### New Commands
- Added `ls-files [host:]` command to list all tracked files in the git repository for a specific host (or the current host if not specified). Output is relative to the current directory when possible.

### Path Parsing Improvements
- Added logic to detect `/mnt/host/path` and automatically translate it to `host:/path`. This allows using `bak add` on files within `sshfs` mounts by correctly identifying the target host.
- Fixed `split` logic to handle multiple spaces in the input line, improving compatibility with various `nc` versions.
- Improved the `add` command loop regex to correctly extract multiple files from the message.
- Improved host parsing regex to allow an empty path after the colon (e.g., `bak ls-files host:`).
- Fixed handling of Git flags (e.g., `--stat`) in `diff`, `status`, and `log` commands. These are now correctly identified and passed to Git without triggering unnecessary `rsync` operations.

### Performance Optimizations
- Reduced `rsync` verbosity from `-avv` to `-av`. This significantly reduces the amount of data transferred and output processed, speeding up `add`, `commit`, and `diff` operations.
