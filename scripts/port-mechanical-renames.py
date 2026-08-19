#!/usr/bin/env python3
"""The mechanical half of the NeoForge 1.21.1 -> Fabric 26.2 rename work.

Only renames that are true one-to-one substitutions live here. Anything where the
replacement has a different shape (MultiBufferSource, GuiGraphics, ArmorItem,
InteractionResultHolder, ...) is deliberately absent: those are judgement calls and
belong to an agent, not to sed.

  ResourceLocation      -> Identifier         (net.minecraft.resources)
  new ResourceLocation  -> Identifier.fromNamespaceAndPath / .parse, by arity
  IPayloadContext       -> PlayMessageContext (com.ldtteam.common.network)
  ModConfigSpec.*       -> ConfigValue.*      (com.ldtteam.common.config)

Usage: port-mechanical-renames.py <source-root>
"""
import os
import re
import sys
from collections import Counter

ROOT = sys.argv[1] if len(sys.argv) > 1 else "26.2/src/main/java"

stats = Counter()


def split_new_resourcelocation(text):
    """Rewrite `new ResourceLocation(...)` by counting its top-level arguments.

    Two arguments is a namespace/path pair -> fromNamespaceAndPath. One argument is a
    combined "ns:path" string -> parse. Paren matching is done by hand because the
    arguments routinely contain nested calls and string concatenation.
    """
    needle = "new ResourceLocation("
    out, i = [], 0
    while True:
        j = text.find(needle, i)
        if j < 0:
            out.append(text[i:])
            return "".join(out)
        out.append(text[i:j])
        k = j + len(needle)
        depth, commas, in_str, in_chr, esc = 1, 0, False, False, False
        while k < len(text) and depth:
            c = text[k]
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif in_str:
                in_str = c != '"'
            elif in_chr:
                in_chr = c != "'"
            elif c == '"':
                in_str = True
            elif c == "'":
                in_chr = True
            elif c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
            elif c == "," and depth == 1:
                commas += 1
            k += 1
        args = text[j + len(needle):k - 1]
        if commas == 1:
            out.append("Identifier.fromNamespaceAndPath(" + args + ")")
            stats["new ResourceLocation(ns, path) -> Identifier.fromNamespaceAndPath"] += 1
        elif commas == 0:
            out.append("Identifier.parse(" + args + ")")
            stats["new ResourceLocation(str) -> Identifier.parse"] += 1
        else:
            out.append(text[j:k])
            stats["new ResourceLocation with unexpected arity — LEFT ALONE"] += 1
        i = k


WORD_RENAMES = [
    (re.compile(r"\bResourceLocation\b"), "Identifier", "ResourceLocation -> Identifier"),
    (re.compile(r"\bIPayloadContext\b"), "PlayMessageContext", "IPayloadContext -> PlayMessageContext"),
]

IMPORT_RENAMES = [
    (re.compile(r"^import\s+net\.minecraft\.resources\.Identifier;\s*$", re.M),
     "import net.minecraft.resources.Identifier;\n", None),
    (re.compile(r"^import\s+net\.neoforged\.neoforge\.network\.handling\.PlayMessageContext;\s*$", re.M),
     "import com.ldtteam.common.network.PlayMessageContext;\n",
     "IPayloadContext import -> ldtteam.common"),
    (re.compile(r"^import\s+net\.neoforged\.neoforge\.common\.ModConfigSpec\.\*;\s*$", re.M),
     "import com.ldtteam.common.config.ConfigValue.*;\n",
     "ModConfigSpec.* import -> ConfigValue.*"),
    (re.compile(r"^import\s+net\.neoforged\.neoforge\.common\.ModConfigSpec\.(\w+);\s*$", re.M),
     r"import com.ldtteam.common.config.ConfigValue.\1;" + "\n",
     "ModConfigSpec.X import -> ConfigValue.X"),
]

touched = 0
for dirpath, _, files in os.walk(ROOT):
    for f in files:
        if not f.endswith(".java"):
            continue
        path = os.path.join(dirpath, f)
        with open(path, encoding="utf-8") as fh:
            original = fh.read()

        text = split_new_resourcelocation(original)
        for pattern, repl, label in WORD_RENAMES:
            text, n = pattern.subn(repl, text)
            if n and label:
                stats[label] += n
        for pattern, repl, label in IMPORT_RENAMES:
            text, n = pattern.subn(repl, text)
            if n and label:
                stats[label] += n

        if text != original:
            touched += 1
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)

print(f"files rewritten: {touched}\n")
for k, n in stats.most_common():
    print(f"{n:6d}  {k}")
