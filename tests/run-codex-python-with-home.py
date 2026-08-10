#!/usr/bin/env python3

import importlib.machinery
import importlib.util
import sys
from pathlib import Path


script_path = Path(sys.argv[1]).resolve()
fake_home = Path(sys.argv[2]).resolve()
loader = importlib.machinery.SourceFileLoader("tested_codex_script", str(script_path))
spec = importlib.util.spec_from_loader(loader.name, loader)
if spec is None or spec.loader is None:
    raise SystemExit("could not load test target")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.Path.home = lambda: fake_home
sys.argv = [str(script_path), *sys.argv[3:]]
raise SystemExit(module.main())
