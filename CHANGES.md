# Changes to bak-git

## 2026-04-24

### Security & Access Control
- **Hostname Whitelist Enforcement**: The server now strictly allows connections only from hostnames listed in `whitelist.txt`.
- **IP Verification**: Added support for optional IP mapping in the whitelist (e.g., `hostname IP1,IP2`). Connections are denied if a known host connects from an unauthorized IP.
- **Automated Alerts**: Denied connection attempts now trigger an immediate email alert to the administrator, including enrollment instructions.
- **Privacy Scrubbing**: Implemented an automated procedure to synchronize the private `master` branch to a public `main` branch, scrubbing internal IPs, hostnames, and project names from the Git history.
- **Push Protection**: Added a Git `pre-push` hook that physically blocks accidental pushes of the private `master` branch to GitHub and scans outgoing commits for leaked sensitive data.

### New Features & Improvements
- **Timestamp Preservation**: `bak commit` now preserves the original file modification time (`mtime`) in the Git commit date, ensuring history reflects actual edit times.
- **Relative ls-files**: Added `ls-files` command that provides output relative to the user's current working directory, mirroring standard Git behavior.
- **Absolute Path Support**: Improved `cat`, `ls`, and `diff` to handle absolute paths correctly by normalizing double slashes.
- **Advanced Argument Parsing**:
    - Fixed `split` logic to handle multiple spaces and multi-word commit messages.
    - Improved regex to allow single-character paths (like `/`) following Git flags.
    - Fixed Git flag handling (e.g., `--stat`) to prevent unnecessary `rsync` operations.
- **Path Translation**: Added logic to detect `/mnt/host/path` and automatically translate it to `host:/path` for seamless backups from FUSE mounts.

### Performance Optimizations
- **WireGuard Integration**: Optimized default routes to use WireGuard IPs, nearly doubling throughput over DSL (~14 Mbps).
- **SSH Latency Reduction**: Configured direct routes for local IPs in `.ssh/config`, reducing SSH handshake overhead by 10x.
- **Rsync Verbosity**: Reduced `rsync` verbosity from `-avv` to `-av` to minimize network overhead.

### Reliability
- **Comprehensive Test Suite**: Created a robust `test.sh` runner with 18 automated test cases covering basic commands, security enforcement, and complex edge cases in an isolated environment.

## 2026-03-02

### Path Parsing Improvements
- Added logic to detect `/mnt/host/path` and automatically translate it to `host:/path`. This allows using `bak add` on files within `sshfs` mounts by correctly identifying the target host.
- Fixed `split` logic to handle multiple spaces in the input line, improving compatibility with various `nc` versions.
- Improved the `add` command loop regex to correctly extract multiple files from the message.
- Improved host parsing regex to allow an empty path after the colon (e.g., `bak ls-files host:`).
- Fixed handling of Git flags (e.g., `--stat`) in `diff`, `status`, and `log` commands. These are now correctly identified and passed to Git without triggering unnecessary `rsync` operations.

### Performance Optimizations
- Reduced `rsync` verbosity from `-avv` to `-av`. This significantly reduces the amount of data transferred and output processed, speeding up `add`, `commit`, and `diff` operations.
