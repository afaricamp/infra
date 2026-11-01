"""Checks the devkit plugin against the rules in devkit/README.md.

Prints 'ok    ...' / 'FAIL  ...' lines like tests/static/policy.sh and exits
non-zero if anything failed. Standard library only.

Usage: python3 tests/lib/skills.py [plugin dir, default devkit]
"""
import json
import os
import re
import sys

PLUGIN = sys.argv[1] if len(sys.argv) > 1 else "devkit"
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
# Fields that run things without a permission prompt in every project.
FORBIDDEN_FIELDS = {"allowed-tools", "hooks"}
MIN_EVALS = 3
MAX_LINES = 500

failed = False


def ok(msg):
    print(f"ok    {msg}")


def bad(msg):
    global failed
    print(f"FAIL  {msg}", file=sys.stderr)
    failed = True


def check(cond, msg):
    (ok if cond else bad)(msg)


def frontmatter(text):
    """Top-level keys of a simple YAML frontmatter block (scalars and lists)."""
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end < 0:
        return None
    fields = {}
    for line in text[4:end].splitlines():
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if m:
            fields[m.group(1)] = m.group(2).strip().strip('"')
    return fields


try:
    with open(os.path.join(PLUGIN, ".claude-plugin", "plugin.json")) as f:
        manifest = json.load(f)
    check(manifest.get("name") == os.path.basename(os.path.abspath(PLUGIN)),
          f"plugin.json name is '{os.path.basename(os.path.abspath(PLUGIN))}'")
except (OSError, ValueError) as e:
    bad(f"plugin.json cannot be read: {e}")

with open(os.path.join(PLUGIN, "README.md")) as f:
    readme = f.read()

skills_dir = os.path.join(PLUGIN, "skills")
for skill in sorted(os.listdir(skills_dir)):
    path = os.path.join(skills_dir, skill, "SKILL.md")
    if not os.path.isfile(path):
        bad(f"{skills_dir}/{skill} has no SKILL.md")
        continue
    with open(path) as f:
        text = f.read()
    fm = frontmatter(text)
    if fm is None:
        bad(f"{path} has no frontmatter")
        continue

    check(fm.get("name") == skill, f"{skill}: name matches the folder")
    check(bool(NAME_RE.match(skill)) and len(skill) <= 64, f"{skill}: name is lowercase and hyphenated")
    desc = fm.get("description", "")
    check(0 < len(desc) <= 1024, f"{skill}: description has 1-1024 characters ({len(desc)})")
    for field in sorted(FORBIDDEN_FIELDS & fm.keys()):
        bad(f"{skill}: '{field}' is not allowed in shared skills")
    check("!`" not in text, f"{skill}: no !`command` injection")
    check(text.count("\n") < MAX_LINES, f"{skill}: SKILL.md under {MAX_LINES} lines")
    check(f"`{skill}`" in readme, f"{skill}: listed in {PLUGIN}/README.md")

    # Relative links in the skill point to files that exist.
    for link in re.findall(r"\]\(((?:references|assets|scripts)/[^)]+)\)", text):
        check(os.path.isfile(os.path.join(skills_dir, skill, link)), f"{skill}: link {link} exists")
    # Files named through ${CLAUDE_PLUGIN_ROOT} exist in the plugin.
    for ref in re.findall(r"\$\{CLAUDE_PLUGIN_ROOT\}/([\w./-]+[\w])", text):
        check(os.path.isfile(os.path.join(PLUGIN, ref)), f"{skill}: plugin file {ref} exists")

    cases_dir = os.path.join(PLUGIN, "evals", skill)
    cases = []
    if os.path.isdir(cases_dir):
        cases = [c for c in os.listdir(cases_dir)
                 if os.path.isfile(os.path.join(cases_dir, c, "prompt.md"))]
    check(len(cases) >= MIN_EVALS, f"{skill}: at least {MIN_EVALS} eval cases ({len(cases)})")
    for c in cases:
        graders = os.path.join(cases_dir, c, "graders")
        check(os.path.isdir(graders) and os.listdir(graders), f"{skill}/{c}: has graders")

sys.exit(1 if failed else 0)
