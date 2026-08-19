#!/usr/bin/env python3
"""Generate the Stable's blueprints for every shipped style.

Upstream MineColonies wrote the whole cavalry feature (the horse, the AI, the job, the guard type,
the building class and its modules) and then never landed the fourth pull request, the one that
would have shipped the building.  There is no ``stable*.blueprint`` in this port, in upstream's
9,460, or anywhere else, so nothing a player can do reaches the cavalry.  This script fills that
hole without a blueprint editor, which the CI container has no client to run.

The blueprint format is Structurize's v1 NBT (see
``/workspace/structurize/26.2/.../blueprints/v1/BlueprintUtil.java``).  Rather than invent geometry,
each style's stable is derived from that same style's cow barn -- ``agriculture/husbandry/cowboy*``
or ``cowhand*`` depending on how old the style is.  A cow barn is already a hand-built, style-correct
farm building with a fenced pen, five levels of it, in every style; the transform is:

  * the anchor's ``minecolonies:blockhutcowboy`` palette entry becomes ``minecolonies:blockhutstable``,
    which is what actually decides the building type at placement time;
  * the anchor block entity's ``schematicName``/``path`` are renamed to ``stableN`` so
    ``WorkOrderBuilding`` (which upgrades by swapping the trailing digit) and
    ``BuildingStable.getSchematicName()`` agree;
  * ``stall`` tags are added to the anchor's ``posTagMap`` -- ``BuildingStable.stallPositions()``
    warns and returns nothing without them, and ``ReturnToStableGoal``/``CavalryStrollGoal`` walk
    horses to them.  Stall spots are found by scanning the blueprint for standable, open-sky floor
    tiles in the pen, so they land where the cows used to graze rather than inside the barn (the
    horse's navigator is configured never to enter a door).
  * one ``patrol_point`` tag, which is what BuildingStable.patrolPointForBuilding looks for on a
    building a cavalry patrol is routed to.

Nothing else in the donor is touched: the geometry, the palette and every other block entity are
the style author's work, unmodified, so the result cannot be geometrically invalid.

Usage:  python3 make-stable-blueprints.py [--check] <blueprints-root>
        (blueprints-root defaults to 26.2/src/main/resources/blueprints/minecolonies)
"""

import os
import sys
import nbtlib
from nbtlib import Compound, List, String, Int, IntArray

HUT_FROM = 'minecolonies:blockhutcowboy'
HUT_TO = 'minecolonies:blockhutstable'

# Blocks a horse cannot stand on top of, or which are not really "floor".
NON_SOLID_SUFFIX = ('_fence', '_fence_gate', '_wall', '_door', '_trapdoor', '_sign', '_banner',
                    '_carpet', '_button', '_pressure_plate', '_torch', '_slab', '_stairs',
                    '_pane', '_bars', '_chain', '_lantern', '_rail', '_sapling', '_bed',
                    '_pot', '_ladder', '_vine', '_leaves', '_head', '_candle', '_grass',
                    '_fern', '_flower', '_bush', '_roots', '_sprouts', '_coral', '_amethyst_bud')
NON_SOLID_EXACT = {'minecraft:water', 'minecraft:lava', 'minecraft:torch', 'minecraft:ladder',
                   'minecraft:vine', 'minecraft:snow', 'minecraft:fire', 'minecraft:scaffolding',
                   'minecraft:cobweb', 'minecraft:lily_pad', 'minecraft:cactus',
                   'minecraft:sugar_cane', 'minecraft:bamboo', 'minecraft:composter',
                   'minecraft:cauldron', 'minecraft:chain', 'minecraft:end_rod'}
AIR = {'minecraft:air', 'minecraft:cave_air', 'minecraft:void_air',
       'structurize:blocksubstitution'}


def classify(name):
    """air (a horse may occupy it) / solid (a horse may stand on it) / other (neither)."""
    if name in AIR:
        return 'air'
    if name == 'structurize:blocksolidsubstitution':
        return 'solid'
    if name in NON_SOLID_EXACT or name.endswith(NON_SOLID_SUFFIX):
        return 'other'
    return 'solid'


def load(path):
    f = nbtlib.load(path)
    return f.root if hasattr(f, 'root') else f


def dims(root):
    return int(root['size_x']), int(root['size_y']), int(root['size_z'])


def unpack_blocks(root):
    sx, sy, sz = dims(root)
    flat = []
    for v in root['blocks']:
        v = int(v) & 0xFFFFFFFF
        flat.append((v >> 16) & 0xFFFF)
        flat.append(v & 0xFFFF)
    blocks, i = [], 0
    for _ in range(sy):
        plane = []
        for _ in range(sz):
            plane.append(flat[i:i + sx])
            i += sx
        blocks.append(plane)
    return blocks


def primary_offset(root):
    od = root.get('optional_data')
    if od is not None and 'structurize' in od and 'primary_offset' in od['structurize']:
        p = od['structurize']['primary_offset']
        return (int(p['x']), int(p['y']), int(p['z']))
    return None


def anchor_te(root):
    for te in root.get('tile_entities', []):
        if str(te.get('id', '')) == 'minecolonies:colonybuilding':
            return te
    return None


def standable_spots(root, require_sky=True):
    """Floor tiles a horse fits on: solid below, two air above.

    With require_sky the column also has to be clear all the way to the top of the blueprint, which
    is what separates the open pen from the inside of the barn.  Underground styles (cavern) have no
    such column anywhere, so the caller retries without it.
    """
    sx, sy, sz = dims(root)
    blocks = unpack_blocks(root)
    kinds = [classify(str(e.get('Name', ''))) for e in root['palette']]
    spots = []
    for x in range(sx):
        for z in range(sz):
            col = [kinds[blocks[y][z][x]] for y in range(sy)]
            for y in range(sy - 3):
                if col[y] != 'solid' or col[y + 1] != 'air' or col[y + 2] != 'air':
                    continue
                if require_sky and any(c != 'air' for c in col[y + 3:]):
                    break
                spots.append((x, y + 1, z))
                break
    return spots


def largest_component(spots):
    """4-connected component (same y) with the most tiles -- that is the pen."""
    remaining = set(spots)
    best = []
    while remaining:
        seed = next(iter(remaining))
        stack, comp = [seed], []
        remaining.discard(seed)
        while stack:
            x, y, z = stack.pop()
            comp.append((x, y, z))
            for nx, nz in ((x + 1, z), (x - 1, z), (x, z + 1), (x, z - 1)):
                if (nx, y, nz) in remaining:
                    remaining.discard((nx, y, nz))
                    stack.append((nx, y, nz))
        if len(comp) > len(best):
            best = comp
    return best


def spread(comp, anchor, count):
    """Farthest-point sampling, seeded from the tile nearest the anchor."""
    if not comp or count <= 0:
        return []
    ax, _, az = anchor
    chosen = [min(comp, key=lambda p: (p[0] - ax) ** 2 + (p[2] - az) ** 2)]
    while len(chosen) < count and len(chosen) < len(comp):
        nxt = max(comp, key=lambda p: min((p[0] - c[0]) ** 2 + (p[2] - c[2]) ** 2 for c in chosen))
        if nxt in chosen:
            break
        chosen.append(nxt)
    return chosen


def bpos(x, y, z):
    return Compound({'x': Int(x), 'y': Int(y), 'z': Int(z)})


def read_bpos(c):
    return (int(c['x']), int(c['y']), int(c['z']))


def tag_entry(pos, names):
    return Compound({
        'tagPos': bpos(*pos),
        'tagNameList': List[Compound]([Compound({'tagName': String(n)}) for n in names]),
    })


def convert(src, dst, level, verbose=True):
    root = load(src)
    name = 'stable%d' % level

    # 1. The hut block. This is what makes the placed building a Stable.
    swapped = 0
    for entry in root['palette']:
        if str(entry.get('Name', '')) == HUT_FROM:
            entry['Name'] = String(HUT_TO)
            swapped += 1
    if swapped == 0:
        raise RuntimeError('%s: no %s in the palette' % (src, HUT_FROM))

    te = anchor_te(root)
    if te is None:
        raise RuntimeError('%s: no minecolonies:colonybuilding block entity' % src)
    anchor = primary_offset(root) or (int(te['x']), int(te['y']), int(te['z']))

    # 2. Names. WorkOrderBuilding upgrades by replacing the trailing digit of this path, and
    #    BuildingStable.getSchematicName() returns "stable", so both halves have to say stableN.
    root['name'] = String(name + '.blueprint')
    te['path'] = String(name + '.blueprint')
    bd = te['blueprintDataProvider']
    bd['path'] = String(name + '.blueprint')
    bd['schematicName'] = String(name)

    # 3. Tags. Keep whatever the donor had (groundlevel), add stalls and a patrol point.
    #
    # posTagMap is read back into a Map<BlockPos, List<String>> (IBlueprintDataProviderBE#readTagPosMapFrom),
    # so two entries at the same position do not merge -- the later one wins and the earlier tag is lost
    # silently. Collect into a dict keyed by position and write one entry per position.
    c1 = read_bpos(bd['corner1'])
    c2 = read_bpos(bd['corner2'])
    tagged = {}
    for e in bd.get('posTagMap', []):
        names = [str(t['tagName']) for t in e['tagNameList']]
        if any(n in ('stall', 'patrol_point') for n in names):
            continue
        pos = read_bpos(e['tagPos'])
        if not all(c1[i] <= pos[i] <= c2[i] for i in range(3)):
            # original/cowboy2 carries a tag at (-840, 14, -1526) -- an absolute world position saved as a
            # relative one by whoever scanned it. Copying it forward would give the stable a tag pointing a
            # kilometre away, so drop anything outside the blueprint's own corners.
            continue
        tagged.setdefault(pos, []).extend(names)

    pen = largest_component(standable_spots(root, require_sky=True))
    if len(pen) < 2:
        # Roofed styles (cavern) have no open sky at all; take the biggest indoor floor instead.
        pen = largest_component(standable_spots(root, require_sky=False))
    # The mount cap is 2 x building level (EntityAIWorkStablemaster#convertMount), so give the
    # stable that many stalls when the pen is big enough to hold them.
    stalls = spread(pen, anchor, min(2 * level, max(1, len(pen) // 2)))
    for (x, y, z) in stalls:
        tagged.setdefault((x - anchor[0], y - anchor[1], z - anchor[2]), []).append('stall')

    # A patrol point as far from the anchor as the pen reaches, so cavalry routed to this stable rides
    # round it rather than stopping on the hut block. Prefer a tile that is not already a stall.
    free = [p for p in pen if (p[0] - anchor[0], p[1] - anchor[1], p[2] - anchor[2]) not in tagged]
    if free or pen:
        far = max(free or pen, key=lambda p: (p[0] - anchor[0]) ** 2 + (p[2] - anchor[2]) ** 2)
        tagged.setdefault((far[0] - anchor[0], far[1] - anchor[1], far[2] - anchor[2]), []).append('patrol_point')

    bd['posTagMap'] = List[Compound]([tag_entry(pos, names) for pos, names in tagged.items()])

    os.makedirs(os.path.dirname(dst), exist_ok=True)
    nbtlib.File(root, gzipped=True).save(dst)
    if verbose:
        print('  %s -> %s  (%d stalls, pen %d tiles)'
              % (os.path.basename(src), os.path.relpath(dst), len(stalls), len(pen)))
    return len(stalls)


def find_donor(style_dir, level):
    """The style's cow barn at this level, wherever the style keeps it."""
    husbandry = os.path.join(style_dir, 'agriculture', 'husbandry')
    if not os.path.isdir(husbandry):
        return None
    for stem in ('cowboy', 'cowhand'):
        candidate = os.path.join(husbandry, '%s%d.blueprint' % (stem, level))
        if os.path.isfile(candidate):
            return candidate
    # cavern keeps its huts one level deeper, under default/ and megahall/
    for sub in sorted(os.listdir(husbandry)):
        subdir = os.path.join(husbandry, sub)
        if not os.path.isdir(subdir):
            continue
        for stem in ('cowboy', 'cowhand'):
            candidate = os.path.join(subdir, '%s%d.blueprint' % (stem, level))
            if os.path.isfile(candidate):
                return candidate
    return None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    root_dir = args[0] if args else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', '..',
        '26.2', 'src', 'main', 'resources', 'blueprints', 'minecolonies')
    root_dir = os.path.abspath(root_dir)

    styles = sorted(d for d in os.listdir(root_dir)
                    if os.path.isdir(os.path.join(root_dir, d)))
    done, skipped = 0, []
    for style in styles:
        style_dir = os.path.join(root_dir, style)
        donors = [(lvl, find_donor(style_dir, lvl)) for lvl in range(1, 6)]
        if any(d is None for _, d in donors):
            skipped.append(style)
            continue
        print(style)
        for lvl, donor in donors:
            # The donor is a cow barn and lives under agriculture/husbandry; the stable does not.  The
            # build tool groups by folder, and a building whose whole point is cavalry belongs beside the
            # barracks rather than beside the pig sty -- that is where a player goes looking for it.
            dst = os.path.join(style_dir, 'military', 'stable%d.blueprint' % lvl)
            convert(donor, dst, lvl)
            done += 1
    print('\n%d blueprints written across %d styles' % (done, len(styles) - len(skipped)))
    if skipped:
        print('no cow barn to derive from, skipped: %s' % ', '.join(skipped))


if __name__ == '__main__':
    main()
