#!/usr/bin/env python3
"""Migrate LuckyTNTMod recipe JSON to the 26.2 format.

- Ingredients are now plain id strings: {"item":"X"} -> "X"; {"tag":"X"} -> "#X".
  Applies to shaped "key" values, shapeless "ingredients", and cooking "ingredient".
  The "result" object ({"id":..,"count":..}) is left untouched.
- The mod's custom "luckytntmod:smelting_mult" serializer was never ported to Java, so
  those recipes fail to load. Convert them to vanilla "minecraft:smelting" (count on the
  result is dropped — vanilla smelting yields one item).
"""
import json, os, sys, glob

RECIPE_DIR = sys.argv[1] if len(sys.argv) > 1 else \
    "tntmod/src/main/resources/data/luckytntmod/recipe"

def fix_forge(s):
    # Forge tag namespace -> Fabric conventional tags
    if isinstance(s, str):
        return s.replace("forge:", "c:")
    return s

def conv_ingredient(v):
    """{"item":"x"}->"x", {"tag":"x"}->"#x"; lists element-wise; forge:->c:; else unchanged."""
    if isinstance(v, dict):
        if set(v.keys()) == {"item"}:
            return fix_forge(v["item"])
        if set(v.keys()) == {"tag"}:
            return "#" + fix_forge(v["tag"])
    if isinstance(v, list):
        return [conv_ingredient(e) for e in v]
    return fix_forge(v)

changed = 0
for path in glob.glob(os.path.join(RECIPE_DIR, "*.json")):
    with open(path) as f:
        try:
            data = json.load(f)
        except Exception as e:
            print("SKIP (bad json):", path, e); continue
    orig = json.dumps(data, sort_keys=True)

    # custom *_mult cooking serializers were never ported -> map to vanilla equivalents
    MULT = {
        "luckytntmod:smelting_mult": "minecraft:smelting",
        "luckytntmod:blasting_mult": "minecraft:blasting",
        "luckytntmod:smoking_mult": "minecraft:smoking",
    }
    if data.get("type") in MULT:
        data["type"] = MULT[data["type"]]
        # vanilla cooking result: keep {"id":..}; drop count (unsupported)
        if isinstance(data.get("result"), dict):
            data["result"] = {"id": data["result"].get("id")}

    # shaped: key map
    if isinstance(data.get("key"), dict):
        data["key"] = {k: conv_ingredient(v) for k, v in data["key"].items()}
    # shapeless: ingredients list
    if "ingredients" in data:
        data["ingredients"] = conv_ingredient(data["ingredients"])
    # cooking: single ingredient
    if "ingredient" in data:
        data["ingredient"] = conv_ingredient(data["ingredient"])

    if json.dumps(data, sort_keys=True) != orig:
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        changed += 1

print(f"Rewrote {changed} recipe files under {RECIPE_DIR}")
