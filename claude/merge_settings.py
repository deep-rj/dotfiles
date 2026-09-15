#!/usr/bin/env python3
"""Deep-merge settings.snippet.json into ~/.claude/settings.json, leaving keys that locally differ untouched instead of overwriting them. Usage: merge_settings.py <snippet.json> <settings.json> [--apply]"""

import json
import os
import sys


def deep_merge(base, overlay, path=""):
    changed = []
    conflicts = []
    for key, want in overlay.items():
        p = f"{path}.{key}" if path else key
        if key not in base:
            base[key] = want
            changed.append((p, "add", want))
        elif isinstance(base[key], dict) and isinstance(want, dict):
            c, cf = deep_merge(base[key], want, p)
            changed += c
            conflicts += cf
        elif base[key] == want:
            pass
        else:
            conflicts.append((p, base[key], want))
    return changed, conflicts


def main():
    apply = "--apply" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--apply"]
    snippet_path, settings_path = args

    with open(snippet_path) as f:
        snippet = json.load(f)

    settings = {}
    if os.path.exists(settings_path):
        with open(settings_path) as f:
            settings = json.load(f)

    changed, conflicts = deep_merge(settings, snippet)

    for p, verb, new in changed:
        print(f"  + {verb} {p}: {json.dumps(new)}")
    for p, old, new in conflicts:
        print(
            f"  ! conflict {p}: local value kept ({json.dumps(old)}), "
            f"dotfiles wants {json.dumps(new)} - reconcile manually",
            file=sys.stderr,
        )
    if not changed and not conflicts:
        print("  (already up to date)")

    if apply and changed:
        os.makedirs(os.path.dirname(settings_path) or ".", exist_ok=True)
        with open(settings_path, "w") as f:
            json.dump(settings, f, indent=2)
            f.write("\n")

    return 1 if conflicts else 0


if __name__ == "__main__":
    sys.exit(main())
