#!/usr/bin/env python3
"""Run the five non-desktop-switching modes with disposable preference storage."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
binary = root / 'build/DeskNames.app/Contents/MacOS/DeskNames'
artifacts = Path(tempfile.mkdtemp(prefix='robustness-tests-', dir=root / 'build'))
print(f'Logs and isolated storage: {artifacts}', flush=True)
failed = []
for mode in ['self-test', 'pane-session-test', 'pane-interaction-test', 'movement-session-test', 'window-refresh-test']:
    directory = artifacts / mode
    home = directory / 'home'
    temporary = directory / 'tmp'
    home.mkdir(parents=True)
    temporary.mkdir()
    environment = dict(os.environ, CFFIXED_USER_HOME=str(home), TMPDIR=str(temporary) + '/', NSUnbufferedIO='YES')
    with (directory / 'output.log').open('w') as output:
        try:
            result = subprocess.run([str(binary), '--' + mode], env=environment,
                                    stdout=output, stderr=subprocess.STDOUT, timeout=120)
            status = result.returncode
        except subprocess.TimeoutExpired:
            status = 124
            output.write('FAIL: Test exceeded 120 seconds.\n')
    print((directory / 'output.log').read_text(), end='', flush=True)
    print(f'RESULT --{mode}: exit {status}', flush=True)
    if status:
        failed.append(mode)
raise SystemExit(bool(failed))
