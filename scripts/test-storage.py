#!/usr/bin/env python3
"""Verify preference isolation in a separate Foundation process, without launching apps."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

root = Path(__file__).resolve().parent.parent
(root / 'build').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='storage-regression-', dir=root / 'build') as directory:
    temporary = Path(directory)
    main = temporary / 'main.swift'
    shutil.copyfile(root / 'Tools/storage-isolation-test.swift', main)
    binary = temporary / ('DeskNamesStorageProbe-' + uuid.uuid4().hex)
    subprocess.run(['xcrun', 'swiftc', str(root / 'Sources/DeskNames/RuntimeStorage.swift'),
                    str(root / 'Sources/DeskNames/SelfTests/StorageTests.swift'),
                    str(main), '-o', str(binary)], check=True)
    try:
        subprocess.run([str(binary), str(temporary / 'isolated')], check=True)
    finally:
        # The unique executable domain exists only to prove exclusion from the child suite.
        (Path.home() / 'Library/Preferences' / (binary.name + '.plist')).unlink(missing_ok=True)
