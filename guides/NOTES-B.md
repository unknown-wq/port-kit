# NOTES-B — NeoForge 1.21.1 → Fabric 26.2: entities, upgrades, networking

Verified against the decompiled tree at `/opt/mc-src` (Loom's Fabric-patched 26.2 sources) and the
Fabric API jars in `~/.gradle/caches/modules-2/files-2.1/net.fabricmc.fabric-api/`.
Every row below was compiled successfully with:

```sh
CP=$(find /root/.gradle/caches/modules-2/files-2.1 -name '*.jar' | grep -v sources | tr '\n' ':')\
/root/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.2/minecraft-merged-deobf-26.2.jar
/usr/lib/jvm/java-25-openjdk-amd64/bin/javac -proc:none --release 25 -cp "$CP" -d /tmp/out $(find src/main/java -name '*.java')
```

> That `javac` invocation is **not** gradle and does not touch the build dir — it is the cheapest way
> to check a pass before handing errors back to the orchestrator.

---

## 0. The rename that touches every file

| 1.21.1 | 26.2 | source |
|---|---|---|
| `net.minecraft.resources.ResourceLocation` | **`net.minecraft.resources.Identifier`** | `/opt/mc-src/net/minecraft/resources/Identifier.java` |
| `ResourceLocation.fromNamespaceAndPath/parse/tryParse` | same names on `Identifier` | ibid. l.40/44/52 |
| `ResourceLocation.STREAM_CODEC` | `Identifier.STREAM_CODEC` (`StreamCodec<ByteBuf, Identifier>`) | ibid. l.20 |
| `FriendlyByteBuf#writeResourceLocation/readResourceLocation` | **`writeIdentifier` / `readIdentifier`** | `/opt/mc-src/net/minecraft/network/FriendlyByteBuf.java:579,583` |
| `net.minecraft.Util` | **`net.minecraft.util.Util`** | `/opt/mc-src/net/minecraft/world/entity/animal/parrot/Parrot.java:31` |
| `net.minecraft.world.entity.npc.Villager` | **`net.minecraft.world.entity.npc.villager.Villager`** | `/opt/mc-src/net/minecraft/world/entity/npc/villager/` |
| `net.minecraft.world.level.GameRules` | **`net.minecraft.world.level.gamerules.GameRules`** | `/opt/mc-src/net/minecraft/world/level/gamerules/GameRules.java` |
| `javax.annotation.Nullable` | not on the classpath → **`org.jspecify.annotations.Nullable`** | jspecify-1.0.0 is a transitive dep |

Dead ends:
* `net.minecraft.client.renderer.MultiBufferSource`, `net.minecraft.client.gui.GuiGraphics`,
  `RenderType.armorCutoutNoCull`, `ItemRenderer.getArmorFoilBuffer` — **none exist in 26.2.**
  Anything in a non-client package that took them has to lose the method.
* `net.minecraft.world.entity.projectile.AbstractArrow` moved to `…projectile.arrow.AbstractArrow`;
  `SmallFireball`/`Fireball` moved to `…projectile.hurtingprojectile.*`.

---

## 1. `Level` / `Entity` member access

| before | after | source |
|---|---|---|
| `level.isClientSide` (field) | `level.isClientSide()` — **the field is private now** | compile error `isClientSide has private access in Level` |
| `level.random` (field) | `level.getRandom()` — the field is protected | idem |
| `entity.getLevel()` / `getWorld()` | `entity.level()` (unchanged from NeoForge) | `Entity.java` |
| `isControlledByLocalInstance()` | **`isLocalInstanceAuthoritative()`** (final) | `/opt/mc-src/.../Entity.java:3568` |
| `absMoveTo(x,y,z,yRot,xRot)` | **`absSnapTo(...)`**; `moveTo` → `snapTo` | `Entity.java:1763,1784` |
| `Entity#lerpTo(...)` | **gone.** Override `getInterpolation()` returning an `InterpolationHandler` | `Entity.java:2554`, pattern from `vehicle/boat/AbstractBoat.java:64,196,228` |
| `getPickedResult(HitResult)` | **`getPickResult()`** returning `@Nullable ItemStack` | `Entity.java:3852` |
| `interact(Player, InteractionHand)` | **`interact(Player, InteractionHand, Vec3 location)`** | `Entity.java:2257` |
| `canBeCollidedWith()` | **`canBeCollidedWith(@Nullable Entity other)`** | `Entity.java:2366` |
| `causeFallDamage(float, float, DamageSource)` | **`causeFallDamage(double fallDistance, float mult, DamageSource)`** | `Entity.java:1579` |
| `Block#fallOn(level, state, pos, entity, float)` | last arg is now **`double`** | `block/Block.java:478` |
| `kill()` | **`kill(ServerLevel)`** | `Entity.java:411` |
| `spawnAtLocation(ItemStack)` | **`spawnAtLocation(ServerLevel, ItemStack)`** (`@Nullable ItemEntity`) | `Entity.java:2212-2231` |
| `state.getFriction(level, pos, entity)` | **`state.getBlock().getFriction()`** (no args) | `block/Block.java:486`, used in `LivingEntity.java:2452` |
| `Vec3` horizontal helper | `getDeltaMovement().horizontalDistanceSqr()` | `world/phys/Vec3.java:192` |
| `level.getGameRules().getBoolean(GameRules.RULE_DOENTITYDROPS)` | **`level.getGameRules().get(GameRules.ENTITY_DROPS)`** | `gamerules/GameRules.java:34,120` |
| `Level#getTimeOfDay(float)` | **gone** (day time became the world-clock system). Use `level.environmentAttributes().getDimensionValue(EnvironmentAttributes.SUN_ANGLE)` → **degrees**, equals old `getTimeOfDay()*360` | `world/attribute/EnvironmentAttributes.java:55`, usage `block/DaylightDetectorBlock.java:56` |
| `player.connection.aboveGroundVehicleTickCount = 0` | field is private → **`player.connection.resetFlyingTicks()`** | `server/network/ServerGamePacketListenerImpl.java:370` |
| `Items.WHITE_BANNER` | **`Items.BANNER.pick(DyeColor.WHITE)`** (`ColorCollection<Item>`) | `world/item/Items.java:1569`, `world/level/block/ColorCollection.java:90` |
| `itemStack.getBurnTime(RecipeType)` (NeoForge) | **`level.fuelValues().burnDuration(stack)`** | `world/level/Level.java:1107`, `block/entity/FuelValues.java:34` |
| `itemStack.hasCraftingRemainingItem()/getCraftingRemainingItem()` | **`stack.getItem().getCraftingRemainder()`** → `@Nullable ItemStackTemplate`, then `.create()` | `world/item/Item.java:284`, `world/item/ItemStackTemplate.java:79` |
| `itemStack.getEnchantmentLevel(holder)` | **`EnchantmentHelper.getItemEnchantmentLevel(holder, stack)`** | `item/enchantment/EnchantmentHelper.java:53` |
| `registryAccess().registry(key)` | **`registryAccess().lookup(key)`** → `Optional<Registry<E>>` | `core/RegistryAccess.java:19` |
| `registry.getHolder(ResourceKey)` | **`registry.get(ResourceKey)`** → `Optional<Holder.Reference<T>>` (from `HolderGetter`) | `core/HolderGetter.java:9` |
| `registry.get(Identifier)` returning `T` | **`registry.getValue(Identifier)`** (`@Nullable T`); `get(Identifier)` now returns `Optional<Holder.Reference<T>>` | `core/Registry.java:67,133` |
| `BlockTags.create(id)` | `create` is **private**; use `TagKey.create(Registries.BLOCK, id)` | `tags/BlockTags.java:260` |
| `EyeOfEnder#signalTo(BlockPos)` | **`signalTo(Vec3)`** | `projectile/EyeOfEnder.java:74` |

### Damage

```java
// 1.21.1
@Override public boolean hurt(DamageSource source, float amount) { ... }
// 26.2 — Entity#hurt is FINAL and only dispatches:
@Override public boolean hurtServer(ServerLevel level, DamageSource source, float amount) { ... }
//        public boolean hurtClient(DamageSource source)                  // optional
```
`Entity.java:1918-1931`. **`Entity#isInvulnerableTo(DamageSource)` no longer exists** — only
`protected final boolean isInvulnerableToBase(DamageSource)` (`Entity.java:3002`).
`isInvulnerableTo(ServerLevel, DamageSource)` exists **on `LivingEntity` only**
(`LivingEntity.java:3975`). For a non-living entity, write your own helper that ends in
`return isInvulnerableToBase(source);` — do not mark it `@Override`.

### Riding / passengers

| before | after |
|---|---|
| `canBeRiddenUnderFluidType(FluidType, Entity)` (NeoForge) | `boolean dismountsUnderwater()` — default `this.is(EntityTypeTags.DISMOUNTS_UNDERWATER)` (`Entity.java:2664`) |
| `positionRider(Entity, MoveFunction)` | unchanged, `Entity.MoveFunction` still at `Entity.java:4093` |
| `getDismountLocationForPassenger(LivingEntity)` | unchanged (`Entity.java:3598`) |
| `canAddPassenger` / `canRide` / `addPassenger` | unchanged, still `protected` |

---

## 2. Entity NBT: `CompoundTag` → `ValueInput` / `ValueOutput`

```java
// 1.21.1
public void readAdditionalSaveData(CompoundTag tag)
public void addAdditionalSaveData(CompoundTag tag)
// 26.2 — both are PROTECTED and ABSTRACT on Entity (Entity.java:2208/2210)
protected void readAdditionalSaveData(ValueInput input)
protected void addAdditionalSaveData(ValueOutput output)
```
Package: `net.minecraft.world.level.storage.{ValueInput,ValueOutput,TagValueInput,TagValueOutput}`.

**Exact `ValueInput` surface** (`/opt/mc-src/net/minecraft/world/level/storage/ValueInput.java`) — there is
nothing else:

```
<T> Optional<T> read(String, Codec<T>)          Optional<ValueInput> child(String)
ValueInput childOrEmpty(String)                 Optional<ValueInput.ValueInputList> childrenList(String)
ValueInput.ValueInputList childrenListOrEmpty(String)
<T> Optional<TypedInputList<T>> list(String, Codec<T>)   <T> TypedInputList<T> listOrEmpty(String, Codec<T>)
boolean getBooleanOr(String, boolean)   byte getByteOr(String, byte)   int getShortOr(String, short)
Optional<Integer> getInt(String)        int getIntOr(String, int)
long getLongOr(String, long)            Optional<Long> getLong(String)
float getFloatOr(String, float)         double getDoubleOr(String, double)
Optional<String> getString(String)      String getStringOr(String, String)
Optional<int[]> getIntArray(String)
```

**`ValueOutput`**: `store(String, Codec<T>, T)`, `storeNullable`, `putBoolean/Byte/Short/Int/Long/Float/Double/String/IntArray`,
`child(String)`, `childrenList(String)`, `list(String, Codec<T>)`, `discard`, `isEmpty`.

### Dead end that costs the most time
**`ValueInput` cannot enumerate keys.** There is no `getAllKeys()`/`keySet()`. If your old format was a
compound keyed by dynamic ids (e.g. `upgrades: { "mod:armor": {...}, "mod:seats": {...} }`) you have
two choices:

1. **Keep the format** — read the whole subtree back as a tag and enumerate it yourself:
   ```java
   CompoundTag t = input.read("upgrades", CompoundTag.CODEC).orElse(null);
   for (String key : t.keySet()) {
       ValueInput sub = TagValueInput.create(ProblemReporter.DISCARDING, registryAccess(), t.getCompoundOrEmpty(key));
   }
   // writing is fine with the normal API:
   ValueOutput o = output.child("upgrades");
   o.child(idString);   // one child per entry
   ```
   Do this when another file (item tooltips, recipes) still parses the raw `CompoundTag`.
2. Switch to a **list of children** with an explicit `id` field:
   `output.childrenList("x").addChild()` / `for (ValueInput c : input.childrenListOrEmpty("x"))`.
   `childrenList` + `putString("id",…)` + `child("nbt")` produces a `ListTag` of compounds — byte-identical
   to a hand-written `ListTag` of `{id:…, nbt:…}`.

### CompoundTag ↔ ValueInput/Output bridges
```java
TagValueOutput out = TagValueOutput.createWithContext(ProblemReporter.DISCARDING, registryAccess());
addAdditionalSaveData(out);
CompoundTag tag = out.buildResult();                                   // TagValueOutput.java:27,151

ValueInput in = TagValueInput.create(ProblemReporter.DISCARDING, registryAccess(), tag); // TagValueInput.java:40
entity.load(in);                                                       // Entity.java:2139 — takes ValueInput now
```
`ProblemReporter.DISCARDING` is at `/opt/mc-src/net/minecraft/util/ProblemReporter.java:18`.

Because `readAdditionalSaveData` is **protected** in 26.2 (it was public in 1.21.1), anything outside the
entity (e.g. an item that stores entity NBT in a data component) needs a public bridge method on the
entity — there is no other way in.

### ItemStack in NBT
`ItemStack.save(...)` / `ItemStack.parseOptional(...)` are gone. Use the codecs:
`ItemStack.CODEC`, `ItemStack.OPTIONAL_CODEC` (`world/item/ItemStack.java:122,123`) with
`output.store(name, ItemStack.CODEC, stack)` / `input.read(name, ItemStack.CODEC)`.
Stream side is unchanged: `ItemStack.OPTIONAL_STREAM_CODEC` (`ItemStack.java:125`).

### Container serialisation
`SimpleContainer` has ready-made helpers (`/opt/mc-src/net/minecraft/world/SimpleContainer.java:198,206`):
```java
container.storeAsItemList(output.list("Items", ItemStack.CODEC));
container.fromItemList(input.listOrEmpty("Items", ItemStack.CODEC));
```

---

## 3. Synched data & spawn

```java
@Override protected void defineSynchedData(SynchedEntityData.Builder builder) {
    builder.define(HEALTH, 10);
}
```
Unchanged from NeoForge 1.21.1. Gotcha found the hard way:

| accessor | 1.21.1 type | 26.2 type |
|---|---|---|
| `EntityDataSerializers.QUATERNION` | `EntityDataSerializer<Quaternionf>` | **`EntityDataSerializer<Quaternionfc>`** (`network/codec/ByteBufCodecs.java:191`) |

So the field must be `EntityDataAccessor<Quaternionfc>`; `entityData.get(Q)` returns `Quaternionfc`,
wrap it (`new Quaternionf(entityData.get(Q))`) where you need the mutable class.
Same for the stream codec: `ByteBufCodecs.QUATERNIONF` is `StreamCodec<ByteBuf, Quaternionfc>` —
adapt with `ByteBufCodecs.QUATERNIONF.map(Quaternionf::new, q -> q)`
(`StreamCodec#map` at `network/codec/StreamCodec.java:69`).

`EntityType#create(Level)` → **`create(Level, EntitySpawnReason)`**
(`/opt/mc-src/net/minecraft/world/entity/EntitySpawnReason.java`; values incl. `MOB_SUMMONED`,
`TRIGGERED`, `COMMAND`). It returns `@Nullable T`.

`EntityType#updateInterval()` still exists (`EntityType.java:422`).

---

## 4. Networking: NeoForge payloads → Fabric

Everything NeoForge-side is gone: `IPayloadContext`, `PayloadRegistrar`,
`RegisterPayloadHandlersEvent`, `PacketDistributor`, `ConnectionType`,
`registrar.playToServer/playToClient`.

The payload record itself is **unchanged** — `CustomPacketPayload` + `CustomPacketPayload.Type<T>` +
a `StreamCodec` are vanilla. Only registration, dispatch and the handler signature change.

### Registration (common entrypoint, runs on both sides)
```java
import net.fabricmc.fabric.api.networking.v1.PayloadTypeRegistry;

PayloadTypeRegistry.serverboundPlay().register(MyC2S.TYPE, MyC2S.STREAM_CODEC);
PayloadTypeRegistry.clientboundPlay().register(MyS2C.TYPE, MyS2C.STREAM_CODEC);
```
Note the names: **`serverboundPlay()` / `clientboundPlay()`**, *not* `playC2S()/playS2C()`.
Also available: `serverboundConfiguration()`, `clientboundConfiguration()`, and
`registerLarge(TYPE, CODEC, int|IntSupplier)` for oversized payloads.
`B` is `RegistryFriendlyByteBuf` for play, so a `StreamCodec<ByteBuf, T>` fits (`? super B`).
(verified with `javap` on `fabric-networking-api-v1-6.3.3+72073ef09e.jar`)

### Receivers
```java
// server (common entrypoint)
ServerPlayNetworking.registerGlobalReceiver(MyC2S.TYPE, (payload, context) -> {
    ServerPlayer player = context.player();      // Context: server(), player(), responseSender()
    ...                                          // already on the main thread — no enqueueWork()
});

// client (client entrypoint ONLY)
ClientPlayNetworking.registerGlobalReceiver(MyS2C.TYPE, (payload, context) -> {
    Minecraft mc = context.client();             // Context: client(), player(), responseSender()
});
```
`context.enqueueWork(...)` has no Fabric equivalent and is not needed — handlers already run on the
game thread.

### Sending
```java
ServerPlayNetworking.send(serverPlayer, payload);   // S2C
ClientPlayNetworking.send(payload);                 // C2S
```

### `PacketDistributor.sendToPlayersTrackingEntity(entity, payload)` replacement
```java
import net.fabricmc.fabric.api.networking.v1.PlayerLookup;
for (ServerPlayer p : PlayerLookup.tracking(entity)) ServerPlayNetworking.send(p, payload);
```
`PlayerLookup` also has `all(server)`, `level(serverLevel)`, `tracking(ServerLevel, ChunkPos|BlockPos)`,
`tracking(BlockEntity)`, `around(level, Vec3|Vec3i, radius)`. **`PlayerLookup.tracking` requires a
server-side entity** — guard every call with `!level().isClientSide()`.

### `IEntityWithComplexSpawn` (extra spawn data) — no Fabric equivalent
Replace with your own S2C payload fired from `EntityTrackingEvents.START_TRACKING`:
```java
import net.fabricmc.fabric.api.networking.v1.EntityTrackingEvents;

EntityTrackingEvents.START_TRACKING.register((entity, player) -> {
    if (entity instanceof MyEntity e) ServerPlayNetworking.send(player, MySpawnPacket.create(e));
});
```
(`EntityTrackingEvents.StartTracking#onStartTracking(Entity, ServerPlayer)`; also `STOP_TRACKING`.)
It fires after the vanilla spawn packet, so the client entity already exists — still null-check it.

### Dead end: writing "the rest of the buffer" lazily
The NeoForge trick of `new RegistryFriendlyByteBuf(outgoingBuf, access, ConnectionType.NEOFORGE)` inside
`StreamCodec#encode` and then writing directly into the live outgoing buffer does not port
(`ConnectionType` is NeoForge-only and Fabric's encoder does not hand you the frame). Serialise
eagerly into a `byte[]` instead:
```java
RegistryFriendlyByteBuf buf = new RegistryFriendlyByteBuf(Unpooled.buffer(), entity.registryAccess());
writeMyStuff(buf);
byte[] data = new byte[buf.readableBytes()];
buf.readBytes(data);
buf.release();
// record component: byte[] data, codec ByteBufCodecs.BYTE_ARRAY (ByteBufCodecs.java:150)
// on the client:
new RegistryFriendlyByteBuf(Unpooled.wrappedBuffer(data), mc.level.registryAccess());
```
`RegistryFriendlyByteBuf` is now a **2-arg** constructor `(ByteBuf, RegistryAccess)`
(`/opt/mc-src/net/minecraft/network/RegistryFriendlyByteBuf.java:10`).

`StreamCodec.composite` exists for 1–12 field pairs (`StreamCodec.java:118…543`).

### Dedicated-server safety (what `runServer` catches)
Put every client-touching receiver body in a **separate class** referenced only from the
client-registration method:
```java
public static void register()       { /* payload types + server receivers only */ }
public static void registerClient() { MyClientNetworking.register(); }   // lazily resolved
```
Same rule for any call into a client class from shared code: keep the reference inside a method that
only runs when `level().isClientSide()`, never in a field type or a method signature — JVM constant-pool
resolution is lazy per call site, but signatures are resolved at class verification.

---

## 5. Capabilities (contract C4) — what to write instead

| NeoForge | replacement | notes |
|---|---|---|
| `ItemStackHandler` / `IItemHandler` | `net.minecraft.world.SimpleContainer` | `getItem/setItem/removeItem/getContainerSize/addListener`; already has `storeAsItemList`/`fromItemList` |
| `SlotItemHandler` | plain `net.minecraft.world.inventory.Slot(Container, idx, x, y)` | `Slot` and `DataSlot` are unchanged |
| `IEnergyStorage` / `EnergyStorage` | plain field/class owned by the upgrade | do **not** pull in Team Reborn Energy |
| `FluidTank` / `FluidStack` | small local class holding `Fluid fluid; int amount;` | do **not** pull in the Transfer API |
| `stack.getCapability(Capabilities.FluidHandler.ITEM)` | no equivalent — vanilla-bucket-only fallback: `item instanceof BucketItem` + match `fluid.getBucket() == item` (`world/level/material/Fluid.java:55`); `BucketItem.content` is **protected**, so you cannot read it without an access widener |
| `entity.getCap(cap)` / `BaseCapability` | delete | nothing to expose to other mods |

## 6. Menus with extra open data

`Player#openMenu(MenuProvider, Consumer<FriendlyByteBuf>)` (NeoForge) does not exist; vanilla only has
`OptionalInt openMenu(@Nullable MenuProvider)` (`entity/player/Player.java:803`).
Fabric supplies the missing half in **`fabric-menu-api-v1`**:

```java
// registration (Agent A side)
new ExtendedMenuType<MyMenu, Integer>(MyMenu::new, ByteBufCodecs.VAR_INT)   // MyMenu(int id, Inventory inv, Integer data)

// opening (entity/upgrade side)
player.openMenu(new ExtendedMenuProvider<Integer>() {
    @Override public Integer getScreenOpeningData(ServerPlayer p) { return entity.getId(); }
    @Override public Component getDisplayName()                   { return entity.getName(); }
    @Override public AbstractContainerMenu createMenu(int id, Inventory inv, Player pl) { ... }
});
```
`net.minecraft.world.MenuProvider` already `extends FabricMenuProvider` in the patched sources, and
`ExtendedMenuProvider<D> extends MenuProvider`. `MenuType`'s `(MenuSupplier, FeatureFlagSet)`
constructor is **private** in 26.2 — non-extended menus need another route.

## 7. Misc dead ends burned

* `Entity#getWorld` / `getEntityWorld` — yarn advice; NeoForge sources already use `level()`, keep it.
* `state.getFriction(level, pos, entity)` — the 3-arg form was a NeoForge extension; vanilla only has
  `Block#getFriction()`.
* `Level#explode(Entity, double,double,double,float, Level.ExplosionInteraction)` still exists
  (`Level.java:581`) — no change needed.
* `ServerLevel#sendParticles(T, double x,y,z, int count, double dx,dy,dz, double speed)` unchanged
  (`ServerLevel.java:1304`).
* `Level#addAlwaysVisibleParticle(options, boolean overrideLimiter, x,y,z, dx,dy,dz)` unchanged
  (`Level.java:520`); the 7-arg no-boolean form also exists.
* `EntitySelector.pushableBy(entity)`, `Stats.PLAY_RECORD`, `SoundEvents.ENDER_EYE_LAUNCH`,
  `StructureTags.EYE_OF_ENDER_LOCATED`, `ServerLevel#findNearestMapStructure` — all unchanged.
* `ArrowItem#createArrow(Level, ItemStack, LivingEntity, @Nullable ItemStack firedFromWeapon)` and
  `AbstractArrow.pickup` (public field) — unchanged, only the package moved.


---

# Приложение: находки порта Domum Ornamentum (NeoForge 26.1 → Fabric 26.2)

Всё ниже добавлено по итогам порта Domum Ornamentum и проверено на нём: сборка, датаген
и выделенный сервер зелёные, клиент проверен вручную. Каждая запись подтверждена ссылкой
на `/opt/mc-src` или на строку рабочего 26.2-мода. Материал не дублирует то, что было
в ките выше, — это только новое.



Только то, чего **не было** в `PORT-ANY-MOD-26.2.md` / `NOTES-A.md` / `NOTES-B.md`.
Всё подтверждено грепом по `/opt/mc-src` (декомпил 26.2) или `javap` по jar'ам fabric-api.

---

## 0. Класспас для проверки без Gradle: нужен **инъецированный** jar, а не `minecraft-merged-deobf`

- **Было:** —
- **Стало:** для быстрой javac-проверки пакета есть два разных minecraft-jar'а, и один из них врёт:
  * `~/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.2/minecraft-merged-deobf-26.2.jar`
    — **без** interface injection от Fabric API;
  * `<project>/.gradle/loom-cache/minecraftMaven/net/minecraft/minecraft-merged-<hash>/26.2/minecraft-merged-<hash>-26.2.jar`
    — **с** инъекциями, это то, чем реально компилирует Loom.
- **Подтверждено:** `javap -cp <deobf>.jar net.minecraft.world.item.crafting.RecipeAccess` → `interface RecipeAccess {…}`;
  `javap -cp <project loom-cache>.jar …RecipeAccess` → `interface RecipeAccess extends net.fabricmc.fabric.api.recipe.v1.FabricRecipeAccess`.
- **Комментарий:** на «плохом» jar'е javac даёт **ложные** ошибки вида
  `cannot find symbol: method getSynchronizedRecipes() location: interface RecipeAccess` и
  `method does not override … getRenderData()`. Это не ошибки порта. `/opt/mc-src` декомпилирован
  из инъецированного jar'а и потому прав — если `/opt/mc-src` показывает `extends Fabric…`, а javac
  ругается, виноват класспас.

---

## 1. Рендер-данные блок-сущности: `ModelData` → `RenderDataBlockEntity#getRenderData()`

- **Было (NeoForge):** `BlockEntity#getModelData()` → `ModelData.builder().with(ModelProperty, value).build()`,
  плюс `BlockEntity#requestModelDataUpdate()` и `BlockEntity#onLoad()`.
- **Стало (26.2):** ванильный `BlockEntity` **уже** реализует
  `net.fabricmc.fabric.api.blockgetter.v2.RenderDataBlockEntity` (инъекция из `fabric-block-getter-api-v2`).
  Единственный метод — `default Object getRenderData()`. Никакого key/value-контейнера нет:
  отдаёшь свой объект как есть, модель на другой стороне его кастует.
  `requestModelDataUpdate()` и `onLoad()` **не существуют** — своя перерисовка делается вручную:
  `level.setBlocksDirty(worldPosition, Blocks.AIR.defaultBlockState(), getBlockState())` под `level.isClientSide()`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/entity/BlockEntity.java:8,43`;
  `javap -cp fabric-block-getter-api-v2-2.0.7+*.jar net.fabricmc.fabric.api.blockgetter.v2.RenderDataBlockEntity`.
- **Комментарий:** `ModelProperty<T>` больше не нужен как ключ — целый класс модовых «properties»
  умирает вместе с `ModelData`. Договоритесь между агентом блоков и агентом моделей о **типе**
  возвращаемого объекта: он и есть весь контракт.

---

## 2. `BlockEntity#saveToItem` удалён; `BlockItem.setBlockEntityData` принимает `TagValueOutput`

- **Было (1.21.1/26.1):** `blockEntity.saveToItem(stack, provider)`;
  `BlockItem.setBlockEntityData(stack, type, CompoundTag)`;
  `BlockEntity#removeComponentsFromTag(CompoundTag)`.
- **Стало (26.2):**
  ```java
  TagValueOutput out = TagValueOutput.createWithContext(ProblemReporter.DISCARDING, registries);
  blockEntity.saveCustomOnly(out);
  blockEntity.removeComponentsFromTag(out);          // теперь принимает ValueOutput
  BlockItem.setBlockEntityData(stack, blockEntity.getType(), out);
  stack.applyComponents(blockEntity.collectComponents());
  ```
  Для простого случая (у BE только компоненты) хватает одной строки
  `stack.applyComponents(blockEntity.collectComponents())`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/item/BlockItem.java:206`;
  эталон целиком — `/opt/mc-src/net/minecraft/server/network/ServerGamePacketListenerImpl.java:708-716`;
  однострочник — `/opt/mc-src/net/minecraft/world/level/block/ShulkerBoxBlock.java:113`.
- **Комментарий:** `DataComponents.BLOCK_ENTITY_DATA` теперь **не** `CustomData`, а
  `TypedEntityData<BlockEntityType<?>>` (`/opt/mc-src/net/minecraft/core/component/DataComponents.java:267`).
  Читать сырой тег — `typedEntityData.getUnsafe()` / `copyTagWithoutId()`.

---

## 3. Список компаундов в NBT блок-сущности сохраняется байт-в-байт через `childrenList`

- **Было:** `ListTag` из `{offset:int, bool:byte}` + `compound.put("offsets", listTag)`.
- **Стало:**
  ```java
  ValueOutput.ValueOutputList list = output.childrenList("offsets");
  ValueOutput e = list.addChild(); e.putInt("offset", …); e.putBoolean("bool", …);
  // чтение
  for (ValueInput e : input.childrenListOrEmpty("offsets")) { e.getIntOr("offset", -1); e.getBooleanOr("bool", false); }
  ```
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/storage/ValueOutput.java:36,50-56`,
  `.../ValueInput.java:20-22,61-65`.
- **Комментарий:** совместимость со старыми сохранениями сохраняется полностью — это не «новый формат»,
  а тот же `ListTag` компаундов. Не поддавайтесь соблазну переписать на `output.list(name, Codec)`:
  тот пишет список **значений кодека**, формат другой, старые миры отвалятся молча.

---

## 4. `Recipe#placementInfo()` не имеет права вернуть `null` — иначе рецепты падают на загрузке датапака

- **Было:** в 1.21.1 такого метода не было; при механическом порте на 26.x его добавляют
  «заглушкой» `return null` (так сделано и в апстримовом `port/26.1` Domum Ornamentum).
- **Стало (26.2):** `RecipeManager#finalizeRecipeLoading` дёргает
  `recipe.placementInfo().isImpossibleToPlace()` **для каждого** загруженного рецепта.
  `null` → `NullPointerException` внутри `forEach` → падает весь этап загрузки рецептов.
  Правильно: `PlacementInfo.NOT_PLACEABLE` (для рецептов не из книги) + `isSpecial() → true`,
  иначе в лог сыплется `Recipe … can't be placed due to empty ingredients and will be ignored`
  по строке на рецепт (у DO это ~700 строк).
  `recipeBookCategory()` тоже не должен быть `null` — берите `RecipeBookCategories.CRAFTING_MISC`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/item/crafting/RecipeManager.java:98,230,237`;
  `/opt/mc-src/net/minecraft/world/item/crafting/PlacementInfo.java:11,71`;
  `/opt/mc-src/net/minecraft/world/item/crafting/RecipeBookCategories.java:10`.
- **Комментарий:** близкий родственник ловушки с `ItemStackTemplate`: симптом снаружи почти тот же
  («рецептов нет»), но здесь в консоли всё-таки будет NPE. Проверять обязательно **до** `runServer`.

### Про `ItemStackTemplate` — когда ловушка НЕ применяется
`ShapedRecipe` в 26.2 действительно хранит результат как `ItemStackTemplate`
(`/opt/mc-src/net/minecraft/world/item/crafting/ShapedRecipe.java:11,24,41,71`), и `ItemStack.CODEC`
в поле `result` собственного рецепта — реальная мина. Но если рецепт **не хранит `ItemStack`**,
а хранит `Holder<Block>`/`Identifier` + `count` + `DataComponentPatch` и собирает стак в `assemble()`
уже в рантайме, менять нечего: `BuiltInRegistries.BLOCK.holderByNameCodec()` и
`DataComponentPatch.CODEC` при загрузке датапака валидны.

---

## 5. Свои рецепты, читаемые из меню на клиенте: `RecipeAccess#getSynchronizedRecipes()`

- **Было (NeoForge/1.21.1):** `level.getRecipeManager().getRecipesFor(TYPE, input, level)` работает на обеих сторонах.
- **Стало (26.2 + Fabric):** `Level#getRecipeManager()` удалён; `Level#recipeAccess()` даёт `RecipeAccess`,
  и только серверный экземпляр — `RecipeManager`. Полный список рецептов на клиенте даёт
  `fabric-recipe-api-v1`:
  ```java
  // регистрация (один раз, рядом с регистрацией сериализатора)
  RecipeSynchronization.synchronizeRecipeSerializer(MY_SERIALIZER);
  // использование, обе стороны
  Stream<RecipeHolder<T>> s = level.recipeAccess().getSynchronizedRecipes()
        .<MyInput, MyRecipe>getAllMatches(MY_TYPE, input, level);
  ```
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/Level.java:1064`,
  `/opt/mc-src/net/minecraft/world/item/crafting/RecipeAccess.java:3,6`;
  `javap` на `fabric-recipe-api-v1-9.0.20+*.jar`:
  `net.fabricmc.fabric.api.recipe.v1.sync.RecipeSynchronization#synchronizeRecipeSerializer(RecipeSerializer<?>)`,
  `net.fabricmc.fabric.api.recipe.v1.sync.SynchronizedRecipes#getAllMatches(RecipeType,I,Level)`.
- **Комментарий:** пакеты — `…recipe.v1.sync.*` (в NOTES-A они указаны как `…recipe.v1.*`, это неточность);
  `FabricRecipeAccess`/`FabricRecipeManager` лежат в `…recipe.v1`, а `RecipeSynchronization`/`SynchronizedRecipes` —
  в `…recipe.v1.sync`. `getAllMatches` возвращает `Stream`, не `List` (`getRecipesFor` возвращал
  изменяемый список) — нужен `.collect(Collectors.toCollection(ArrayList::new))`, если потом сортируете.
  Без `synchronizeRecipeSerializer` клиент рецептов не увидит и меню будет пустым — молча.

---

## 6. `RecipeHolder#id()` — это `ResourceKey<Recipe<?>>`, а датаген принимает только ключ

- **Было:** `RecipeHolder::id` → `Identifier`; `RecipeOutput#accept(Identifier, Recipe<?>, AdvancementHolder)`.
- **Стало (26.2):** `RecipeHolder#id()` → `ResourceKey<Recipe<?>>`; путь берётся как `holder.id().identifier()`.
  То же в датагене:
  `RecipeOutput#accept(ResourceKey<Recipe<?>>, Recipe<?>, @Nullable AdvancementHolder)`,
  `RecipeUnlockedTrigger.unlocked(ResourceKey<Recipe<?>>)`,
  `AdvancementRewards.Builder.recipe(ResourceKey<Recipe<?>>)`.
  А вот `Advancement.Builder#build(...)` по-прежнему берёт **`Identifier`**.
- **Подтверждено:** `/opt/mc-src/net/minecraft/data/recipes/RecipeOutput.java:11`,
  `/opt/mc-src/net/minecraft/advancements/triggers/RecipeUnlockedTrigger.java:23`,
  `/opt/mc-src/net/minecraft/advancements/AdvancementRewards.java:116`,
  `/opt/mc-src/net/minecraft/advancements/Advancement.java:215`.
- **Комментарий:** конвертация — `ResourceKey.create(Registries.RECIPE, identifier)`. И общий рефлекс 26.2:
  **`ResourceKey#location()` переименован в `ResourceKey#identifier()`** — задевает любой
  `builtInRegistryHolder().key().location()`.

---

## 7. Блочные хуки, которые были NeoForge-only и в 26.2 не имеют замены

| NeoForge (1.21.1/26.1) | 26.2 | что делать |
|---|---|---|
| `Block#getExplosionResistance(BlockState, BlockGetter, BlockPos, Explosion)` | только `Block#getExplosionResistance()` без аргументов (`Block.java:445`) | позиции нет → значение блок-сущности недоступно; §10 |
| `Block#getSoundType(BlockState, LevelReader, BlockPos, Entity)` | только `BlockBehaviour#getSoundType(BlockState)` (`BlockBehaviour.java:404`) | то же |
| `Block#rotate(BlockState, LevelAccessor, BlockPos, Rotation)` | только `rotate(BlockState, Rotation)` (`BlockBehaviour.java:255`) | то же |
| `IBlockExtension#shouldDisplayFluidOverlay(...)` | нет нигде (`grep -rn shouldDisplayFluidOverlay /opt/mc-src` → 0) | миксин в `LiquidBlockRenderer` или §10 |
| `IItemExtension#verifyComponentsAfterLoad(ItemStack)` | нет ни в ванили, ни в `FabricItem` | своя DFU-логика теряет вызывающую сторону; §10 |

`fabric-block-api-v1` даёт **только** `FabricBlock#getAppearance(...)` — на эти дыры он не отвечает
(javap на `fabric-block-api-v1-3.0.3+*.jar`: `FabricBlock`, `FabricBlockState`, `FabricBlock$FabricProperties`,
`BlockFunctionalityTags` — и всё).
`fabric-item-api-v1`'s `FabricItem` — тоже мимо: `allowComponentsUpdateAnimation`,
`allowContinuingBlockBreaking`, `getCraftingRemainder`, `canBeEnchantedWith`, `getCreatorNamespace`.

---

## 8. Ванильные сигнатуры блоков/предметов, изменившиеся в 26.2 (сверх того, что в ките)

| было | стало | источник |
|---|---|---|
| `getCloneItemStack(BlockState, HitResult, LevelReader, BlockPos, Player)` (NeoForge) | `protected ItemStack getCloneItemStack(LevelReader level, BlockPos pos, BlockState state, boolean includeData)` | `BlockBehaviour.java:408` |
| `updateShape(BlockState, Direction, BlockState, LevelAccessor, BlockPos, BlockPos)` | `protected BlockState updateShape(BlockState, LevelReader, ScheduledTickAccess, BlockPos, Direction directionToNeighbour, BlockPos neighbourPos, BlockState neighbourState, RandomSource)` | `BlockBehaviour.java:148`, эталон `StairBlock.java:112-129` |
| `level.scheduleTick(pos, Fluids.WATER, …)` внутри `updateShape` | `ticks.scheduleTick(pos, Fluids.WATER, Fluids.WATER.getTickDelay(level))` — планировщик теперь отдельный параметр | `StairBlock.java:123` |
| `net.minecraft.world.level.block.state.properties.DirectionProperty` | **класса нет** → `EnumProperty<Direction>` | `HorizontalDirectionalBlock.java:11`, `BlockStateProperties.java:53-57` |
| `WallBlock.NORTH_WALL/EAST_WALL/SOUTH_WALL/WEST_WALL` | на `WallBlock` они называются `NORTH/EAST/SOUTH/WEST`; исходные — `BlockStateProperties.NORTH_WALL` и т.д. | `WallBlock.java:36-39` |
| `BlockBehaviour.Properties#noCollission()` (две `s`) | `noCollision()` | `BlockBehaviour.java:1080` |
| `Block#onRemove(BlockState, Level, BlockPos, BlockState, boolean)` | `protected void affectNeighborsAfterRemoval(BlockState, ServerLevel, BlockPos, boolean movedByPiston)` — **`ServerLevel`**, не `Level` | `BlockBehaviour.java:173` |
| `LevelHeightAccessor#getMinBuildHeight()` | `getMinY()` | `LevelHeightAccessor.java:9` |
| `LevelReader#getShade(Direction, boolean)` | **удалён** | — |
| `LevelReader` — новый абстрактный метод | `EnvironmentAttributeReader environmentAttributes()`; заглушка — `EnvironmentAttributeReader.EMPTY` | `LevelReader.java:222`, `world/attribute/EnvironmentAttributeReader.java:10` |
| `ChunkAccess#setUnsaved(boolean)` | `markUnsaved()` | `ChunkAccess.java:263` |
| `Slot#getSlotIndex()` | `getContainerSlot()` (поле `slot` приватное) | `world/inventory/Slot.java:11,159` |
| `ItemStack#onCraftedBy(Level, Player, int)` | `onCraftedBy(Player, int)` | `ItemStack.java:721` |
| `Items.WHITE_CONCRETE_POWDER` (и прочие цветные) | `Items.CONCRETE_POWDER.pick(DyeColor.WHITE)` — `ColorCollection<Item>`; `DyeColor` лежит в `net.minecraft.world.item` | `Items.java:643`, `block/ColorCollection.java:90` |
| `Item#appendHoverText(ItemStack, TooltipContext, List<Component>, TooltipFlag)` | `appendHoverText(ItemStack, Item.TooltipContext, TooltipDisplay, Consumer<Component>, TooltipFlag)` — `tooltip.add(x)` → `tooltip.accept(x)` | `Item.java:323` (импорты `Item.java:11,75`) |

`ScheduledTickAccess` лежит в **`net.minecraft.world.level`**, а не в `net.minecraft.world.ticks`
(`/opt/mc-src/net/minecraft/world/level/ScheduledTickAccess.java`).

---

## 9. `DataComponentPatch.Builder` нельзя наследовать

- **Было:** мод расширял `DataComponentPatch.Builder`, дополняя его методом `update(...)`; работало,
  потому что NeoForge access-transformer'ом открывал конструктор и поле `map`.
- **Стало (26.2):** `private Builder()` и `private final Reference2ObjectMap<…> map`.
  Fabric-эквивалента AT нет (accesswidener можно, но ради одного билдера не стоит).
  Дешевле держать собственную `Map<DataComponentType<?>, Optional<?>>` и собирать
  `DataComponentPatch.builder()` только в `build()`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/core/component/DataComponentPatch.java:243-274`.

---

## 10. Обёртка «`DataComponentType<T>` + `Supplier<DataComponentType<T>>`» ломает перегрузки

- **Было:** приём из NOTES-A §1 — регистрировать компонент классом, который реализует и
  `DataComponentType<T>`, и `Supplier<DataComponentType<T>>`, чтобы работали и `X`, и `X.get()`.
- **Стало:** приём рабочий, но у него есть побочка: любой ваш **свой** класс, где рядом лежат
  `set(DataComponentType<T>, T)` и `set(Supplier<DataComponentType<T>>, T)`, начинает давать
  `reference to set is ambiguous` — обе перегрузки применимы к обёртке.
- **Комментарий:** лечится удалением `Supplier`-перегрузок (обёртка делает их лишними).
  Проверьте это во всех своих билдерах/хелперах, а не только там, где компилятор ткнул первым.

---

## 11. Сеть: `PacketDistributor` → `PlayerLookup` + `ServerPlayNetworking`, и где взять `MinecraftServer`

- **Было:** `PacketDistributor.sendToPlayer / sendToPlayersInDimension / sendToPlayersNear /
  sendToAllPlayers / sendToPlayersTrackingEntity(AndSelf) / sendToPlayersTrackingChunk / sendToServer`.
- **Стало (26.2 + Fabric):**

  | NeoForge | Fabric |
  |---|---|
  | `sendToPlayer(p, m)` | `ServerPlayNetworking.send(p, m)` |
  | `sendToPlayersInDimension(level, m)` | `PlayerLookup.level(level)` |
  | `sendToPlayersNear(level, excluded, x,y,z,r, m)` | `PlayerLookup.around(level, new Vec3(x,y,z), r)` + вручную отфильтровать `excluded` |
  | `sendToAllPlayers(m)` | `PlayerLookup.all(server)` — **нужен `MinecraftServer`** |
  | `sendToPlayersTrackingEntity(e, m)` | `PlayerLookup.tracking(e)` |
  | `sendToPlayersTrackingEntityAndSelf(e, m)` | `PlayerLookup.tracking(e)` + сам `e`, если это `ServerPlayer` |
  | `sendToPlayersTrackingChunk(level, chunkPos, m)` | `PlayerLookup.tracking(level, chunkPos)` |
  | `sendToServer(m)` | `ClientPlayNetworking.send(m)` — **клиентский класс** |

- **`ServerLifecycleHooks.getCurrentServer()` замены не имеет.** Дешёвая: статическое поле,
  заполняемое из `ServerLifecycleEvents.SERVER_STARTING` и обнуляемое в `SERVER_STOPPED`
  (`fabric-lifecycle-events-v1`, `net.fabricmc.fabric.api.event.lifecycle.v1.ServerLifecycleEvents`).
- **`FMLEnvironment.production`** → `!FabricLoader.getInstance().isDevelopmentEnvironment()`
  (`net.fabricmc.loader.api.FabricLoader`, ядро лоадера, отдельная зависимость не нужна).
- **Комментарий по дедикейт-серверу:** `ClientPlayNetworking` можно звать из **тела** default-метода
  общего интерфейса — константы пула резолвятся лениво per call site. Нельзя — в сигнатуре, типе поля
  или `implements`. Держите один клиентский класс с единственным `sendToServer(payload)`,
  на который ссылается общий `IServerboundDistributor#sendToServer()`.
- **Подтверждено:** `javap` на `fabric-networking-api-v1-6.3.3+*.jar` (`PlayerLookup`, `ServerPlayNetworking`),
  `fabric-lifecycle-events-v1-4.1.3+*.jar` (`ServerLifecycleEvents`).

---

## 12. Приёмник пакета вместо `IPayloadContext`

- **Было:** `void onExecute(IPayloadContext ctx)` + `ctx.player()` + `ctx.enqueueWork(…)`.
- **Стало:** `ServerPlayNetworking.registerGlobalReceiver(TYPE, (payload, context) -> …)`,
  `context.player()` → `ServerPlayer`. `enqueueWork` не нужен и не существует: хендлер уже на
  игровом потоке. Сам `record … implements CustomPacketPayload` + `Type` + `StreamCodec` не меняется
  вообще — это ванильное API.
- **Комментарий:** удобно оставить прежний метод `onExecute`, поменяв параметр с `IPayloadContext`
  на `@Nullable Player`, — тогда тело обработчика не трогается.

---

## 13. Мелочи, стоившие времени

* `CompoundTag#contains(String, int type)` (двухаргументный, с типом) удалён; остался
  `contains(String)`. Типизированная проверка выражается через `Optional`-геттеры:
  `tag.getString(k).ifPresent(...)`, `tag.getCompound(k).ifPresent(...)`
  (`/opt/mc-src/net/minecraft/nbt/CompoundTag.java:275,331,351`).
* `CustomData#getUnsafe()` больше нет — есть `copyTag()`. `getUnsafe()` остался у `TypedEntityData`
  (`/opt/mc-src/net/minecraft/world/item/component/TypedEntityData.java:171`).
* `net.minecraft.Util` → **`net.minecraft.util.Util`** (`Util.copyAndPut` на месте, `Util.java:1181`).
* `ResultContainer#awardUsedRecipes(Player, List<ItemStack>)` жив, но приехал из интерфейса
  `RecipeCraftingHolder` (`/opt/mc-src/net/minecraft/world/inventory/RecipeCraftingHolder.java:17`),
  а не с самого `ResultContainer` — на компиляцию не влияет, но при грепе легко решить, что метод исчез.
* `Recipe#assemble(T input)` — без `HolderLookup.Provider`; `Recipe#getResultItem(...)` удалён
  из интерфейса совсем. Если меню показывает «что получится» без входов — оставьте свой метод
  с тем же именем, но **без** `@Override`.
* `RecipeSerializer` — record, а не интерфейс: класс `XxxRecipeSerializer implements RecipeSerializer<…>`
  превращается в фабрику `static RecipeSerializer<T> create()`.
* Меню, открываемое без дополнительных данных, **не требует** `ExtendedMenuType`: сервер открывает его
  через `state.getMenuProvider(level, pos)` → `player.openMenu(provider)`, клиентский конструктор
  `(int, Inventory)` подходит под обычный `MenuType`. `ExtendedMenuType` нужен только там, где
  NeoForge писал `player.openMenu(provider, buf -> …)`.
* Ловушка порядка при `sed`-переименовании `DirectionProperty` → `EnumProperty<Direction>`:
  в файле после этого нужен импорт `net.minecraft.core.Direction`, а он там был не всегда
  (`DirectionProperty` его не требовал).
* Клиентская сторона обновления блок-сущности: `ClientPacketListener#handleBlockEntityData` зовёт
  `blockEntity.loadWithComponents(TagValueInput.create(...))`
  (`/opt/mc-src/net/minecraft/client/multiplayer/ClientPacketListener.java:1476`) — то есть NeoForge-овские
  `onDataPacket(Connection, ValueInput)` и `handleUpdateTag(ValueInput)` можно просто удалить,
  штатного `loadAdditional(ValueInput)` достаточно.
