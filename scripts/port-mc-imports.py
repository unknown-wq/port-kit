#!/usr/bin/env python3
"""Repoint moved `net.minecraft.*` imports at their 26.2 packages.

The source is NeoForge on official Mojang names, so nothing is *renamed* here --
classes only moved between packages (ResourceLocation -> Identifier and friends are
handled separately, they are genuine renames). For every `import net.minecraft...X;`
this looks X up in the decompiled 26.2 tree; if it lives in exactly one package, the
import is repointed there. Ambiguous and missing classes are left alone and reported,
because guessing at those is how a port acquires silent wrong behaviour.

Usage: port-mc-imports.py <source-root>
"""
import collections
import os
import re
import sys

MC_SRC = "/opt/mc-src/net/minecraft"
ROOT = sys.argv[1] if len(sys.argv) > 1 else "26.2/src/main/java"

index = collections.defaultdict(set)
for dirpath, _, files in os.walk(MC_SRC):
    pkg = "net.minecraft" + dirpath[len(MC_SRC):].replace("/", ".")
    for f in files:
        if f.endswith(".java"):
            index[f[:-5]].add(pkg)

IMPORT = re.compile(r"^(import\s+(?:static\s+)?)net\.minecraft\.([\w.]+)\.(\w+);\s*$")

# `import net.minecraft.data.PackOutput.Target;` names a nested class, not a package
# member: the segment before the last one is capitalised. Repointing those by simple name
# lands on an unrelated class in another package -- skip them, an agent handles the outer.
NESTED = re.compile(r"^import\s+(?:static\s+)?net\.minecraft\.[\w.]*\.[A-Z][\w$]*\.[A-Z][\w$]*;")

moved = collections.Counter()
gone = collections.Counter()
ambiguous = collections.Counter()
touched = 0

for dirpath, _, files in os.walk(ROOT):
    for f in files:
        if not f.endswith(".java"):
            continue
        path = os.path.join(dirpath, f)
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
        out, changed = [], False
        for line in lines:
            m = IMPORT.match(line)
            if not m or NESTED.match(line.strip()):
                out.append(line)
                continue
            prefix, old_pkg, cls = m.group(1), "net.minecraft." + m.group(2), m.group(3)
            pkgs = index.get(cls)
            if not pkgs:
                gone[f"{old_pkg}.{cls}"] += 1
                out.append(line)
            elif len(pkgs) > 1:
                if old_pkg not in pkgs:
                    ambiguous[f"{old_pkg}.{cls}"] += 1
                out.append(line)
            else:
                new_pkg = next(iter(pkgs))
                if new_pkg == old_pkg:
                    out.append(line)
                else:
                    moved[f"{old_pkg}.{cls} -> {new_pkg}"] += 1
                    out.append(f"{prefix}{new_pkg}.{cls};\n")
                    changed = True
        if changed:
            touched += 1
            with open(path, "w", encoding="utf-8") as fh:
                fh.writelines(out)

print(f"files rewritten: {touched}")
print(f"imports repointed: {sum(moved.values())} ({len(moved)} distinct)")
print(f"classes not found in 26.2: {sum(gone.values())} ({len(gone)} distinct)")
print(f"ambiguous (several packages, old one wrong): {sum(ambiguous.values())} ({len(ambiguous)} distinct)")
print()
print("=== top moves ===")
for k, n in moved.most_common(40):
    print(f"{n:5d}  {k}")
print()
print("=== not found — these need a human or an agent ===")
for k, n in gone.most_common(60):
    print(f"{n:5d}  {k}")
print()
print("=== ambiguous ===")
for k, n in ambiguous.most_common(30):
    print(f"{n:5d}  {k}")
