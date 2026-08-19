#!/usr/bin/env bash
# First-pass mechanical renames Yarn -> Mojang official (26.2), derived from PORT-MOD-26.2.md §4.
# Run ONCE from the repo root BEFORE any hand edits:  ./port-rename.sh
# Skips mixin/ dirs (mixin targets/descriptors must be re-verified by hand).
# This is a FIRST PASS: the compiler catches the leftovers — fix those by error, not by re-reading files.
set -euo pipefail
SRC="${1:-tntmod/src}"

mapfile -t FILES < <(find "$SRC" -name '*.java' -not -path '*/mixin/*')
echo "Rewriting ${#FILES[@]} files under $SRC (mixins excluded)..."

perl -pi -e '
  # ---- fully-qualified imports / package paths ----
  s/net\.minecraft\.util\.Identifier\b/net.minecraft.resources.Identifier/g;
  s/net\.minecraft\.util\.math\.BlockPos\b/net.minecraft.core.BlockPos/g;
  s/net\.minecraft\.util\.math\.Vec3d\b/net.minecraft.world.phys.Vec3/g;
  s/net\.minecraft\.util\.math\.Box\b/net.minecraft.world.phys.AABB/g;
  s/net\.minecraft\.util\.math\.Direction\b/net.minecraft.core.Direction/g;
  s/net\.minecraft\.util\.math\.MathHelper\b/net.minecraft.util.Mth/g;
  s/net\.minecraft\.util\.math\.random\.Random\b/net.minecraft.util.RandomSource/g;
  s/net\.minecraft\.util\.hit\.(\w+)/net.minecraft.world.phys.$1/g;
  s/net\.minecraft\.util\.Hand\b/net.minecraft.world.InteractionHand/g;
  s/net\.minecraft\.util\.(Typed)?ActionResult\b/net.minecraft.world.InteractionResult/g;
  s/net\.minecraft\.text\.Text\b/net.minecraft.network.chat.Component/g;
  s/net\.minecraft\.text\.MutableText\b/net.minecraft.network.chat.MutableComponent/g;
  s/net\.minecraft\.world\.World\b/net.minecraft.world.level.Level/g;
  s/net\.minecraft\.world\.WorldAccess\b/net.minecraft.world.level.LevelAccessor/g;
  s/net\.minecraft\.world\.BlockView\b/net.minecraft.world.level.BlockGetter/g;
  s/net\.minecraft\.server\.world\.ServerWorld\b/net.minecraft.server.level.ServerLevel/g;
  s/net\.minecraft\.world\.explosion\.Explosion\b/net.minecraft.world.level.Explosion/g;
  s/net\.minecraft\.fluid\.FluidState\b/net.minecraft.world.level.material.FluidState/g;
  s/net\.minecraft\.block\.BlockState\b/net.minecraft.world.level.block.state.BlockState/g;
  s/net\.minecraft\.block\.AbstractBlock\b/net.minecraft.world.level.block.state.BlockBehaviour/g;
  s/net\.minecraft\.block\.MapColor\b/net.minecraft.world.level.material.MapColor/g;
  s/net\.minecraft\.block\.(Block|Blocks|TntBlock)\b/net.minecraft.world.level.block.$1/g;
  s/net\.minecraft\.sound\.BlockSoundGroup\b/net.minecraft.world.level.block.SoundType/g;
  s/net\.minecraft\.sound\.SoundCategory\b/net.minecraft.sounds.SoundSource/g;
  s/net\.minecraft\.sound\.(SoundEvent|SoundEvents)\b/net.minecraft.sounds.$1/g;
  s/net\.minecraft\.nbt\.NbtCompound\b/net.minecraft.nbt.CompoundTag/g;
  s/net\.minecraft\.entity\.player\.PlayerEntity\b/net.minecraft.world.entity.player.Player/g;
  s/net\.minecraft\.server\.network\.ServerPlayerEntity\b/net.minecraft.server.level.ServerPlayer/g;
  s/net\.minecraft\.entity\.damage\.(\w+)/net.minecraft.world.damagesource.$1/g;
  s/net\.minecraft\.entity\.TntEntity\b/net.minecraft.world.entity.item.PrimedTnt/g;
  s/net\.minecraft\.entity\.mob\.PathAwareEntity\b/net.minecraft.world.entity.PathfinderMob/g;
  s/net\.minecraft\.entity\.projectile\.PersistentProjectileEntity\b/net.minecraft.world.entity.projectile.arrow.AbstractArrow/g;
  s/net\.minecraft\.entity\.projectile\.ProjectileEntity\b/net.minecraft.world.entity.projectile.Projectile/g;
  s/net\.minecraft\.entity\.vehicle\.AbstractMinecartEntity\b/net.minecraft.world.entity.vehicle.minecart.AbstractMinecart/g;
  s/net\.minecraft\.entity\.vehicle\.MinecartEntity\b/net.minecraft.world.entity.vehicle.minecart.Minecart/g;
  s/net\.minecraft\.entity\.data\.DataTracker\b/net.minecraft.network.syncher.SynchedEntityData/g;
  s/net\.minecraft\.entity\.data\.TrackedDataHandlerRegistry\b/net.minecraft.network.syncher.EntityDataSerializers/g;
  s/net\.minecraft\.entity\.data\.TrackedData\b/net.minecraft.network.syncher.EntityDataAccessor/g;
  s/net\.minecraft\.entity\.(Entity|LivingEntity|EntityType|MovementType|SpawnGroup|EntityDimensions)\b/net.minecraft.world.entity.$1/g;
  s/net\.minecraft\.item\.ItemUsageContext\b/net.minecraft.world.item.context.UseOnContext/g;
  s/net\.minecraft\.item\.ItemGroups\b/net.minecraft.world.item.CreativeModeTabs/g;
  s/net\.minecraft\.item\.(\w+)/net.minecraft.world.item.$1/g;
  s/net\.minecraft\.particle\.(\w+)/net.minecraft.core.particles.$1/g;
  s/net\.minecraft\.network\.PacketByteBuf\b/net.minecraft.network.FriendlyByteBuf/g;
  s/net\.minecraft\.network\.RegistryByteBuf\b/net.minecraft.network.RegistryFriendlyByteBuf/g;
  s/net\.minecraft\.network\.codec\.PacketCodec\b/net.minecraft.network.codec.StreamCodec/g;
  s/net\.minecraft\.network\.packet\.CustomPayload\b/net.minecraft.network.protocol.common.custom.CustomPacketPayload/g;
  s/net\.minecraft\.registry\.Registries\b/net.minecraft.core.registries.__BUILTIN_REG__/g;
  s/net\.minecraft\.registry\.RegistryKeys\b/net.minecraft.core.registries.RegistryKeys/g;
  s/net\.minecraft\.registry\.Registry\b/net.minecraft.core.Registry/g;
  s/net\.minecraft\.client\.MinecraftClient\b/net.minecraft.client.Minecraft/g;
  s/net\.minecraft\.client\.util\.math\.MatrixStack\b/com.mojang.blaze3d.vertex.PoseStack/g;
  s/net\.minecraft\.client\.render\.VertexConsumerProvider\b/net.minecraft.client.renderer.MultiBufferSource/g;
  s/net\.minecraft\.client\.font\.TextRenderer\b/net.minecraft.client.gui.Font/g;
  s/net\.minecraft\.client\.gui\.DrawContext\b/net.minecraft.client.gui.GuiGraphics/g;
  s/net\.minecraft\.client\.gui\.screen\.Screen\b/net.minecraft.client.gui.screens.Screen/g;

  # ---- simple class-name tokens (word-boundary) ----
  s/\bNbtCompound\b/CompoundTag/g;
  s/\bVec3d\b/Vec3/g;
  s/\bMathHelper\b/Mth/g;
  s/\bMutableText\b/MutableComponent/g;
  s/\bText\b/Component/g;
  s/\bScreenTexts\b/CommonComponents/g;
  s/\bServerWorld\b/ServerLevel/g;
  s/\bWorldAccess\b/LevelAccessor/g;
  s/\bBlockView\b/BlockGetter/g;
  s/\bWorld\b/Level/g;
  s/\bServerPlayerEntity\b/ServerPlayer/g;
  s/\bPlayerEntity\b/Player/g;
  s/\bTntEntity\b/PrimedTnt/g;
  s/\bPathAwareEntity\b/PathfinderMob/g;
  s/\bSpawnGroup\b/MobCategory/g;
  s/\bMovementType\b/MoverType/g;
  s/\bPersistentProjectileEntity\b/AbstractArrow/g;
  s/\bProjectileEntity\b/Projectile/g;
  s/\bAbstractMinecartEntity\b/AbstractMinecart/g;
  s/\bMinecartEntity\b/Minecart/g;
  s/\bDataTracker\b/SynchedEntityData/g;
  s/\bTrackedDataHandlerRegistry\b/EntityDataSerializers/g;
  s/\bTrackedData\b/EntityDataAccessor/g;
  s/\bTypedActionResult\b/InteractionResult/g;
  s/\bActionResult\b/InteractionResult/g;
  s/\bHand\b/InteractionHand/g;
  s/\bBlockSoundGroup\b/SoundType/g;
  s/\bSoundCategory\b/SoundSource/g;
  s/\bParticleEffect\b/ParticleOptions/g;
  s/\bPacketByteBuf\b/FriendlyByteBuf/g;
  s/\bRegistryByteBuf\b/RegistryFriendlyByteBuf/g;
  s/\bPacketCodec\b/StreamCodec/g;
  s/\bCustomPayload\b/CustomPacketPayload/g;
  s/\bMinecraftClient\b/Minecraft/g;
  s/\bMatrixStack\b/PoseStack/g;
  s/\bVertexConsumerProvider\b/MultiBufferSource/g;
  s/\bDrawContext\b/GuiGraphics/g;
  s/\bButtonWidget\b/Button/g;
  s/\bAbstractBlock\b/BlockBehaviour/g;
  s/Item\.Settings\b/Item.Properties/g;
  s/BlockBehaviour\.Settings\b/BlockBehaviour.Properties/g;
  s/\bRegistries\b/__BUILTIN_REG__/g;
  s/\bRegistryKeys\b/Registries/g;
  s/__BUILTIN_REG__/BuiltInRegistries/g;
  s/Identifier\.of\(/Identifier.fromNamespaceAndPath(/g;

  # ---- common method renames ----
  s/\.getWorld\(\)/.level()/g;
  s/\.setVelocity\(/.setDeltaMovement(/g;
  s/\.getVelocity\(/.getDeltaMovement(/g;
  s/\.isOnGround\(\)/.onGround()/g;
  s/\.hasNoGravity\(\)/.isNoGravity()/g;
  s/\.getSoundCategory\(/.getSoundSource(/g;
  s/\.getYaw\(/.getYRot(/g;
  s/\.setYaw\(/.setYRot(/g;
  s/\.getPitch\(/.getXRot(/g;
  s/\.setPitch\(/.setXRot(/g;
  s/\.spawnEntity\(/.addFreshEntity(/g;
  s/\.getStackInHand\(/.getItemInHand(/g;
  s/\.maxCount\(/.stacksTo(/g;
  s/\.decrement\(/.shrink(/g;
' "${FILES[@]}"

echo "Done. Review with: git diff --stat"
echo "Now run compileJava and fix ONLY what the compiler reports."
