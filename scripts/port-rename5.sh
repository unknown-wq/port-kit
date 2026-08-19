#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-tntmod/src}"
mapfile -t FILES < <(find "$SRC" -name '*.java' -not -path '*/mixin/*')
perl -pi -e '
  s/\.getNonSpectatingEntities\(/.getEntitiesOfClass(/g;
  s/\.setStackInHand\(/.setItemInHand(/g;
  s/\.prevX\b/.xo/g;
  s/\.prevY\b/.yo/g;
  s/\.prevZ\b/.zo/g;
  s/\bStairsBlock\b/StairBlock/g;
  s/\bStairShape\b/StairsShape/g;
' "${FILES[@]}"
echo "pass5 done over ${#FILES[@]} files"
