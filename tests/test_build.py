import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_build_script_runs():
    result = subprocess.run(
        [sys.executable, os.path.join(ROOT, 'build.py')],
        capture_output=True,
        text=True,
        cwd=ROOT,
        check=False,
    )
    assert result.returncode == 0, result.stderr or result.stdout
    assert 'Built' in result.stdout or 'built' in result.stdout.lower()
    assert os.path.exists(os.path.join(ROOT, 'build', 'dist', 'build-manifest.txt'))
