#!/usr/bin/env bash
# ============================================================================
# park-stop.sh — end a PARKED PS5 14.22 session (session85.sh).
#
#   bash park-stop.sh /tmp/opencode/ps5-park-<rundir>.env
#
# 1. QMP `quit` over the existing FIFO pipe chardev (no sockets; L-223/L-224).
# 2. If quit does not take the VM down: SIGTERM QEMU_PID (only if /proc/PID/comm
#    is still qemu-system-x86*, so a recycled pid is never signalled), then
#    SIGKILL after a grace period.
# 3. Delete the /tmp/ps5park.* IPC dir (known files only — never rm -rf).
# 4. Remove coord/BOOT.lock (the lock is kept while the VM is parked).
#
# The park env file is kept as evidence; delete it by hand if you want.
# Every branch logs on entry; every failure prints PARK-STOP-FAIL on stderr.
# ============================================================================
set -u
if [ "$#" -ne 1 ]; then
  echo "PARK-STOP-FAIL: usage: bash park-stop.sh <env-file>" >&2
  exit 2
fi
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
exec python3 - "$1" "$SCRIPT_DIR" <<'PY'
import json
import os
import select
import stat
import sys
import time

TIMEOUT = 5.0
env_path = sys.argv[1]
script_dir = sys.argv[2]


def log(msg):
    print('PARK-STOP: ' + msg, flush=True)


def fail(msg):
    print('PARK-STOP-FAIL: ' + msg, file=sys.stderr, flush=True)


log('ENTER env=%s' % env_path)

if not os.path.isfile(env_path):
    fail('env file not found: %s' % env_path)
    sys.exit(1)
env = {}
with open(env_path, 'r', errors='replace') as fh:
    for line in fh:
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        env[key.strip()] = value.strip()

ipc = env.get('IPC_DIR', '')
try:
    qemu_pid = int(env.get('QEMU_PID', '0'))
except ValueError:
    qemu_pid = 0
if not ipc:
    fail('env file has no IPC_DIR: %s' % env_path)
    sys.exit(1)
log('parked VM ipc=%s qemu_pid=%s' % (ipc, qemu_pid))

failures = []


def proc_state(pid):
    try:
        with open('/proc/%d/stat' % pid, 'r') as fh:
            return fh.read().split(')', 1)[1].split()[0]
    except OSError:
        return None


def alive(pid):
    if pid <= 0:
        return False
    state = proc_state(pid)
    return state is not None and state != 'Z'


def is_qemu(pid):
    try:
        with open('/proc/%d/comm' % pid, 'r') as fh:
            return fh.read().strip().startswith('qemu-system-x86')
    except OSError:
        return False


# ------------------------------------------------------- 1. QMP quit
fifo_in = os.path.join(ipc, 'qmp.in')
fifo_out = os.path.join(ipc, 'qmp.out')
quit_sent = False
if os.path.isdir(ipc) and os.path.exists(fifo_in) and os.path.exists(fifo_out):
    try:
        wfd = os.open(fifo_in, os.O_RDWR)
        rfd = os.open(fifo_out, os.O_RDWR)
    except OSError as e:
        log('QUIT: cannot open QMP FIFO pair (%r) — falling back to signals' % e)
        wfd = rfd = None
    if wfd is not None:
        buf = b''

        def send(msg):
            os.write(wfd, (json.dumps(msg) + '\n').encode())

        def read_until(want, timeout=TIMEOUT):
            global buf
            deadline = time.monotonic() + timeout
            while True:
                while b'\n' in buf:
                    line, _, buf = buf.partition(b'\n')
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        msg = json.loads(line)
                    except ValueError:
                        continue
                    if msg.get('id') == want:
                        return msg
                left = deadline - time.monotonic()
                if left <= 0:
                    return None
                ready, _, _ = select.select([rfd], [], [], left)
                if not ready:
                    return None
                chunk = os.read(rfd, 65536)
                if not chunk:
                    return None
                buf += chunk

        send({'execute': 'qmp_capabilities', 'id': 'stop-caps'})
        caps = read_until('stop-caps')
        if caps is None:
            log('QUIT: no QMP reply (VM already gone?) — will verify pid')
        elif 'error' in caps and 'already complete' not in json.dumps(caps['error']):
            log('QUIT: qmp_capabilities error %s — trying quit anyway'
                % json.dumps(caps['error']))
        log('QUIT: sending QMP quit')
        send({'execute': 'quit', 'id': 'stop-quit'})
        reply = read_until('stop-quit', 3.0)
        if reply is None:
            log('QUIT: no reply to quit (normal: QEMU may exit before replying)')
        elif 'error' in reply:
            log('QUIT: QMP quit error %s' % json.dumps(reply['error']))
        else:
            log('QUIT: QMP quit accepted')
        quit_sent = True
        for fd in (wfd, rfd):
            try:
                os.close(fd)
            except OSError:
                pass
else:
    log('QUIT: IPC dir/pipe absent (%s) — no QMP channel, falling back to signals' % ipc)

# ------------------------------------------------- 2. wait / signal fallback
if qemu_pid and alive(qemu_pid):
    for _ in range(50):          # up to 5 s after quit
        if not alive(qemu_pid):
            break
        time.sleep(0.1)
if alive(qemu_pid):
    if is_qemu(qemu_pid):
        log('SIGNAL: QEMU %d still alive — SIGTERM%s'
            % (qemu_pid, '' if quit_sent else ' (quit was not possible)'))
        try:
            os.kill(qemu_pid, 15)
        except OSError as e:
            log('SIGNAL: SIGTERM failed: %r' % e)
        for _ in range(50):
            if not alive(qemu_pid):
                break
            time.sleep(0.1)
        if alive(qemu_pid):
            log('SIGNAL: still alive — SIGKILL %d' % qemu_pid)
            try:
                os.kill(qemu_pid, 9)
            except OSError as e:
                log('SIGNAL: SIGKILL failed: %r' % e)
            time.sleep(0.5)
    else:
        log('SIGNAL: pid %d is no longer qemu-system-x86* — NOT signalled (pid reuse guard)' % qemu_pid)
if qemu_pid and alive(qemu_pid):
    failures.append('QEMU pid %d is still alive' % qemu_pid)
else:
    log('QEMU down (pid %s)' % qemu_pid)

# ------------------------------------------------------- 3. delete IPC dir
if os.path.isdir(ipc):
    real = os.path.realpath(ipc)
    if os.path.dirname(real) != '/tmp' or not os.path.basename(real).startswith('ps5park.'):
        failures.append('refusing to delete unexpected IPC dir %r (not /tmp/ps5park.*)' % real)
    else:
        for name in ('gdb.in', 'gdb.out', 'qmp.in', 'qmp.out', 'gdb_bridge.py'):
            path = os.path.join(real, name)
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
            except OSError as e:
                failures.append('cannot remove %s: %r' % (path, e))
        try:
            os.rmdir(real)
            log('IPC: removed %s' % real)
        except OSError as e:
            failures.append('cannot rmdir %s: %r' % (real, e))
else:
    log('IPC: %s already absent' % ipc)

# ------------------------------------------------------- 4. remove BOOT.lock
# Prefer the lock path recorded by session85.sh at park time (BOOT_LOCK=).
# Fall back to <kit>/../../coord/BOOT.lock for hand-written env files.
lock = env.get('BOOT_LOCK', '')
if not lock:
    lock = os.path.join(os.path.abspath(os.path.join(script_dir, '..', '..')),
                        'coord', 'BOOT.lock')
if os.path.exists(lock):
    try:
        os.unlink(lock)
        log('LOCK: removed %s' % lock)
    except OSError as e:
        failures.append('cannot remove %s: %r' % (lock, e))
else:
    log('LOCK: %s already absent' % lock)

log('env file kept as evidence: %s' % env_path)

if failures:
    for f in failures:
        fail(f)
    sys.exit(1)
log('DONE: QEMU stopped, IPC removed, BOOT.lock removed')
sys.exit(0)
PY
