"""Public-tree hygiene and Markdown link checks; never prints matched secrets."""
from pathlib import Path
import re
import sys
from urllib.parse import unquote

root = Path(sys.argv[1]).resolve()
skip = {".git", ".build", ".swiftpm", "dist", "__pycache__"}
failures = []
key_pattern = re.compile(r"sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----")
for path in root.rglob("*"):
    relative = path.relative_to(root)
    if any(part in skip for part in relative.parts):
        continue
    if path.is_symlink():
        failures.append(f"symlink: {relative}")
        continue
    if not path.is_file():
        continue
    if path.suffix in {".sqlite", ".log", ".p12", ".pfx", ".key", ".mobileprovision"} or path.name.startswith(".env"):
        failures.append(f"private file type: {relative}")
    if path.suffix.lower() in {".png", ".icns"}:
        continue  # Visual review is a separate release step.
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        failures.append(f"unexpected binary: {relative}")
        continue
    if key_pattern.search(text):
        failures.append(f"credential pattern: {relative}")
    if re.search(r"/Users/" + r"[^\s/]+/", text):
        failures.append(f"personal absolute path: {relative}")
    if path.suffix == ".md":
        for link in re.findall(r"\]\(([^)]+)\)", text):
            if re.match(r"[a-zA-Z]+:", link) or link.startswith("#"):
                continue
            destination = path.parent / unquote(link.split("#")[0])
            if not destination.exists():
                failures.append(f"broken relative link: {relative}")
if failures:
    print("\n".join(sorted(set(failures))))
    raise SystemExit(1)
print("Public tree checks passed (text patterns, private file types, symlinks, relative links).")
