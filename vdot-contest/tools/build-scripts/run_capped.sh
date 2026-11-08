#!/bin/bash
# Run a command inside a memory-capped cgroup (v1) so the WSL VM never asks the
# Windows host for more memory than it can commit; overflow goes to Linux swap.
CG=/sys/fs/cgroup/memory/xsbuild
LIMIT_MB=${LIMIT_MB:-5632}
mkdir -p $CG
echo $((LIMIT_MB*1024*1024)) > $CG/memory.limit_in_bytes
echo 60 > $CG/memory.swappiness 2>/dev/null || true
echo $$ > $CG/cgroup.procs
exec "$@"
