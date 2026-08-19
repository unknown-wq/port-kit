#!/usr/bin/env bash
# Fourth-pass: more verified yarn->Mojang method/const renames. Skips mixins.
set -euo pipefail
SRC="${1:-tntmod/src}"
mapfile -t FILES < <(find "$SRC" -name '*.java' -not -path '*/mixin/*')
echo "Pass 4 over ${#FILES[@]} files..."
perl -pi -e '
  # method renames
  s/\.setBlockState\(/.setBlock(/g;
  s/\.isFullCube\(/.isCollisionShapeFullBlock(/g;
  s/\.isFaceFullSquare\(/.isFaceSturdy(/g;
  s/\.isSideSolidFullSquare\(/.isFaceSturdy(/g;
  s/\.getOffsetX\(/.getStepX(/g;
  s/\.getOffsetY\(/.getStepY(/g;
  s/\.getOffsetZ\(/.getStepZ(/g;
  s/\.crossProduct\(/.cross(/g;
  s/\.getLerpedPos\(/.getPosition(/g;
  s/\.getLightEmission\(/.getLightEmission(/g;
  # blockstate .with(prop,val) -> .setValue(prop,val)
  s/\.with\(/.setValue(/g;
  # bare class tokens
  s/\bBox\b/AABB/g;
  s/\bRegistryEntry\b/Holder/g;
  # sound const lost ENTITY_ prefix
  s/\bENTITY_GENERIC_EXPLODE\b/GENERIC_EXPLODE/g;
  # state property access Properties.FACING -> BlockStateProperties.FACING (not X.Properties)
  s/(?<!\.)\bProperties\.([A-Z][A-Z0-9_]+)/BlockStateProperties.$1/g;
' "${FILES[@]}"
echo "Done."
