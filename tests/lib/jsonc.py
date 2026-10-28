#!/usr/bin/env python3
"""Minimal JSONC (JSON with // and /* */ comments) reader for devcontainer.json.

  jsonc.py FILE...              validate: exit 1 if any file does not parse
  jsonc.py --get KEY FILE       print a top-level value: one line per element
                                for a list, KEY=VALUE lines for an object,
                                the plain value otherwise

Standard library only, so it runs on any host with python3.
"""
import json
import sys


def strip_comments(text):
    out, i, n = [], 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
        elif c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise ValueError("unterminated /* comment")
            # Keep the newlines so json error line numbers still match.
            out.append("\n" * text.count("\n", i, end))
            i = end + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.loads(strip_comments(f.read()))


def main(argv):
    if len(argv) == 3 and argv[0] == "--get":
        value = load(argv[2]).get(argv[1])
        if value is None:
            return 1
        if isinstance(value, dict):
            for k, v in value.items():
                print(f"{k}={v}")
        else:
            for item in value if isinstance(value, list) else [value]:
                print(item)
        return 0
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    status = 0
    for path in argv:
        try:
            load(path)
            print(f"ok    {path}")
        except (OSError, ValueError) as e:
            print(f"FAIL  {path}: {e}", file=sys.stderr)
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
