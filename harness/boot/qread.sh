#!/usr/bin/env bash
# ============================================================================
# qread.sh — query a PARKED PS5 14.22 VM (session85.sh) through QEMU's QMP
# human-monitor-command over the EXISTING FIFO pipe chardev. No sockets:
# AF_INET/AF_UNIX bind is EPERM on this host (LEDGER L-223/L-224).
#
#   bash qread.sh <env-file> <hmp-command...>
#   bash qread.sh --cont <env-file> <hmp-command...>
#
# The env file is the self-describing /tmp/opencode/ps5-park-<rundir>.env that
# session85.sh writes when it parks the VM. The `return` text is printed
# verbatim on stdout; every failure prints `QREAD-FAIL: ...` on stderr and
# exits non-zero (never a silent empty success).
#
# Default: no `cont`, no `stop` — park leaves the guest STOPPED and a stopped
# guest is exactly what HMP xp / info registers want. --cont issues QMP `cont`
# before the query and QMP `stop` after it (both idempotent), for a parked VM
# that was resumed by an earlier query or is running for any other reason.
#
# Exit: 0 = query returned text; 1 = QMP/handshake/empty-return failure;
#       2 = usage error.
# ============================================================================
set -u
if [ "$#" -lt 2 ]; then
  echo "QREAD-FAIL: usage: bash qread.sh [--cont] <env-file> <hmp-command...>" >&2
  exit 2
fi
exec python3 - "$@" <<'PY'
import json
import os
import select
import stat
import sys
import time

TIMEOUT = 10.0


def qfail(msg):
    # Print here, not only in a later handler: failures before/inside the QMP
    # session (missing env file, missing pipe, QMP error, empty return) must
    # always emit QREAD-FAIL on stderr — never a traceback, never silent.
    print('QREAD-FAIL: %s' % msg, file=sys.stderr, flush=True)
    raise SystemExit(1)


def entry_log(msg):
    # Instrumentation must log on entry (never a silent branch).
    print('QREAD: ' + msg, file=sys.stderr, flush=True)


argv = sys.argv[1:]
cont = False
if argv and argv[0] == '--cont':
    cont = True
    argv = argv[1:]
if len(argv) < 2:
    qfail('usage: bash qread.sh [--cont] <env-file> <hmp-command...>')
env_path = argv[0]
hmp_cmd = ' '.join(argv[1:])

entry_log('ENTER env=%s mode=%s cmd=%r' %
          (env_path, 'cont+query+stop' if cont else 'query', hmp_cmd))

# ---------------------------------------------------------------- env file
if not os.path.isfile(env_path):
    qfail('env file not found: %s' % env_path)
env = {}
try:
    with open(env_path, 'r', errors='replace') as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, value = line.split('=', 1)
            env[key.strip()] = value.strip()
except OSError as e:
    qfail('cannot read env file %s: %r' % (env_path, e))

ipc = env.get('IPC_DIR', '')
if not ipc:
    qfail('env file has no IPC_DIR: %s' % env_path)
if not os.path.isdir(ipc):
    qfail('IPC_DIR does not exist (was the session already stopped?): %s' % ipc)
fifo_in = os.path.join(ipc, 'qmp.in')
fifo_out = os.path.join(ipc, 'qmp.out')
for path in (fifo_in, fifo_out):
    try:
        st = os.stat(path)
    except OSError as e:
        qfail('QMP pipe missing (%s): %r' % (path, e))
    if not stat.S_ISFIFO(st.st_mode):
        qfail('not a FIFO: %s' % path)

try:
    wfd = os.open(fifo_in, os.O_RDWR)
    rfd = os.open(fifo_out, os.O_RDWR)
except OSError as e:
    qfail('cannot open QMP FIFO pair in %s: %r' % (ipc, e))

buf = b''
seq = 0
cont_active = False


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
                continue  # greeting/event/partial text: never a match
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


def request(execute, args=None, tag=None):
    global seq
    seq += 1
    want = tag or ('qread-%d' % seq)
    msg = {'execute': execute, 'id': want}
    if args is not None:
        msg['arguments'] = args
    send(msg)
    return read_until(want)


def close_fds():
    for fd in (wfd, rfd):
        try:
            os.close(fd)
        except OSError:
            pass


def stop_after_cont():
    entry_log('STOP: sending QMP stop after the query (--cont)')
    reply = request('stop', tag='qread-stop')
    if reply is None:
        return 'stop after query: no QMP reply'
    if 'error' in reply:
        return 'stop after query: QMP error %s' % json.dumps(reply['error'])
    entry_log('STOP: guest stopped again')
    return None


rc = 0
try:
    # qmp_capabilities: on a parked VM the monitor is already in command mode,
    # so QEMU answers "Capabilities negotiation is already complete, command
    # ignored". That exact error is benign (proven by /tmp/opencode/
    # qmp_reattach_test.py); anything else is a failure.
    reply = request('qmp_capabilities', tag='qread-caps')
    if reply is None:
        qfail('no QMP reply in %ss on %s (QEMU not running, or pipe peer gone)' %
              (TIMEOUT, ipc))
    if 'error' in reply:
        if 'already complete' not in json.dumps(reply['error']):
            qfail('qmp_capabilities failed: %s' % json.dumps(reply['error']))
        entry_log('CAPS: already negotiated (benign) — continuing')
    elif 'return' not in reply:
        qfail('qmp_capabilities returned neither return nor error: %s' % json.dumps(reply))

    if cont:
        entry_log('CONT: sending QMP cont before the query (idempotent)')
        reply = request('cont', tag='qread-cont')
        if reply is None:
            qfail('cont: no QMP reply')
        if 'error' in reply:
            qfail('cont failed: %s' % json.dumps(reply['error']))
        cont_active = True

    reply = request('human-monitor-command',
                    {'command-line': hmp_cmd}, tag='qread-cmd')
    if reply is None:
        qfail('no QMP reply to human-monitor-command %r' % hmp_cmd)
    if 'error' in reply:
        qfail('HMP %r failed: %s' % (hmp_cmd, json.dumps(reply['error'])))
    text = reply.get('return')
    if not isinstance(text, str):
        qfail('HMP %r returned no text: %s' % (hmp_cmd, json.dumps(reply)))
    if not text.strip():
        qfail('HMP %r returned EMPTY text — refusing to report a silent success'
              % hmp_cmd)

    sys.stdout.write(text)
    if not text.endswith('\n'):
        sys.stdout.write('\n')
    sys.stdout.flush()
    entry_log('OK: %d bytes returned' % len(text))
except Exception as e:  # never die silently
    print('QREAD-FAIL: unhandled %r' % (e,), file=sys.stderr, flush=True)
    rc = 1
finally:
    if cont_active:
        try:
            problem = stop_after_cont()
        except Exception as e:
            problem = 'stop after query raised %r' % (e,)
        if problem:
            print('QREAD-FAIL: %s' % problem, file=sys.stderr, flush=True)
            rc = 1
    close_fds()

sys.exit(rc)
PY
