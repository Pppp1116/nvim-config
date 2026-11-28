#!/usr/bin/env python3
"""Run configuration tests with disposable Neovim state and cache."""

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="nvim-config-tests-") as scratch:
    env = os.environ.copy()
    env["XDG_STATE_HOME"] = str(Path(scratch) / "state")
    env["XDG_CACHE_HOME"] = str(Path(scratch) / "cache")
    env["NVIM_LOG_FILE"] = str(Path(scratch) / "nvim.log")
    for script in (
        "tests/run.lua",
        "tests/edge_cases.lua",
        "tests/build_integration.lua",
        "tests/navigation_integration.lua",
        "tests/rust_integration.lua",
    ):
        result = subprocess.run(
            ["nvim", "--headless", "-u", "init.lua", "-l", script],
            cwd=ROOT,
            env=env,
            check=False,
            timeout=30 if script == 'tests/rust_integration.lua' else 15,
        )
        if result.returncode:
            raise SystemExit(result.returncode)
    without_plugins = env.copy()
    without_plugins["XDG_DATA_HOME"] = str(Path(scratch) / "empty-data")
    result = subprocess.run(
        ["nvim", "--headless", "-u", "init.lua", "+qa!"],
        cwd=ROOT,
        env=without_plugins,
        check=False,
        timeout=5,
    )
    if result.returncode:
        raise SystemExit(result.returncode)
    bad_state = Path(scratch) / 'state-is-a-file'
    bad_state.write_text('not a directory')
    unusable_state = env.copy()
    unusable_state['XDG_STATE_HOME'] = str(bad_state)
    result = subprocess.run(
        ["nvim", "--headless", "-u", "init.lua",
         "+lua print(vim.o.swapfile, vim.o.undofile)", "+qa!"],
        cwd=ROOT,
        env=unusable_state,
        check=False,
        timeout=5,
        capture_output=True,
        text=True,
    )
    if result.returncode or 'false false' not in result.stdout + result.stderr:
        raise SystemExit('unwritable recovery directory was not handled')
    (Path(without_plugins['XDG_DATA_HOME']) / 'nvim/lazy/lazy.nvim').mkdir(parents=True)
    result = subprocess.run(
        ["nvim", "--headless", "-u", "init.lua", "+qa!"],
        cwd=ROOT,
        env=without_plugins,
        check=False,
        timeout=5,
    )
    if result.returncode:
        raise SystemExit(result.returncode)
