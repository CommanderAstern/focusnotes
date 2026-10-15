#!/usr/bin/env python3
"""Reject unsafe app names and output parents before build/install scripts mutate them."""

from pathlib import Path
import os
import re
import sys


APP_NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,62}\Z", re.ASCII)


def refuse(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(2)


def main() -> None:
    if len(sys.argv) not in (3, 4):
        refuse("Usage: check-app-path.py APPNAME TARGET_PARENT [TARGET_NAME]")

    app_name, parent_arg = sys.argv[1:3]
    if APP_NAME_RE.fullmatch(app_name) is None:
        refuse(
            "Unsafe APPNAME: use 1-63 ASCII letters, digits, underscores, or hyphens, "
            "starting with a letter or digit."
        )

    parent = Path(parent_arg)
    if not parent.is_absolute():
        refuse(f"Refusing non-absolute app target parent: {parent}")

    # The callers pass physical repository/home paths (or /Applications). Requiring
    # the parent to already be canonical rejects symlinks in any parent component.
    parent = Path(os.path.abspath(parent))
    if parent != Path(os.path.realpath(parent)):
        refuse(f"Refusing app target parent containing a symlink: {parent}")
    if parent.exists():
        if parent.is_symlink() or not parent.is_dir():
            refuse(f"App target parent is not a real directory: {parent}")
    elif not parent.parent.is_dir():
        refuse(f"App target parent has no existing directory anchor: {parent}")

    target_name = sys.argv[3] if len(sys.argv) == 4 else f"{app_name}.app"
    if target_name in ("", ".", "..") or Path(target_name).name != target_name:
        refuse(f"Refusing non-basename app target: {target_name}")

    target = parent / target_name
    if target.is_symlink():
        refuse(f"Refusing app target that is a symlink: {target}")
    if target.exists() and not target.is_dir():
        refuse(f"App target exists but is not a directory: {target}")
    if Path(os.path.realpath(target)).parent != parent:
        refuse(f"App target resolves outside its intended directory: {target}")


if __name__ == "__main__":
    main()
