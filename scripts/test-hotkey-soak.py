#!/usr/bin/env python3
"""Run the trusted real-key helper with an independent crash/timeout recovery path."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--report', type=Path)
parser.add_argument('--quick', action='store_true', help='Debug fixture/UI setup without the 300-press soak')
parser.add_argument('--chord-stress', action='store_true', help='Repeat each held chord 20 times per app')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
app = root / 'build/DeskNames.app'
output = Path(tempfile.mkdtemp(prefix='desknames-hotkey-launch-'))
report = (args.report or output / 'report.json').resolve()
log = output / 'output.log'
journal = output / 'recovery.json'
if report.exists():
    raise SystemExit('Choose a new report path; refusing stale test evidence.')


def launch(mode, argument, output_log):
    return ['open', '-n', '-W', '--stdout', str(output_log), '--stderr', str(output_log),
            str(app), '--args', mode, str(argument)]


def stop_owned(pid, required_argument):
    if not pid:
        return
    command = subprocess.run(['ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True).stdout
    if str(app / 'Contents/MacOS/DeskNames') in command and required_argument in command:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


try:
    subprocess.run(['osascript', '-e', 'tell application id "local.desknames.app" to quit'], timeout=15, check=True)
    subprocess.run(launch('--hotkey-soak-test', '--report', log) + [str(report), '--journal', str(journal)] + (['--quick'] if args.quick else []) + (['--chord-stress'] if args.chord_stress else []), timeout=600, check=True)
finally:
    try:
        cleanup_failed = report.exists() and any(row['result'] == 'FAIL' and row['scenario'].startswith('cleanup-') for row in json.loads(report.read_text())['observations'])
        if (not report.exists() or cleanup_failed) and journal.exists():
            recovery = json.loads(journal.read_text())
            stop_owned(recovery.get('helperPID'), '--hotkey-soak-test')
            stop_owned(recovery.get('targetPID'), recovery['storage'])
            recovery_log = output / 'recovery.log'
            try:
                subprocess.run(launch('--hotkey-soak-cleanup', journal, recovery_log), timeout=90, check=True)
            finally:
                if recovery_log.exists():
                    print(recovery_log.read_text(), flush=True)
    finally:
        subprocess.run(['open', '/Applications/DeskNames.app'], timeout=15, check=True)
        print(f'Log: {log}\nReport: {report}\nRecovery journal: {journal}', flush=True)
        if log.exists():
            print(log.read_text(), flush=True)
if not report.exists():
    raise SystemExit('FAIL: helper did not produce a report')
result = json.loads(report.read_text())
raise SystemExit(any(row['result'] == 'FAIL' for row in result['observations']))
