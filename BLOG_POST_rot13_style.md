If you are using bak-git for a long time this will sound familiar: your DSL connection is slow making backups painful, and you know you should restrict access but adding full-blown configuration management is too much work. To add insult to injury, parsing command outputs with unexpected formats sometimes breaks your scripts.

So, what would an updated, fast, and secure tool for keeping remote files in central git repository look like?
*   fast rsync transfers over modern VPNs like WireGuard
*   strict whitelisting to prevent unauthorized access
*   preserve original file timestamps in git commits
*   test suite to ensure no regressions

I spent some time optimizing bak-git to solve these problems. All this should be simpler...
Like this:
1. Speed up the connection over slow DSL:
Switching the primary route to `klin` over WireGuard (`10.200.100.92`) and reducing rsync verbosity to `-av` nearly doubled throughput to ~14 Mbps. I also bypassed the slow proxy for local connections in `.ssh/config`, dropping SSH latency from 0.5s down to 0.05s.

2. Enforce strict security for clients:
The server now loads a `whitelist.txt` on startup. If an unknown host connects, it's rejected:
dpavlin@denied_host:~$ bak ls
DENIED: hostname denied_host not in whitelist

To make it really secure, the whitelist supports IP mapping (`hostname 10.200.100.40`). Any denial sends an immediate email alert to the admin with a ready-to-copy snippet on how to enroll it.

3. Preserve timestamps and view files intuitively:
dpavlin@nuc:~$ touch -d '2025-05-05 15:30:00' file1.txt
dpavlin@nuc:~$ bak commit file1.txt "update file"
Now `bak commit` extracts the original `mtime` on the server after sync and passes it as `--date` to git, keeping history completely accurate.

And if you want to see what's tracked in your current directory:
dpavlin@nuc:~/some_subdir$ bak ls-files
file1.txt

4. Make sure we don't break anything:
I wrote a new isolated `test.sh` suite that runs an ephemeral `bak-git-server.pl` on port 9002. It tests 18 edge cases (like single-character paths `bak diff --stat /` and backward-compatible space-delimited parsing) without touching production data.

As a fun side effect of building the whitelist, I dug through old git logs and uncovered the MAXXO project infrastructure (circa 2011-2012, including n2n community `calyx` on `10.13.37.x`). I moved 70 legacy hosts to `legacy_hosts.txt` so we keep only our active ones in the whitelist.

Whole solution seems much more robust now, with data channels optimized for speed and encrypted connections tightly verified.
