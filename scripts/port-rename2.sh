#!/usr/bin/env bash
# Second-pass mechanical renames (26.2), covering yarn leftovers port-rename.sh missed.
# High-confidence, verified against /opt/mc-src. Skips mixins. Run once from repo root.
set -euo pipefail
SRC="${1:-tntmod/src}"
mapfile -t FILES < <(find "$SRC" -name '*.java' -not -path '*/mixin/*')
echo "Second pass over ${#FILES[@]} files..."

perl -pi -e '
  # ---- vanilla EntityType constants: EntityType.CREEPER -> EntityTypes.CREEPER ----
  # (ALL_CAPS member access only; leaves EntityType.Builder / .create / EntityType<?> alone)
  s/\bEntityType\.([A-Z][A-Z0-9_]+)\b/EntityTypes.$1/g;

  # ---- fully-qualified yarn packages (class name unchanged) ----
  s/net\.minecraft\.registry\.tag\./net.minecraft.tags./g;
  s/net\.minecraft\.util\.math\.ChunkPos\b/net.minecraft.world.level.ChunkPos/g;
  s/net\.minecraft\.util\.math\.BlockBox\b/net.minecraft.world.level.levelgen.structure.BoundingBox/g;
  s/net\.minecraft\.util\.math\.Vec2f\b/net.minecraft.world.phys.Vec2/g;
  s/net\.minecraft\.util\.math\.random\.\w+/net.minecraft.util.RandomSource/g;
  s/net\.minecraft\.world\.chunk\./net.minecraft.world.level.chunk./g;
  s/net\.minecraft\.world\.biome\./net.minecraft.world.level.biome./g;
  s/net\.minecraft\.state\.property\.Properties\b/net.minecraft.world.level.block.state.properties.BlockStateProperties/g;
  s/net\.minecraft\.entity\.effect\.StatusEffectInstance\b/net.minecraft.world.effect.MobEffectInstance/g;
  s/net\.minecraft\.entity\.effect\.StatusEffects\b/net.minecraft.world.effect.MobEffects/g;
  s/net\.minecraft\.registry\.entry\.RegistryEntry\b/net.minecraft.core.Holder/g;
  s/net\.minecraft\.entity\.mob\.MobEntity\b/net.minecraft.world.entity.Mob/g;
  s/net\.minecraft\.entity\.mob\.HostileEntity\b/net.minecraft.world.entity.monster.Monster/g;
  s/net\.minecraft\.entity\.mob\.PathAwareEntity\b/net.minecraft.world.entity.PathfinderMob/g;
  s/net\.minecraft\.server\.command\.ServerCommandSource\b/net.minecraft.commands.CommandSourceStack/g;
  s/net\.minecraft\.screen\.CommonComponents\b/net.minecraft.network.chat.CommonComponents/g;

  # ---- bare class-name tokens (word boundary) that the above imply ----
  s/\bStatusEffectInstance\b/MobEffectInstance/g;
  s/\bStatusEffects\b/MobEffects/g;
  s/\bMobEntity\b/Mob/g;
  s/\bHostileEntity\b/Monster/g;
  s/\bVec2f\b/Vec2/g;
  s/\bServerCommandSource\b/CommandSourceStack/g;
  s/\bLightningEntity\b/LightningBolt/g;
  s/\bMathHelper\b/Mth/g;
' "${FILES[@]}"

echo "Done. Review with: git diff --stat"
