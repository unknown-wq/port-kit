#!/usr/bin/env bash
# Third-pass: yarn->Mojang method renames (verified against /opt/mc-src). Skips mixins.
set -euo pipefail
SRC="${1:-tntmod/src}"
mapfile -t FILES < <(find "$SRC" -name '*.java' -not -path '*/mixin/*')
echo "Method-rename pass over ${#FILES[@]} files..."
perl -pi -e '
  s/\.getDefaultState\(/.defaultBlockState(/g;
  s/\.getBlastResistance\(/.getExplosionResistance(/g;
  s/\.onDestroyedByExplosion\(/.wasExploded(/g;
  s/\.setPosition\(/.setPos(/g;
  s/\.getChunkManager\(/.getChunkSource(/g;
  s/\.isSkyVisible\(/.canSeeSky(/g;
  s/\.getRegistryManager\(/.registryAccess(/g;
  s/\.spawnParticles\(/.sendParticles(/g;
  s/\.isOf\(/.is(/g;
  s/\.isIn\(/.is(/g;
  s/\.down\(/.below(/g;
  s/\.up\(/.above(/g;
  s/\.north\(/.north(/g;
  s/\.isClient\b/.isClientSide/g;
  s/\.getStructureTemplateManager\(/.getStructureManager(/g;
' "${FILES[@]}"
echo "Done."
