# NOTES-A — NeoForge 1.21.1 → Fabric 26.2: core / registration / containers / recipes / data

Recipe sheet from Agent A's pass on Simple Planes. **Every entry below was verified** against the
decompiled sources at `/opt/mc-src/…` or against a working Fabric 26.2 mod on disk
(`/home/user/Fabric-LuckyTNTMod/{TntLib,tntmod}`). Paths are given per row.

---

## 0. The one that invalidates the brief: `ResourceLocation` is now `Identifier`

`net.minecraft.resources.ResourceLocation` **does not exist in 26.2**. It was renamed to
`net.minecraft.resources.Identifier` in Mojang's own mappings.

| check | result |
|---|---|
| `ls /opt/mc-src/net/minecraft/resources/` | `Identifier.java`, no `ResourceLocation.java` |
| `/opt/mc-src/net/minecraft/resources/Identifier.java:18` | `public final class Identifier implements Comparable<Identifier>` |
| `Fabric-LuckyTNTMod/TntLib/src/main/java/luckytntlib/registry/RegistryHelper.java:37` | `import net.minecraft.resources.Identifier;` |
| `/home/user/desolation/src/main/java/raltsmc/desolation/world/structure/AshTinkerBaseStructure.java:5` | `import net.minecraft.resources.Identifier;` |

`Identifier` is **not** a Yarn name here — Mojang adopted it. `ResourceKey` kept its name.
Static factories are unchanged: `Identifier.fromNamespaceAndPath(ns, path)`, `Identifier.parse(s)`,
`Identifier.withDefaultNamespace(s)`, `Identifier.tryParse(s)`, `Identifier.CODEC`,
`Identifier.STREAM_CODEC` (`/opt/mc-src/net/minecraft/resources/Identifier.java:19-52`).

---

## 1. Registration: `DeferredRegister` → eager `Registry.register`

Pattern that preserves the `Supplier<T>` field shape (contract C1), mirroring
`TntLib/.../registry/RegistryHelper.java:205,210,489`:

```java
private static <T extends Item> Supplier<T> register(String name, Function<Item.Properties, T> factory, Item.Properties props) {
    T value = Registry.register(BuiltInRegistries.ITEM,
        Identifier.fromNamespaceAndPath(MODID, name),
        factory.apply(props.setId(ResourceKey.create(Registries.ITEM, Identifier.fromNamespaceAndPath(MODID, name)))));
    return () -> value;
}
```

`Registry.register` overloads (`/opt/mc-src/net/minecraft/core/Registry.java:106-118`):
`register(Registry<? super T>, String, T)`, `register(Registry<V>, Identifier, T extends V)`,
`register(Registry<V>, ResourceKey<V>, T)`. There is also `registerForHolder(...)` returning
`Holder.Reference<T>` (line 120) when you need a `Holder`.

| registry | `BuiltInRegistries` field | source |
|---|---|---|
| items | `ITEM` (`Registry<Item>`) | BuiltInRegistries.java |
| blocks | `BLOCK` | |
| block entities | `BLOCK_ENTITY_TYPE` | |
| entities | `ENTITY_TYPE` | |
| menus | `MENU` | |
| sounds | `SOUND_EVENT` | |
| creative tabs | `CREATIVE_MODE_TAB` (line 293) — **not** `Registries.CREATIVE_MODE_TAB` for `Registry.register` | |
| data components | `DATA_COMPONENT_TYPE` (line 296) | |
| recipe types / serializers | `RECIPE_TYPE` (203) / `RECIPE_SERIALIZER` (204) | |
| recipe book categories | `RECIPE_BOOK_CATEGORY` (328) | |

### Mandatory `setId(...)` on properties

| class | method | source |
|---|---|---|
| `Item.Properties` | `Item.Properties setId(ResourceKey<Item>)` | `/opt/mc-src/net/minecraft/world/item/Item.java:627` |
| `BlockBehaviour.Properties` | `Properties setId(ResourceKey<Block>)` | `.../block/state/BlockBehaviour.java:1278` |

Missing it → `NullPointerException: Item id not set` at registration.

### `EntityType`

```java
EntityType<T> type = Registry.register(BuiltInRegistries.ENTITY_TYPE, id,
    EntityType.Builder.of(factory, MobCategory.MISC)
        .sized(w, h).clientTrackingRange(5).updateInterval(3)
        .build(ResourceKey.create(Registries.ENTITY_TYPE, id)));   // build() takes a ResourceKey now
```
`/opt/mc-src/net/minecraft/world/entity/EntityType.java:487` (`Builder.of`), `:595` (`build(ResourceKey<EntityType<?>>)`).
The old public 12-arg `new EntityType<>(factory, category, …, FeatureFlags.VANILLA_SET)` constructor
shape from 1.21.1 no longer matches.

`EntityType#create` now needs a spawn reason:
`create(Level, EntitySpawnReason)` (`EntityType.java:300`). Values at
`/opt/mc-src/net/minecraft/world/entity/EntitySpawnReason.java` — `SPAWN_ITEM_USE`, `MOB_SUMMONED`,
`COMMAND`, `TRIGGERED`, `LOAD`, … It returns `@Nullable T`.

### `BlockEntityType`

Constructor lost the datafixer arg: `new BlockEntityType<>(BlockEntitySupplier<T>, Set<Block>)`
— 2 args, no trailing `null` (`/opt/mc-src/net/minecraft/world/level/block/entity/BlockEntityType.java:18`).

### Custom (modded) registry — NeoForge `RegistryBuilder` → Fabric

```java
public static final ResourceKey<Registry<UpgradeType>> KEY =
    ResourceKey.createRegistryKey(Identifier.fromNamespaceAndPath(MODID, "upgrade_types"));
public static final Registry<UpgradeType> UPGRADE_TYPE =
    FabricRegistryBuilder.create(KEY).attribute(RegistryAttribute.SYNCED).buildAndRegister();
```
Verified with `javap` on
`~/.gradle/caches/modules-2/files-2.1/net.fabricmc.fabric-api/fabric-registry-sync-v0/**.jar`:
`FabricRegistryBuilder.create(ResourceKey<Registry<T>>) → FabricRegistryBuilder<T, MappedRegistry<T>>`,
`.attribute(RegistryAttribute)`, `.buildAndRegister()`. `RegistryAttribute` = `SYNCED|MODDED|OPTIONAL`.
There is **no** `NewRegistryEvent` equivalent — the builder registers immediately.

### Creative tabs

`FabricCreativeModeTab.builder()` → `CreativeModeTab.Builder` (javap on
`fabric-creative-tab-api-v1`; used in `tntmod/src/main/java/luckytnt/registry/LuckyTNTTabs.java:25`).
Vanilla `CreativeModeTab.builder()` now needs `(Row, int column)`
(`/opt/mc-src/net/minecraft/world/item/CreativeModeTab.java:49`) — use the Fabric one instead.
Then `Registry.register(BuiltInRegistries.CREATIVE_MODE_TAB, id, tab)` (LuckyTNTTabs.java:78).

### Data components

`DataComponentType.builder().persistent(codec).networkSynchronized(streamCodec).build()`
(`/opt/mc-src/net/minecraft/core/component/DataComponentType.java:26,53,60`), then
`Registry.register(BuiltInRegistries.DATA_COMPONENT_TYPE, id, type)`.

**Dead end:** NeoForge's `ItemStack#set(Supplier<DataComponentType<T>>, T)` /
`get(Supplier<…>)` overloads do not exist in vanilla — `ItemStack.set/get` take the raw
`DataComponentType`. If some call sites in the codebase write `FOO` and others `FOO.get()`, register
a wrapper that implements *both* `DataComponentType<T>` and `Supplier<DataComponentType<T>>`
(delegating `codec()`, `streamCodec()`, `ignoreSwapAnimation()`); everything then compiles unchanged.

---

## 2. Entrypoint & events

| NeoForge | Fabric 26.2 |
|---|---|
| `@Mod(MODID)` + ctor `(IEventBus, ModContainer)` | `implements ModInitializer` / `onInitialize()` |
| `FMLCommonSetupEvent` + `event.enqueueWork(…)` | just run it at the end of `onInitialize()` — registries are already populated |
| `RegisterCapabilitiesEvent` | **gone**, no replacement; look the target object up directly |
| `@EventBusSubscriber` + `PlayerInteractEvent.RightClickItem` | `UseItemCallback.EVENT.register((Player, Level, InteractionHand) -> InteractionResult)` |

`UseItemCallback` verified via javap on `fabric-events-interaction-v0`:
`InteractionResult interact(Player, Level, InteractionHand)`. Same jar also has
`BlockEvents$UseItemOnCallback`, `ItemEvents$UseCallback`, `AttackEntityCallback`,
`PlayerPickItemEvents`, `UseEntityCallback`, `UseBlockCallback`.

---

## 3. Config

NeoForge `ModConfigSpec` has no Fabric counterpart and no vanilla one. Cheapest port that keeps
`XXX.get()` call sites: a class of `public static final Supplier<Boolean|Integer|Double>` constants
holding the old TOML defaults. Log it as a §9 cut.

---

## 4. Reload listeners (datapack JSON)

**Dead end:** `SimpleJsonResourceReloadListener` still exists but became
`SimpleJsonResourceReloadListener<T> extends SimplePreparableReloadListener<Map<Identifier, T>>`
and is **codec-driven** — the old `super(GSON, "dir")` + `apply(Map<ResourceLocation, JsonElement>, …)`
shape is gone (`/opt/mc-src/net/minecraft/server/packs/resources/SimpleJsonResourceReloadListener.java:23-38`).

If you want to keep raw Gson parsing, extend `SimplePreparableReloadListener<Map<Identifier, JsonElement>>`
and scan yourself:

```java
private static final FileToIdConverter LISTER = FileToIdConverter.json("plane_payload");

protected Map<Identifier, JsonElement> prepare(ResourceManager manager, ProfilerFiller profiler) {
    Map<Identifier, JsonElement> out = new HashMap<>();
    for (Map.Entry<Identifier, Resource> e : LISTER.listMatchingResources(manager).entrySet()) {
        try (Reader r = e.getValue().openAsReader()) { out.put(LISTER.fileToId(e.getKey()), StrictJsonParser.parse(r)); }
        catch (Exception ex) { LOGGER.error(…); }
    }
    return out;
}
protected void apply(Map<Identifier, JsonElement> map, ResourceManager manager, ProfilerFiller profiler) { … }
```
`SimplePreparableReloadListener` signatures: `/opt/mc-src/.../SimplePreparableReloadListener.java:22-24`.
`FileToIdConverter.json(prefix)` / `.fileToId(Identifier)` / `.listMatchingResources(ResourceManager)`:
`/opt/mc-src/net/minecraft/resources/FileToIdConverter.java:11,23`.
`StrictJsonParser.parse(Reader)`: `/opt/mc-src/net/minecraft/util/StrictJsonParser.java:16`.

Registration replaces `AddReloadListenerEvent`:
```java
ResourceLoader.get(PackType.SERVER_DATA).registerReloadListener(Identifier, PreparableReloadListener);
```
javap on `fabric-resource-loader-v1`:
`net.fabricmc.fabric.api.resource.v1.ResourceLoader.get(PackType)` +
`registerReloadListener(Identifier, PreparableReloadListener)` and
`addListenerOrdering(Identifier, Identifier)`. Ordering anchors live in
`net.fabricmc.fabric.api.resource.v1.reloader.ResourceReloaderKeys.{BEFORE,AFTER}_VANILLA`.
(`fabric-resource-loader-v0`'s `ResourceManagerHelper` still exists but v1 is the current API.)

Other registry-lookup fixes hit here:
`BuiltInRegistries.X.get(Identifier)` now returns `Optional<Holder.Reference<T>>`
(`/opt/mc-src/net/minecraft/core/Registry.java:133`). For the old nullable value use
**`getValue(Identifier)`** (line 67). `getTag(TagKey)` is gone — the tag lookup is
`registry.get(TagKey) → Optional<HolderSet.Named<T>>` (`HolderLookup.java:121`).

`TagParser.parseTag(String)` → **`TagParser.parseCompoundFully(String)`**
(`/opt/mc-src/net/minecraft/nbt/TagParser.java:60`).

---

## 5. Menus / containers

| NeoForge | Fabric 26.2 |
|---|---|
| `IMenuTypeExtension.create(factory)` (menu with extra spawn data) | `new ExtendedMenuType<T, D>(ExtendedFactory<T,D>, StreamCodec<? super RegistryFriendlyByteBuf, D>)` |
| `player.openMenu(provider, buf -> …)` | `player.openMenu(ExtendedMenuProvider<D>)` — implement `D getScreenOpeningData(ServerPlayer)` |
| client ctor `(int, Inventory, FriendlyByteBuf)` | client ctor `(int, Inventory, D)` |
| plain menu | `new MenuType<>(MenuSupplier<T>, FeatureFlags.VANILLA_SET)` (unchanged) |

Package is `net.fabricmc.fabric.api.menu.v1` (module **`fabric-menu-api-v1`**, *not*
`fabric-screen-handler-api-v1`). javap output:
```
ExtendedMenuType<T extends AbstractContainerMenu, D> extends MenuType<T>
  ExtendedMenuType(ExtendedMenuType$ExtendedFactory<T,D>, StreamCodec<? super RegistryFriendlyByteBuf, D>)
ExtendedMenuType$ExtendedFactory<T,D>: T create(int, Inventory, D)
ExtendedMenuProvider<D> extends MenuProvider: D getScreenOpeningData(ServerPlayer)
```
`ByteBufCodecs.VAR_INT` is `StreamCodec<ByteBuf, Integer>`; `FriendlyByteBuf extends ByteBuf`
(`/opt/mc-src/net/minecraft/network/FriendlyByteBuf.java:71`), so `? super RegistryFriendlyByteBuf`
accepts it and `Foo::new` binds to an `int` ctor by unboxing.

### `ItemStackHandler` / `IItemHandler` / `SlotItemHandler`

All gone. Two workable substitutions:

* `SimpleContainer` (`/opt/mc-src/net/minecraft/world/SimpleContainer.java`) + plain
  `new Slot(Container, index, x, y)` (`/opt/mc-src/net/minecraft/world/inventory/Slot.java:17`).
* A hand-written `implements Container` class keeping the NeoForge method names
  (`getSlots/getStackInSlot/setStackInSlot/insertItem/extractItem/setSize/serializeNBT/deserializeNBT`)
  when you must not touch hundreds of call sites. Because it implements `Container`, vanilla `Slot`
  works over it directly.

`Container` (`/opt/mc-src/net/minecraft/world/Container.java:19`) extends `Clearable, Iterable<ItemStack>,
SlotProvider`; abstract methods are `getContainerSize, isEmpty, getItem, removeItem,
removeItemNoUpdate, setItem, setChanged, stillValid` (+ `clearContent()` from `Clearable`).
Note `startOpen`/`stopOpen` now take `ContainerUser`, not `Player`.

Item persistence helpers: `ContainerHelper.saveAllItems(ValueOutput, NonNullList<ItemStack>[, boolean])`
/ `loadAllItems(ValueInput, NonNullList<ItemStack>)`
(`/opt/mc-src/net/minecraft/world/ContainerHelper.java:21,40`) — they write an `"Items"` list of
`ItemStackWithSlot`.

**Fuel check:** `ItemStack#getBurnTime(RecipeType)` is gone. Burn time is data-driven:
`Level#fuelValues()` → `FuelValues#isFuel(ItemStack)` / `burnDuration(ItemStack)`
(`/opt/mc-src/net/minecraft/world/level/Level.java:1107`,
`/opt/mc-src/net/minecraft/world/level/block/entity/FuelValues.java:26,34`). A `Slot` has no `Level`,
so pass a `Supplier<Level>` into the slot.

---

## 6. Recipes

`RecipeSerializer` is **no longer an interface to implement** — it is a record:
```java
public record RecipeSerializer<T extends Recipe<?>>(MapCodec<T> codec, StreamCodec<RegistryFriendlyByteBuf, T> streamCodec) {}
```
(`/opt/mc-src/net/minecraft/world/item/crafting/RecipeSerializer.java:7`). Delete the serializer
class, keep the two codecs, and register `new RecipeSerializer<>(CODEC, STREAM_CODEC)`.

`RecipeType` has no `RecipeType.simple(Identifier)`; register an anonymous instance:
`Registry.register(BuiltInRegistries.RECIPE_TYPE, id, new RecipeType<MyRecipe>() {})`
(mirrors `/opt/mc-src/net/minecraft/world/item/crafting/RecipeType.java:16`).

`Recipe<T extends RecipeInput>` interface changed (`/opt/mc-src/.../crafting/Recipe.java:18-42`):

| 1.21.1 | 26.2 |
|---|---|
| `assemble(T, HolderLookup.Provider)` | `ItemStack assemble(T input)` |
| `getResultItem(HolderLookup.Provider)` | **removed** |
| `canCraftInDimensions(int,int)` | **removed** |
| — | `boolean showNotification()` **(new, required)** |
| — | `String group()` **(new, required)** |
| — | `PlacementInfo placementInfo()` **(new, required)** — `PlacementInfo.NOT_PLACEABLE` is fine |
| — | `RecipeBookCategory recipeBookCategory()` **(new, required)** — `RecipeBookCategories.CRAFTING_MISC` |
| `getSerializer()` returns `RecipeSerializer<?>` | returns `RecipeSerializer<? extends Recipe<T>>` |

`ItemStack.STRICT_CODEC` **does not exist** in 26.2 — use `ItemStack.CODEC`
(`/opt/mc-src/net/minecraft/world/item/ItemStack.java:122`). `Ingredient.CODEC` and
`Ingredient.CONTENTS_STREAM_CODEC` are unchanged (`.../crafting/Ingredient.java:27,34`).

### Reading recipes from a menu (client-side!)

`Level#getRecipeManager()` is gone. `Level#recipeAccess()` returns `RecipeAccess`
(`/opt/mc-src/net/minecraft/world/level/Level.java:1064`); only the *server* one is a `RecipeManager`.
`getAllRecipesFor(type)` is now `getAllOfType(type)` and lives on Fabric's `FabricRecipeManager`
(server-only). To list a custom recipe type on both sides:

```java
SimplePlanesRecipes.init():  RecipeSynchronization.synchronizeRecipeSerializer(SERIALIZER);
in the menu:                 level.recipeAccess().getSynchronizedRecipes().getAllOfType(TYPE);
```
javap on `fabric-recipe-api-v1`: `RecipeSynchronization.synchronizeRecipeSerializer(RecipeSerializer<?>)`,
`FabricRecipeAccess.getSynchronizedRecipes() → SynchronizedRecipes`,
`SynchronizedRecipes.getAllOfType(RecipeType<T>) → Collection<RecipeHolder<T>>`.

---

## 7. Blocks & block entities

| 1.21.1 | 26.2 | source |
|---|---|---|
| `Block#onRemove(BlockState, Level, BlockPos, BlockState, boolean)` | **removed** → `protected void affectNeighborsAfterRemoval(BlockState, ServerLevel, BlockPos, boolean movedByPiston)` | `BlockBehaviour.java:173`, `ChestBlock.java:256` |
| dropping BE contents in `onRemove` | `BlockEntity#preRemoveSideEffects(BlockPos, BlockState)` — runs **before** the BE is detached (`LevelChunk.java:307-315`) | `BlockEntity.java:235`, `AbstractFurnaceBlockEntity.java:376` |
| `saveAdditional(CompoundTag, HolderLookup.Provider)` | `protected void saveAdditional(ValueOutput)` | `BlockEntity.java:109` |
| `loadAdditional(CompoundTag, HolderLookup.Provider)` | `protected void loadAdditional(ValueInput)` | `BlockEntity.java:97` |
| `Containers.dropItemStack(...)` | unchanged (`Containers.java:32`); `updateNeighboursAfterDestroy(BlockState, Level, BlockPos)` at `:49` | |

`ValueInput` getters (`/opt/mc-src/net/minecraft/world/level/storage/ValueInput.java`):
`getIntOr/getShortOr/getLongOr/getFloatOr/getDoubleOr/getBooleanOr/getByteOr/getStringOr(name, def)`,
`getInt/getString/getLong → Optional`, `child(name) → Optional<ValueInput>`,
`childOrEmpty(name)`, `list(name, codec)`, `read(name, Codec)`.
`ValueOutput` (same dir): `putInt/putString/…`, `child(name) → ValueOutput`,
`list(name, codec)`, `store(name, Codec, T)`, `discard(name)`.

CompoundTag ↔ ValueInput/Output bridges:
```java
TagValueOutput out = TagValueOutput.createWithContext(ProblemReporter.DISCARDING, registries);
… ; CompoundTag tag = out.buildResult();
ValueInput in = TagValueInput.create(ProblemReporter.DISCARDING, registries, tag);
```
(`/opt/mc-src/net/minecraft/world/level/storage/TagValueOutput.java:27,152`,
`TagValueInput.java:40`, `/opt/mc-src/net/minecraft/util/ProblemReporter.java:18`).

`Entity#readAdditionalSaveData` / `addAdditionalSaveData` are **`protected abstract`** in 26.2
(`/opt/mc-src/net/minecraft/world/entity/Entity.java:2208-2210`) — they were public in 1.21.1.
Cross-package callers (e.g. an item spawning a configured entity) need a public bridge on your own
entity class. Do **not** access-widen `Entity#readAdditionalSaveData`: your subclass would then be
reducing visibility and javac rejects it. `Entity#load(ValueInput)` is public but resets position
from the tag, so it is not a substitute.

---

## 8. Items

| 1.21.1 | 26.2 | source |
|---|---|---|
| `InteractionResultHolder<ItemStack> use(Level, Player, InteractionHand)` | `InteractionResult use(Level, Player, InteractionHand)` | `Item.java:188` |
| `InteractionResultHolder.sidedSuccess(stack, isClient)` | `level.isClientSide ? InteractionResult.SUCCESS : InteractionResult.SUCCESS_SERVER` | `InteractionResult.java:11-16` |
| `InteractionResultHolder.pass/fail(stack)` | `InteractionResult.PASS` / `InteractionResult.FAIL` | |
| `appendHoverText(ItemStack, TooltipContext, List<Component>, TooltipFlag)` | `appendHoverText(ItemStack, Item.TooltipContext, TooltipDisplay, Consumer<Component>, TooltipFlag)` | `Item.java:323`, `net/minecraft/world/item/component/TooltipDisplay.java` |
| `Item#isEnchantable/getEnchantmentValue/supportsEnchantment` | **removed** → `Item.Properties#enchantable(int)` = `DataComponents.ENCHANTABLE` | `Item.java:433`, `DataComponents.java:190` |
| `ItemStack#onCraftedBy(Level, Player, int)` | `ItemStack#onCraftedBy(Player, int)`; `Item#onCraftedBy(ItemStack, Player)` | `ItemStack.java:721`, `Item.java:291` |
| `BlockItem(Block, Item.Properties)` | unchanged, but add `.useBlockDescriptionPrefix()` for the `block.` translation key | `Item.java:637` |

`CompoundTag` getters return `Optional` in 26.2: `getString(name) → Optional<String>`,
`getInt(name) → Optional<Integer>`, `getCompound(name) → Optional<CompoundTag>`; the non-Optional
forms are `getStringOr(name, def)`, `getIntOr(name, def)`, `getCompoundOrEmpty(name)`.
`getAllKeys()` → **`keySet()`**. (`/opt/mc-src/net/minecraft/nbt/CompoundTag.java:193,299,331,351,355`)

`Level#getEntities(null, aabb)` is now ambiguous against the `EntityTypeTest` overload — cast:
`getEntities((Entity) null, aabb)` (`/opt/mc-src/net/minecraft/world/level/EntityGetter.java:19,21,29`).

---

## 9. Data / resource JSON

### Recipes — plain-string ingredients
`{"tag": "c:ingots/iron"}` → `"#c:ingots/iron"`; `{"item": "minecraft:stick"}` → `"minecraft:stick"`;
applies to `key` values, `ingredients` entries and any custom `ingredient` field.
Verified against `tntmod/src/main/resources/data/luckytntmod/recipe/craft_acidic_tnt.json`
(355 already-migrated recipes) and `Ingredient.CODEC = HolderSetCodec.create(Registries.ITEM, …)`.
`result` keeps the `{"id": …, "count": …}` object form.

Convention-tag renames worth knowing (contents of `fabric-convention-tags-v2`'s
`data/c/tags/item/`): `c:slimeballs` → **`c:slime_balls`**. Everything else the mod used exists
unchanged: `c:ingots/{iron,copper}`, `c:storage_blocks/{iron,gold,redstone}`, `c:gems/{lapis,diamond,quartz}`,
`c:rods/blaze`, `c:obsidians/normal`, `c:dusts/redstone`, `c:glass_blocks/colorless`, `c:strings`.

### Item model definitions (1.21.4+)
`assets/<ns>/models/item/foo.json` stays as-is, and a **new** `assets/<ns>/items/foo.json` is required
per registered item:
```json
{ "model": { "type": "minecraft:model", "model": "<ns>:item/foo" } }
```
(mirrors `tntmod/src/main/resources/assets/luckytntmod/items/*.json`).
Item colour providers are gone; tints go in that file, e.g.
```json
"tints": [ { "type": "minecraft:constant", "value": 11702101 } ]
```
Model types are registered at `/opt/mc-src/net/minecraft/client/renderer/item/ItemModels.java:22-30`
(`empty`, `model`, `range_dispatch`, `special`, `composite`, `select`, `condition`);
`tints` field on the `model` type: `CuboidItemModelWrapper.Unbaked` (`:129-135`);
tint sources at `/opt/mc-src/net/minecraft/client/color/item/` (`Constant`, `Dye`, `MapColor`,
`GrassColorSource`, `Potion`, `TeamColor`, `Firework`, `CustomModelDataSource`).

### `pack.mcmeta`
`SharedConstants`: `RESOURCE_PACK_FORMAT_MAJOR = 88`, `MINOR = 0`; `DATA_PACK_FORMAT_MAJOR = 107`,
`MINOR = 1` (`/opt/mc-src/net/minecraft/SharedConstants.java:27-33`).
Above the "last pre-minor" version (64 for resources, 81 for data,
`/opt/mc-src/net/minecraft/server/packs/metadata/pack/PackFormat.java:64-68`), `pack_format` and
`supported_formats` are **rejected**; you must use `min_format`/`max_format`, and a mod's single
pack.mcmeta has to span both pack types:
```json
{ "pack": { "description": "…", "min_format": 88, "max_format": 107 } }
```
(`min_format` uses `BOTTOM_CODEC` → bare int means `.0`; `max_format` uses `TOP_CODEC` → bare int
means `.MAX`, so 107 covers 107.1.)

### Directory layout (unchanged from 1.21.5+, confirmed against tntmod)
`data/<ns>/recipe/`, `data/<ns>/loot_table/blocks/`, `data/<ns>/tags/{block,item}/`,
`data/minecraft/tags/block/mineable/…`, `assets/<ns>/blockstates/`, `assets/<ns>/models/{block,item}/`,
`assets/<ns>/items/`. Block loot table id is `<ns>:blocks/<name>`
(`/opt/mc-src/net/minecraft/world/level/block/state/BlockBehaviour.java:986`).
Blockstate JSON still uses `{"variants": {"": {"model": …}}}`.

---

## 10. Annotations / misc

* `javax.annotation.Nullable` (JSR305) is not on the Fabric classpath — Minecraft itself uses
  `org.jspecify.annotations.Nullable`; use that. `org.jetbrains.annotations` is present but there is
  no reason to depend on it.
* `SoundEvent.createVariableRangeEvent(Identifier)` / `createFixedRangeEvent(Identifier, float)`
  unchanged (`/opt/mc-src/net/minecraft/sounds/SoundEvent.java:38,45`).
* `TagKey.create(Registries.BLOCK, Identifier)` — `BlockTags.create(...)` is private in 26.2
  (`/opt/mc-src/net/minecraft/tags/BlockTags.java:260`).
* `AbstractContainerMenu.stillValid(ContainerLevelAccess, Player, Block)` is still `protected static`
  (`AbstractContainerMenu.java:93`); `DataSlot.standalone()` unchanged.
* Avoid touching `net.minecraft.client.*` from common classes (e.g. resolving an entity in a menu
  constructor): use `playerInventory.player.level().getEntity(id)` — it works on both sides.


---

# Приложение: находки порта Domum Ornamentum (NeoForge 26.1 → Fabric 26.2)

Всё ниже добавлено по итогам порта Domum Ornamentum и проверено на нём: сборка, датаген
и выделенный сервер зелёные, клиент проверен вручную. Каждая запись подтверждена ссылкой
на `/opt/mc-src` или на строку рабочего 26.2-мода. Материал не дублирует то, что было
в ките выше, — это только новое.



Собрано агентом A на порте Domum Ornamentum, NeoForge 26.1 → Fabric 26.2.
Дублей с `NOTES-A.md` / `PORT-ANY-MOD-26.2.md` здесь нет — только то, что пришлось выяснять самому.

---

### `BlockBehaviour.Properties.setId(...)`, когда конструктор блока не принимает `Properties`

- **Было (NeoForge 26.1):** `DeferredRegister.Blocks.register(name, Supplier<B>)` — NeoForge патчил
  `Properties` и проставлял id за тебя, поэтому мод мог сколько угодно строить `Properties` внутри
  собственных конструкторов блоков (`public BarrelBlock() { super(Properties.ofLegacyCopy(Blocks.OAK_PLANKS)); }`).
- **Стало (26.2):** `BlockBehaviour` читает id **в своём конструкторе**, до того как объект вернётся
  наружу:
  ```java
  public BlockBehaviour(final BlockBehaviour.Properties properties) {
      this.drops = properties.effectiveDrops();                 // → requireNonNull(this.id, "Block id not set")
      this.descriptionId = properties.effectiveDescriptionId();  // → то же самое
  ```
  Перехватить неоткуда: `Properties` создаётся статической фабрикой внутри конструктора блока и
  сразу уходит в `super(...)`. Ни рефлексия, ни access widener не помогают — падение происходит
  **раньше**, чем появляется ссылка на объект.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/state/BlockBehaviour.java:104-106`
  (конструктор), `:1154-1156` (`effectiveDrops`), `:1288-1290` (`effectiveDescriptionId`),
  `:1278` (`setId`)
- **Комментарий:** референс-моды этой проблемы не показывают, потому что у них конструкторы блоков
  принимают `Properties` (`/workspace/simple-planes/26.2/src/main/java/xyz/przemyk/simpleplanes/setup/SimplePlanesBlocks.java:34-37`) —
  канонический рецепт `factory.apply(properties.setId(key))` работает только в этом случае.
  У мода с 57 блоками и 13 абстрактными корнями, каждый из которых строит `Properties` сам,
  переписывать конструкторы дорого, и это чужие файлы. Рабочий обходной путь — **контекст-держатель
  + миксин на конструктор `Properties`**:
  ```java
  @Mixin(BlockBehaviour.Properties.class)
  public abstract class BlockBehaviourPropertiesMixin {
      @Inject(method = "<init>", at = @At("RETURN"))
      private void mod$applyPendingId(CallbackInfo ci) {
          ResourceKey<Block> pending = BlockIdContext.get();
          if (pending != null) ((BlockBehaviour.Properties) (Object) this).setId(pending);
      }
  }
  ```
  а регистратор открывает окно ровно вокруг вызова фабрики:
  ```java
  BlockIdContext.set(key);
  try { block = factory.get(); } finally { BlockIdContext.clear(); }
  Registry.register(BuiltInRegistries.BLOCK, key, block);
  ```
  Две грабли, на которых это ломается молча:
  1. **Класс-держатель контекста должен быть пустым.** Миксин трогает его при **каждом** создании
     `Properties`, в том числе на бутстрапе ванильных блоков. Если положить поле прямо в `ModBlocks`,
     первое же ванильное `Properties.of()` инициирует класс мода и зарегистрирует все блоки мода
     посреди бутстрапа. Нужен отдельный класс без статических инициализаторов с побочными эффектами.
  2. **Ванилле это не вредит.** `Blocks.register` сам вызывает `properties.setId(id)` уже после
     конструирования `Properties`, так что «испачканный» id перетирается
     (`/opt/mc-src/net/minecraft/world/level/block/Blocks.java:5692-5694`).

---

### `CreativeModeTab.Builder#withTabsBefore` / `.builder()` без аргументов

- **Было (NeoForge 26.1):** `CreativeModeTab.builder().withTabsBefore(otherTab.getId())…build()`.
- **Стало (26.2):** ванильная фабрика — `CreativeModeTab.builder(CreativeModeTab.Row row, int column)`,
  а `withTabsBefore` **удалён целиком**. Для модов правильная точка входа —
  `net.fabricmc.fabric.api.creativetab.v1.FabricCreativeModeTab.builder()` (без аргументов,
  возвращает ванильный `CreativeModeTab.Builder`), затем
  `Registry.register(BuiltInRegistries.CREATIVE_MODE_TAB, ResourceKey<CreativeModeTab>, tab)`.
  Порядок модовых вкладок задаётся порядком регистрации, явного API упорядочивания нет.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/item/CreativeModeTab.java:49,120-192`;
  `javap net.fabricmc.fabric.api.creativetab.v1.FabricCreativeModeTab` →
  `public static net.minecraft.world.item.CreativeModeTab$Builder builder()`
- **Комментарий:** `CreativeModeTab.Output` не изменился (`accept(ItemStack, TabVisibility)` +
  дефолты `accept(ItemStack)`, `accept(ItemLike[, TabVisibility])`, `acceptAll(...)`), поэтому
  обёртки-декораторы над `DisplayItemsGenerator`/`Output` переносятся дословно
  (`/opt/mc-src/net/minecraft/world/item/CreativeModeTab.java:249-271`). А вот сигнатура
  **пополнения чужих** вкладок другая, чем у `ItemGroupEvents`:
  `CreativeModeTabEvents.modifyOutputEvent(ResourceKey<CreativeModeTab>)` отдаёт `Event<ModifyOutput>`,
  где `void modifyOutput(FabricCreativeModeTabOutput output)` — **один** аргумент, не `(entries)`
  и не `(context, entries)`.

---

### `DataComponentType`, который одновременно `Supplier` самого себя

- **Было (NeoForge 26.1):** `DeferredHolder<DataComponentType<?>, DataComponentType<D>>` — он же
  `Supplier`, плюс NeoForge-перегрузки `ItemStack#get/set/getOrDefault(Supplier<DataComponentType<T>>, …)`.
  Поэтому в коде мирно уживаются `FOO.get()` и `stack.set(FOO, value)`.
- **Стало (26.2):** ванильные `ItemStack` / `DataComponentMap` / `DataComponentPatch.Builder`
  принимают только сырой `DataComponentType<T>`; `Supplier`-перегрузок нет.
- **Подтверждено:** `/opt/mc-src/net/minecraft/core/component/DataComponentType.java:16-70`
  (интерфейс: `codec()`, `ignoreSwapAnimation()`, `streamCodec()` — всего три метода)
- **Комментарий:** `NOTES-A §1` называет обходной путь, но не проговаривает две детали, на которых
  легко ошибиться. Первое: **регистрировать надо обёртку, а не делегат** — в реестре должен лежать
  тот же объект, что и в поле, поиск компонентов идентичностный; соответственно `get()` возвращает
  `this`, а не `delegate`. Второе: если обёртка утекает через публичный API-интерфейс
  (`IDomumOrnamentumApi#getMaterialTextureComponentType()`), **тип возврата в интерфейсе тоже надо
  сменить** с `Supplier<DataComponentType<T>>` на конкретный класс обёртки — иначе `stack.set(...)`
  на месте вызова снова не компилируется. Три метода делегируются в одну строку каждый:
  ```java
  public static final class ComponentType<D> implements DataComponentType<D>, Supplier<DataComponentType<D>> {
      private final DataComponentType<D> delegate;
      public Codec<D> codec() { return delegate.codec(); }
      public boolean ignoreSwapAnimation() { return delegate.ignoreSwapAnimation(); }
      public StreamCodec<? super RegistryFriendlyByteBuf, D> streamCodec() { return delegate.streamCodec(); }
      public DataComponentType<D> get() { return this; }
  }
  ```

---

### `BlockEntityType`, который принимает «все блоки, реализующие интерфейс»

- **Было (NeoForge 26.1):** `BlockEntityType.Builder.of(factory, Block[]).build(null)` — билдер брал
  массив и датафиксер.
- **Стало (26.2):** билдера нет вовсе, конструктор `BlockEntityType(BlockEntitySupplier<T>, Set<Block>)`
  — именно **`Set`**, не массив. Плюс `BlockEntityType` заводит intrusive holder прямо в поле
  (`BuiltInRegistries.BLOCK_ENTITY_TYPE.createIntrusiveHolder(this)`), поэтому созданный тип обязан
  быть зарегистрирован **немедленно** — «создать сейчас, зарегистрировать потом» не работает.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/entity/BlockEntityType.java:13-21`
- **Комментарий:** мод, который собирает `validBlocks` фильтром по `BuiltInRegistries.BLOCK.stream()`,
  на Fabric получает **порядок инициализации в явном виде**: класс с блок-сущностями обязан
  класс-грузиться после класса с блоками. У NeoForge это гарантировал порядок событий реестров, у
  Fabric — только порядок вызовов в `onInitialize()`. Отсюда паттерн «пустой `public static void init()`
  в каждом классе-реестре + явная последовательность вызовов в entrypoint»: он не делает ничего,
  кроме как фиксирует момент класс-загрузки.

---

### `RecipeType` без `simple(...)`

- **Было (NeoForge 26.1):** `RecipeType.simple(ResourceLocation)`.
- **Стало (26.2):** метода нет; ванилла регистрирует анонимную реализацию —
  `Registry.register(BuiltInRegistries.RECIPE_TYPE, id, new RecipeType<T>() { public String toString() {…} })`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/item/crafting/RecipeType.java:7-24`
- **Комментарий:** `RecipeType.register(String)` в ваниле публичный, но подставляет
  `Identifier.withDefaultNamespace(name)`, то есть пространство имён `minecraft:`. Моду им
  пользоваться нельзя, надо копировать тело.

---

### Fabric Loom 1.17.13: `--offline` не работает даже с прогретым кэшем

- **Было:** —
- **Стало (26.2):** `gradle compileJava --offline` падает на
  `net.fabricmc:sponge-mixin:0.17.3+mixin.0.8.7` и `io.github.llamalad7:mixinextras-fabric:0.5.4` —
  «No cached version … available for offline mode», даже когда в кэше уже лежат `minecraft`,
  `fabric-loader` и все модули `fabric-api`. Эти два артефакта — транзитивные зависимости
  `fabric-loader` и попадают в `compileClasspath` **всегда**, независимо от того, использует мод
  миксины или нет.
- **Подтверждено:** `/home/user/Domum-Ornamentum/26.2` — прогон
  `gradle compileJava --no-daemon --offline` против кэша, где
  `~/.gradle/caches/modules-2/files-2.1/net.fabricmc/` содержит `fabric-loader`, `fabric-loom`,
  `tiny-remapper`, но не `sponge-mixin`
- **Комментарий:** практический вывод для контейнера без сети — первый прогон обязан быть онлайн,
  и планировать `--offline` как способ «не ходить в сеть» нельзя. Полезно, чтобы не потратить цикл
  на диагностику «сломанной конфигурации», которой на самом деле нет.

---

### Точки входа: что действительно требуется в `fabric.mod.json`

- **Было (NeoForge 26.1):** `@Mod(MODID)` + конструктор `(FMLModContainer, Dist)`, всё остальное —
  аннотации `@EventBusSubscriber` со сканированием класспаса.
- **Стало (26.2):** три точки входа, все объявляются явно:
  `main` → `ModInitializer#onInitialize()`,
  `client` → `ClientModInitializer#onInitializeClient()`,
  `fabric-datagen` → `net.fabricmc.fabric.api.datagen.v1.DataGeneratorEntrypoint#onInitializeDataGenerator(FabricDataGenerator)`.
- **Подтверждено:** `/workspace/desolation/src/main/resources/fabric.mod.json` (все три + `modmenu`),
  `/workspace/simple-planes/26.2/src/main/resources/fabric.mod.json`
- **Комментарий:** `fabric-datagen` работает только если в `build.gradle` есть блок
  ```groovy
  fabricApi { configureDataGeneration { client = true } }
  ```
  — он и создаёт задачу `runDatagen`. Без него точка входа просто никогда не вызывается, и никакой
  ошибки при этом нет. `pack.mcmeta` в ресурсах мода **не нужен** (у обоих референс-модов его нет),
  а `icon` необязателен — лучше не указывать вовсе, чем указать несуществующий путь.

---

### `@EventBusSubscriber` → явная регистрация: чего не хватает в таблице соответствий

- **Было (NeoForge 26.1):** `RegisterPayloadHandlersEvent` →
  `event.registrar(MOD_ID).versioned(modVersion).playToServer(...)`.
- **Стало (26.2):** у Fabric **нет версионирования пейлоадов**.
  `PayloadTypeRegistry.serverboundPlay()/.clientboundPlay().register(type, codec)` версии не знает,
  поэтому связка `ModList.get().getModContainerById(MOD_ID).get().getModInfo().getVersion()` не
  переносится, а удаляется целиком.
- **Подтверждено:** `/home/user/Domum-Ornamentum/26.2/src/main/java/com/ldtteam/domumornamentum/network/ModNetworking.java:31-39`
- **Комментарий:** побочный эффект — модовый пейлоад, отправленный клиенту другой версии, теперь не
  отвергается рукопожатием, а падает при декодировании. Модам с эволюционирующим протоколом это надо
  закладывать в сам кодек.



Всё, что пришлось выяснить самому при переносе 87 генераторов Domum Ornamentum
(NeoForge 26.1 → Fabric 26.2). §8 кита описывает датаген двумя строками; ниже — полная карта.

Ничего из этого не написано по памяти: каждая строка подтверждена либо файлом в `/opt/mc-src`,
либо рабочим 26.2-модом на диске (`/workspace/desolation`), либо `javap` по джарнику
fabric-api из `~/.gradle/caches`.

---

## 1. Карта замен: NeoForge-датаген → Fabric 26.2 (шпаргалка)

| NeoForge 26.1 | Fabric / ваниль 26.2 |
|---|---|
| `net.neoforged.neoforge.client.model.generators.BlockStateProvider` | `net.fabricmc.fabric.api.client.datagen.v1.provider.FabricModelProvider` (один на мод) |
| `registerStatesAndModels()` | `generateBlockStateModels(BlockModelGenerators)` + `generateItemModels(ItemModelGenerators)` |
| `models()` / `itemModels()` | поле `BlockModelGenerators.modelOutput` типа `BiConsumer<Identifier, ModelInstance>` |
| `ModelFile`, `ModelBuilder<T>`, `ItemModelBuilder` | **не существует**. Модель — это `ModelInstance extends Supplier<JsonElement>`, т.е. сырой `JsonObject` |
| `CustomLoaderBuilder` (`.customLoader(X::new).end()`) | **не существует**. Ключ `"loader"` в JSON пишется руками |
| `models().withExistingParent(path, parent)` | `modelOutput.accept(id, () -> {"parent": parent})` |
| `models().cubeAll(path, texture)` | либо `ModelTemplates.CUBE_ALL.create(...)`, либо тот же сырой JSON |
| `models().getExistingFile(id)` | **исчезло вместе с валидацией** — просто `Identifier` |
| `getVariantBuilder(block)` | `MultiVariantGenerator.dispatch(block[, MultiVariant])` |
| `getVariantBuilder(b).forAllStatesExcept(fn, p…)` | **нет прямого аналога**, см. §4 |
| `getMultipartBuilder(block)` | `MultiPartGenerator.multiPart(block)` |
| `MultiPartBlockStateBuilder.part()…addModel().condition(p,v).end()` | `multiPart.with(ConditionBuilder, MultiVariant)` |
| `ConfiguredModel.builder().modelFile(f).rotationX/Y().uvLock().build()` | `new MultiVariant(WeightedList.of(new Variant(id).withXRot(Quadrant).withYRot(...).withUvLock(true)))` |
| `simpleBlock(block, model)` | `blockStateOutput.accept(MultiVariantGenerator.dispatch(block, multiVariant))` |
| `simpleBlockItem(block, model)` | `modelOutput.accept(item/<name>, json)` + `itemModelOutput.accept(item, ItemModelUtils.plainModel(id))` |
| `ExistingFileHelper` | **нет и не будет**, см. §2 |
| `net.neoforged.neoforge.common.data.BlockTagsProvider` | `net.fabricmc.fabric.api.datagen.v1.provider.FabricTagsProvider.BlockTagsProvider` |
| `net.minecraft.data.tags.ItemTagsProvider` (NeoForge-вариант) | `FabricTagsProvider.ItemTagsProvider` (3-й аргумент ctor — экземпляр блочного провайдера) |
| `this.tag(TagKey)` | `builder(TagKey)` (§5) |
| `this.tag(X).addTags(BlockTags.LOGS, Tags.Blocks.STONES)` — ссылка на чужой тег | `builder(X).forceAddTag(BlockTags.LOGS)` — иначе датаген падает целиком (§5a) |
| `net.neoforged.neoforge.common.Tags.Blocks.X` | `net.fabricmc.fabric.api.tag.convention.v2.ConventionalBlockTags.X` (тот же `c:` на выходе) |
| `net.neoforged.neoforge.common.Tags.Items.X` | `ConventionalItemTags.X` |
| `LootTableProvider(packOutput, Set.of(), List.of(SubProviderEntry…), provider)` | по одному `FabricBlockLootSubProvider` на каждый бывший sub-provider |
| `RecipeProvider extends DataProvider` | `FabricRecipeProvider extends RecipeProvider.Runner` + анонимный `RecipeProvider` внутри (§7) |
| `com.ldtteam.data.LanguageProvider` (внешняя либа) | `FabricLanguageProvider` |
| `GatherDataEvent` в `@EventBusSubscriber` | `DataGeneratorEntrypoint#onInitializeDataGenerator(FabricDataGenerator)`, точка входа `fabric-datagen` в `fabric.mod.json` |

---

## 2. `BlockModelGenerators` — три публичных «стока» + мёртвый `ExistingFileHelper`

### `BlockModelGenerators` — три публичных «стока»
- **Было (NeoForge 26.1):** `BlockStateProvider.models()` / `.itemModels()`, свои билдеры.
- **Стало (26.2 / Fabric):** три поля, и все три — `public final`:
  ```java
  public final Consumer<BlockModelDefinitionGenerator> blockStateOutput;   // assets/<ns>/blockstates/<id>.json
  public final ItemModelOutput                          itemModelOutput;   // assets/<ns>/items/<id>.json
  public final BiConsumer<Identifier, ModelInstance>    modelOutput;       // assets/<ns>/models/<path>.json
  ```
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/data/models/BlockModelGenerators.java:131,135,139`;
  раскладка путей — `/opt/mc-src/net/minecraft/client/data/models/ModelProvider.java:42-44`.
- **Комментарий:** в **26.1** эти поля были `private`, и `/workspace/desolation` открывал их
  access-widener'ом (`desolation.accesswidener`, блок «Model datagen (26.1)»). В 26.2 свой AW не нужен —
  их открывает сам fabric-api через `fabric-data-generation-api-v1.classtweaker`
  (`transitive-accessible field …BlockModelGenerators blockStateOutput …`). **Практическое следствие:**
  ad-hoc `javac` из §3 кита падает на них с «has private access», потому что берёт не тот джарник.
  Компилировать надо против проектного
  `<project>/.gradle/loom-cache/minecraftMaven/net/minecraft/minecraft-merged-<hash>/26.2/…jar`
  (с применённым classtweaker), а не против `~/.gradle/caches/fabric-loom/minecraftMaven/…-deobf-…jar`.

### `ModelInstance` — сырой JSON официально поддержан
- **Было:** `ModelBuilder` с типизированным DSL (`texture()`, `element()`, `transforms()`).
- **Стало:** `public interface ModelInstance extends Supplier<JsonElement> {}` — и всё.
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/data/models/model/ModelInstance.java:9`;
  живой пример сырого JSON — `/workspace/desolation/src/main/java/raltsmc/desolation/data/DesolationModelProvider.java:138-144`.
- **Комментарий:** это **главная зацепка** для порта модов с кастомным модель-лоадером.
  Форму `{"parent": …, "loader": "<mod>:<loader>"}` вани́льным DSL не выразить, но
  `modelOutput.accept(id, () -> jsonObject)` принимает что угодно. Валидации содержимого нет.

### `ExistingFileHelper` — аналога нет, и это важно в трёх местах
- **Было:** NeoForge проверял, что каждый referenced parent/texture существует, и **мержил** выход
  нескольких провайдеров, пишущих в один файл.
- **Стало:** на Fabric ни того, ни другого.
- **Комментарий:** три следствия, каждое ловится только на глаз:
  1. Ссылка на несуществующий `_spec`-родитель молча пройдёт датаген и упадёт в игре.
  2. **Два `FabricTagsProvider`, пишущих один и тот же тег, затирают друг друга.** У DO
     `minecraft:mineable/pickaxe`, `minecraft:stairs`, `minecraft:doors`, `minecraft:wooden_doors`
     заполнялись двумя разными провайдерами каждый — на NeoForge получалось объединение,
     на Fabric осталась бы половина. Лечится сведением всех sub-provider'ов в **один**
     `FabricTagsProvider`: `TagsProvider#builder(tag)` возвращает один и тот же `TagBuilder` на тег.
  3. Аналогично для моделей, но там не молчаливое затирание, а исключение — см. §3.

---

## 3. Дубликаты и повороты

### Дубликат модели — исключение, а не «перезапись»
- **Было:** `models().withExistingParent(name, parent)` при повторном вызове возвращал закэшированный билдер.
- **Стало:** `ModelProvider$SimpleModelCollector#accept` бросает
  `IllegalStateException("Duplicate model definition for " + id)`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/data/models/ModelProvider.java:159-163`;
  то же для blockstate (`:78`) и для item-модели (`:113`).
- **Комментарий:** DO строит модели во вложенных циклах (facing × shape × half), и на NeoForge это
  работало за счёт кэша. При переносе один в один датаген падает на первом же таком провайдере.
  Решение — обёртка со `Set<Identifier> emitted` (`datagen/utils/ModelCollector#model`).

### Повороты — теперь `Quadrant`, но старые файлы валидны
- **Было:** `ConfiguredModel.rotationX(int)` принимал любой кратный 90, включая `-90` и `450`.
- **Стало:** `Variant.SimpleModelState(Quadrant x, Quadrant y, Quadrant z, boolean uvLock)`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/block/dispatch/Variant.java:65-75`,
  `/opt/mc-src/com/mojang/math/Quadrant.java:14-28`.
- **Комментарий:** кодек **читает** через `Mth.positiveModulo(degrees, 360)`, т.е. `-90`/`360`/`450`
  в уже существующих JSON загружаются нормально; но **пишет** он только `0/90/180/270`.
  То есть перегенерённые blockstate'ы численно разойдутся со старыми, оставаясь эквивалентными.
  Свои значения нормализовать обязательно: `Variant#withXRot` требует уже готовый `Quadrant`.

---

## 4. `forAllStatesExcept` — единственное, чего в ванили нет

- **Было (NeoForge):** `getVariantBuilder(block).forAllStatesExcept(state -> ConfiguredModel[], POWERED)`.
- **Стало (26.2):** ванильный `MultiVariantGenerator` умеет только `PropertyDispatch` — фан-аут по
  одному свойству за раз (`MultiVariantGenerator#with(PropertyDispatch<VariantMutator>)`).
  Для двери с пятью свойствами (`facing`, `half`, `hinge`, `open`, `type`) это неприменимо.
- **Рабочий обход:** собрать `BlockStateModelDispatcher` руками и отдать его как анонимный
  `BlockModelDefinitionGenerator` (интерфейс из двух методов: `Block block()` и
  `BlockStateModelDispatcher create()`):
  ```java
  Map<String, BlockStateModel.Unbaked> variants = new LinkedHashMap<>();
  for (BlockState state : block.getStateDefinition().getPossibleStates()) {
      PropertyValueList key = PropertyValueList.EMPTY;
      for (Property<?> p : state.getProperties())
          if (!skipped.contains(p)) key = key.extend(valueOf(state, p));   // generic capture-хелпер
      variants.putIfAbsent(key.getKey(), factory.apply(state).toUnbaked());
  }
  new BlockStateModelDispatcher(Optional.of(new BlockStateModelDispatcher.SimpleModelSelectors(variants)),
                                Optional.empty());
  // где: <T extends Comparable<T>> Property.Value<T> valueOf(BlockState s, Property<T> p) {
  //          return p.value(s.getValue(p)); }
  ```
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/data/models/blockstates/BlockModelDefinitionGenerator.java:9-13`,
  `/opt/mc-src/net/minecraft/client/renderer/block/dispatch/BlockStateModelDispatcher.java:27-40,78`,
  `/opt/mc-src/net/minecraft/client/data/models/blockstates/PropertyValueList.java:29-31`,
  `/opt/mc-src/net/minecraft/world/level/block/state/properties/Property.java:29`.
- **Комментарий:** `PropertyValueList#getKey()` даёт **ровно** тот же ключ, что писал NeoForge
  (`name=value`, отсортировано по имени свойства, через запятую) — старые blockstate'ы не ломаются.
  `Property.Value<T>` из `Property<?>` достаётся только через отдельный generic-метод (capture).

---

## 5. Теги

### `builder(...)` вместо `tag(...)`, `add` на `ResourceKey`
- **Было:** `this.tag(BlockTags.FENCES).add(block)`; в 26.1 Fabric — `valueLookupBuilder(...)`.
- **Стало:** `builder(TagKey<T>)`, а `TagAppender<T>#add(ResourceKey<T>)`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/data/tags/TagAppender.java:11-32`;
  `/workspace/desolation/src/main/java/raltsmc/desolation/data/DesolationBlockTagProvider.java:20-21`.
- **Комментарий:** ключ произвольного блока — `block.builtInRegistryHolder().key()`,
  предмета — `item.asItem().builtInRegistryHolder().key()`. Для 400+ вызовов дешевле не править
  каждый, а подсунуть свой аппендер с NeoForge-сигнатурами (`add(Block...)`, `addTags(TagKey...)`),
  делегирующий на `TagAppender` — тогда тела провайдеров не меняются вообще.

### `BlockItemTagAppender` и `BlockItemId`
- **Стало:** `FabricTagsProvider.BlockTagsProvider#builder` возвращает не `TagAppender<Block>`,
  а `BlockItemTagAppender<Block>` — у него есть перегрузки `add(BlockItemId...)`,
  `addAll(ColorCollection<ResourceKey<…>>)`, `addAll(WeatheringCopperCollection<…>)`.
- **Подтверждено:** `javap` по `fabric-data-generation-api-v1-25.4.4+9e7dc27f9e.jar`;
  `/opt/mc-src/net/minecraft/data/tags/BlockItemTagAppender.java:10-37`.
- **Грабли:** нельзя объявить в своём подклассе `public MyAppender tag(TagKey<Block>)` — у
  `TagsProvider` уже есть `tag(TagKey<T>)` с другим возвращаемым типом, javac скажет
  «cannot override … return type is not compatible». Свой sink надо делать отдельным объектом
  (лямбдой), а не самим провайдером.

### Один провайдер на реестр
См. §2, пункт 2. У DO это 30 блочных + 2 предметных sub-provider'а, сведённых в два `DataProvider`.

---

## 5a. Ссылка на чужой тег роняет весь `TagsProvider` — и `forceAddTag` это чинит без потери семантики

Самая дорогая грабля всего датагена. Симптом:

```
IllegalArgumentException: Couldn't define tag domum_ornamentum:default as it is missing following references:
#c:end_stones, #minecraft:terracotta, #minecraft:wool, #c:storage_blocks, #c:glass_blocks,
#minecraft:logs, #minecraft:wart_blocks, #c:stones, #c:cobblestones, #c:obsidians,
#minecraft:stone_bricks, #minecraft:base_stone_nether
    at net.minecraft.data.tags.TagsProvider.lambda$run$5(TagsProvider.java:95)
```

- **Было (NeoForge 26.1):** `this.tag(ModTags.GLOBAL_DEFAULT).addTags(BlockTags.LOGS, Tags.Blocks.STONES, …)` —
  `ExistingFileHelper` знал про ванильные и форджевые теги, и ссылка считалась разрешённой.
- **Стало (26.2):** `TagsProvider#run` строит проверку так:
  ```java
  Predicate<Identifier> tagCheck = id -> this.builders.containsKey(id)                       // тег определён в ЭТОМ провайдере
                                      || c.parent.contains(TagKey.create(registryKey, id));  // или в parentProvider
  … entries.stream().filter(e -> !e.verifyIfPresent(elementCheck, tagCheck)) … throw new IllegalArgumentException(…)
  ```
  Никакого «а есть ли такой тег в ванили» тут нет и быть не может: во время датагена ванильные теги
  не загружены, а `c:*` живут в `fabric-convention-tags-v2` как ресурсы, а не как данные датагена.
  **Любая** ссылка на тег, который не определён твоим же провайдером, валит прогон целиком.
- **Подтверждено:** `/opt/mc-src/net/minecraft/data/tags/TagsProvider.java:79-99`;
  `TagEntry#verifyIfPresent` — `/opt/mc-src/net/minecraft/tags/TagEntry.java:90-92`
  (`return !this.required || (this.tag ? tagCheck : elementCheck).test(this.id);`).

### Три варианта лечения и почему подходит только один

| вариант | что попадёт в JSON | вердикт |
|---|---|---|
| `addOptionalTag(tag)` | `{"id": "#minecraft:logs", "required": false}` | **нет.** Расходится с оракулом и, главное, при отсутствии тега молча даёт пустоту |
| определить чужой тег у себя (`builder(BlockTags.LOGS)`) | тег мода перезапишет/дополнит ванильный | **нет.** Меняет смысл: мод начинает владеть ванильным тегом |
| **`forceAddTag(tag)`** (Fabric) | `"#minecraft:logs"` — байт-в-байт как было | **да** |

`FabricTagAppender#forceAddTag` вставляет `net.fabricmc.fabric.impl.datagen.ForcedTagEntry`:
```java
public ForcedTagEntry(Identifier id) { super(id, /*tag*/ true, /*required*/ true); }
@Override public boolean verifyIfPresent(Predicate<Identifier> e, Predicate<Identifier> t) { return true; }
```
То есть валидация датагена пропускается, а `required` остаётся `true` — значит сериализуется
голой строкой (`TagEntry.CODEC`: `required ? Either.left(id) : Either.right(FULL_CODEC)`),
и **отсутствующий в рантайме тег по-прежнему падает громко**, а не вырождается в пустоту.
- **Подтверждено:** `javap -c` по `net/fabricmc/fabric/impl/datagen/ForcedTagEntry.class`,
  `net/fabricmc/fabric/mixin/datagen/TagBuilderMixin.class` (`fabric_forceAddTag`) и
  `net/fabricmc/fabric/mixin/datagen/BlockItemTagAppenderMixin.class` — все в
  `fabric-data-generation-api-v1-25.4.4+9e7dc27f9e.jar`.

### Практическое правило
Разделять по **неймспейсу**, а не по «ванильный/конвенциональный»: для валидации `#minecraft:*` и `#c:*`
неразличимы (оба невидимы датагену), разница только в рантайме — `minecraft:*` есть всегда,
`c:*` есть, пока в зависимостях `fabric-convention-tags-v2`.
```java
public Appender addTag(TagKey<T> tag) {
    if (MOD_ID.equals(tag.location().getNamespace())) delegate.addTag(tag);   // свой тег: проверку оставляем
    else                                              delegate.forceAddTag(tag);
    return this;
}
```
Свои теги через обычный `addTag` — тогда опечатка в имени собственного тега по-прежнему валит датаген,
а это единственное, ради чего эта валидация вообще существует.

**Грабля внутри граблей:** `forceAddTag` — `default`-метод `FabricTagAppender`, тело которого
`throw new AssertionError("Implemented via mixin")`. Реализаций **две**: миксин на анонимный
`TagAppender$1` (то, что отдаёт `TagAppender.forBuilder`) и отдельный `BlockItemTagAppenderMixin`
на `BlockItemTagAppender` (то, что отдаёт `FabricTagsProvider.BlockTagsProvider#builder`).
Оба делегируют в `TagBuilderHooks#fabric_forceAddTag`. Если ты обернул аппендер во **что-то своё**,
зови `forceAddTag` именно на делегате, а не на своей обёртке.

**Ещё:** `FabricTagsProvider.ItemTagsProvider#copy(blockTag, itemTag)` переносит **те же объекты**
`TagEntry` (`blockBuilder.build().forEach(itemBuilder::add)`), поэтому форсированные записи остаются
форсированными и после `copy` — отдельно чинить item-сторону не нужно.

---

## 6. Лут

- **Было:** `LootTableProvider(packOutput, Set.of(), List.of(new SubProviderEntry(X::new, LootContextParamSets.BLOCK)), provider)`
  + `BlockLootSubProvider(Set<Item>, FeatureFlagSet, HolderLookup.Provider)` + `getKnownBlocks()`.
- **Стало:** `FabricBlockLootSubProvider(FabricPackOutput, CompletableFuture<HolderLookup.Provider>)`,
  сам является `DataProvider`; абстрактный метод — `public void generate()`.
- **`getKnownBlocks()` в 26.2 нет.** Ванильный `BlockLootSubProvider#generate(BiConsumer)` теперь
  обходит **весь** `BuiltInRegistries.BLOCK` и бросает `Missing loottable '%s' for '%s'`.
  Fabric переопределяет этот метод: отдаёт только то, что реально сгенерировано, а проверку
  «на каждый блок мода есть таблица» делает **лишь при включённой strict validation**.
- **Подтверждено:** `/opt/mc-src/net/minecraft/data/loot/BlockLootSubProvider.java:839-866`;
  `javap -c` по `FabricBlockLootSubProvider` (ветка `isStrictValidationEnabled` → `Missing loot table(s) for %s`);
  `/workspace/desolation/src/main/java/raltsmc/desolation/data/DesolationBlockLootTableProvider.java:20-23`.
- **Следствие:** несколько `FabricBlockLootSubProvider`, покрывающих непересекающиеся блоки, — законно.
- **Ещё одна ломка:** `CopyComponentsFunction.copyComponents(CopyComponentsFunction.Source.BLOCK_ENTITY)`
  → `CopyComponentsFunction.copyComponentsFromBlockEntity(LootContextParams.BLOCK_ENTITY)`
  (`/opt/mc-src/net/minecraft/world/level/storage/loot/functions/CopyComponentsFunction.java:102`,
  `/opt/mc-src/net/minecraft/world/level/storage/loot/parameters/LootContextParams.java:23`).
  JSON на выходе тот же: `{"function":"minecraft:copy_components","source":"block_entity","include":[…]}`.

---

## 7. Рецепты

- **Было:** `class X extends RecipeProvider` + `protected void buildRecipes(RecipeOutput)`,
  статические `ShapedRecipeBuilder.shaped(category, item, count)` и `has(...)`.
- **Стало:** двухслойно.
  ```java
  class X extends FabricRecipeProvider {                       // = RecipeProvider.Runner, это DataProvider
      protected RecipeProvider createRecipeProvider(HolderLookup.Provider lookup, RecipeOutput out) {
          return new RecipeProvider(lookup, out) {             // ctor (HolderLookup.Provider, RecipeOutput)
              @Override public void buildRecipes() { … }       // без аргументов!
          };
      }
  }
  ```
- **Подтверждено:** `/opt/mc-src/net/minecraft/data/recipes/RecipeProvider.java:102` (ctor), `:111`
  (`public abstract void buildRecipes()`), `:1192` (`Runner`);
  `/workspace/desolation/src/main/java/raltsmc/desolation/data/DesolationRecipeProvider.java:21-33`.
- **Грабли:**
  - `ShapedRecipeBuilder.shaped(...)` / `ShapelessRecipeBuilder.shapeless(...)` получили **первым**
    аргументом `HolderGetter<Item>` (`ShapedRecipeBuilder.java:40,44`). Публичного конструктора нет.
    Пользоваться надо унаследованными `this.shaped(category, item[, count])` /
    `this.shapeless(...)` (`RecipeProvider.java:1147-1175`).
  - `has(...)` стал **инстанс-методом** `RecipeProvider` (`:1069,1076`) — внутри анонимного класса
    работает как раньше, снаружи нет.
  - `FabricRecipeProvider#getRecipeIdentifier(Identifier)` переопределять нужно только если
    результат рецепта — ванильный предмет (иначе id уедет в `minecraft:`).

---

## 8. Язык

- **Было:** внешний `com.ldtteam.data.LanguageProvider` с вложенными `SubProvider` / `LanguageAcceptor`.
- **Стало:** `FabricLanguageProvider(FabricPackOutput, String languageCode, CompletableFuture<HolderLookup.Provider>)`,
  абстрактный `generateTranslations(HolderLookup.Provider, TranslationBuilder)`.
- **Подтверждено:** `javap` по `fabric-data-generation-api-v1`.
- **Грабли:** `TranslationBuilder#add` **бросает** на повторный ключ. Если у мода есть свой слой
  sub-provider'ов, безопаснее собрать всё в `LinkedHashMap` и вылить одним махом — тогда поведение
  «последний выигрывает» сохраняется. Выход сортируется (`TreeMap`), как и у большинства старых провайдеров.
- **Приём для внешней либы без 26.x-сборки:** воспроизвести её вложенные интерфейсы в своём классе с
  тем же именем (`datagen/LanguageProvider.java` с `SubProvider`/`LanguageAcceptor`) — тогда в
  23 файлах sub-provider'ов меняется ровно одна строка `import`.

---

## 9. 26.2: id-split задел ещё и константы блоков (не только теги)

Это не про датаген как таковой, но ловится именно в нём, потому что теги — главный потребитель `Blocks.*`.

| было | стало |
|---|---|
| `Blocks.<COLOR>_CONCRETE` | `Blocks.CONCRETE.pick(DyeColor.<COLOR>)` |
| `Blocks.<COLOR>_GLAZED_TERRACOTTA` | `Blocks.GLAZED_TERRACOTTA.pick(DyeColor.<COLOR>)` |
| `Blocks.<COLOR>_WOOL` | `Blocks.WOOL.pick(DyeColor.<COLOR>)` |
| `Blocks.COPPER_BLOCK` | `Blocks.COPPER_BLOCK.weathering().unaffected()` |
| `Blocks.WAXED_EXPOSED_CUT_COPPER` | `Blocks.CUT_COPPER.waxed().exposed()` |
| `Blocks.OXIDIZED_COPPER_GRATE` | `Blocks.COPPER_GRATE.weathering().oxidized()` |
| `DyeItem.byColor(color)` | `Items.DYE.pick(color)` |

- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/Blocks.java:755` (`WOOL`), `:3665`
  (`GLAZED_TERRACOTTA`), `:3676` (`CONCRETE`), `:4997,5023,5030,5074` (медь);
  `/opt/mc-src/net/minecraft/world/level/block/ColorCollection.java:16,90` (`pick`);
  `/opt/mc-src/net/minecraft/world/level/block/WeatheringCopperCollection.java:15,128-146`
  (`weathering()`/`waxed()` → `ByState<T>` с `unaffected/exposed/weathered/oxidized`);
  `/opt/mc-src/net/minecraft/world/item/Items.java:1297` (`ColorCollection<Item> DYE`).
- **Комментарий:** `ColorCollection`/`WeatheringCopperCollection` — обычные `record`-ы с
  `asList()`, `forEach()`, `map()`, `pick(...)`. Если порядок в теге не важен,
  `family.asList().toArray(new Block[0])` короче на порядок.
  **Осторожно с regex-заменами:** наивный `s/Blocks.COPPER_BLOCK/…weathering().unaffected()/`
  сначала переписывает короткое имя, а потом ест собственный результат внутри
  `Blocks.WAXED_EXPOSED_COPPER`. Заменять от длинных имён к коротким либо руками.

---

## 10. `assets/<ns>/items/` генерируется сам — и не туда, куда нужно

- **Стало:** ванильный `ModelProvider$ItemInfoCollector#finalizeAndValidate` для **каждого**
  `BlockItem`, у которого нет явной записи, сам дописывает
  `{"model":{"type":"minecraft:model","model":"<ns>:block/<name>"}}`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/data/models/ModelProvider.java:123-131`;
  фильтр по namespace + `processedBlocks` — в
  `net/fabricmc/fabric/mixin/datagen/client/ModelProviderItemInfoCollectorMixin`
  (`fabric-data-generation-api-v1.client.mixins.json`).
- **Комментарий:** для мода, у которого модели блоков лежат в подпапках
  (`block/fence/fence_post`, а не `block/vanilla_fence_compat`), автозаполнение сгенерирует
  ссылку на несуществующую модель — **молча**, потому что валидации ссылок нет (§2).
  Правильно — явно звать `itemModelOutput.accept(item, ItemModelUtils.plainModel(<нужный id>))`.
  И обязательно пропускать блоки без предмета: `block.asItem()` вернёт `Items.AIR`, и датаген
  запишет `assets/minecraft/items/air.json` в выход мода.

---

## 10a. Item-модели 1.21.4+ — самая дорогая ломка диапазона (и почему предмет становится невидимым)

Стоила живого бага: **все предметы Domum Ornamentum с вариантами рисовались пустым слотом** — тултип
есть, геометрии нет. Блоки при этом ставились и выглядели правильно, то есть блочный конвейер был цел.

### Что именно умерло
- **`"overrides"` в `models/item/*.json`** больше не читается (с 1.21.4). Ключ не вызывает ошибки —
  его просто игнорируют.
- **`ItemProperties.register(item, id, (stack, level, entity, seed) -> float)`**, который эти
  `overrides` и питал, в 26.2 отсутствует как класс.
- Итог для мода, портированного «байт-в-байт по оракулу»: файл вида
  ```json
  { "parent": "minecraft:block/thin_block",
    "overrides": [ {"model": "…/panel_boss_spec", "predicate": {"domum_ornamentum:trapdoor_type": 0.0}}, … ] }
  ```
  теряет **всю** геометрию: собственных `elements` у него нет, `minecraft:block/thin_block` —
  абстрактный родитель без геометрии, а `overrides` мёртв. Рисовать нечего → прозрачный слот.
  **«Совпало с оракулом» здесь означает «воспроизвели мёртвый формат».**

### Как быстро найти все такие предметы, не запуская игру
Прогнать цепочку `parent` каждой item-модели и посмотреть, чем она заканчивается. Ломаными
считаются те, что упираются в абстрактного ванильного родителя
(`minecraft:block/thin_block`, `minecraft:block/block`) или в файл вообще без `parent` и без `elements`:

```python
ABSTRACT = {'minecraft:block/thin_block', 'minecraft:block/block'}
def chain(mid):
    cur = mid
    for _ in range(12):
        d = load(cur)                       # из resources ∪ выхода датагена
        if d is None:      return cur       # ванильная или отсутствующая
        if 'elements' in d: return 'OK'
        if 'parent' not in d: return 'NO-GEOMETRY ' + str(sorted(d))
        cur = d['parent']
```
У Domum Ornamentum из 104 item-моделей так вскрылось ровно 6 (+ их `_spec`-спутники) — и это в точности
те 6 предметов, для которых в 26.1 регистрировался `ItemProperties`. Совпадение не случайно: сломано
ровно то, что зависело от `overrides`.

### Замена: `minecraft:select` в item-model-definition

`assets/<ns>/items/<item_id>.json`:
```json
{ "model": {
    "type": "minecraft:select",
    "property": "minecraft:block_state",
    "block_state_property": "type",
    "cases": [ { "when": "waffle",
                 "model": { "type": "minecraft:model", "model": "domum_ornamentum:item/panel_waffle" } }, … ],
    "fallback": { "type": "minecraft:model", "model": "domum_ornamentum:item/panel_full" } } }
```
Точные имена полей (не из документации, а из кодеков):
- `ClientItem.CODEC` → верхний уровень `{"model": …}`
  (`/opt/mc-src/net/minecraft/client/renderer/item/ClientItem.java:13-17`);
- `ItemModels.CODEC` — диспатч по `"type"`, список зарегистрированных типов:
  `empty`, `model`, `range_dispatch`, `special`, `composite`, `bundle/selected_item`, `select`, `condition`
  (`.../item/ItemModels.java:20-30`);
- `SelectItemModel.Unbaked.MAP_CODEC` → `transformation?` + инлайновый switch + `fallback?`
  (`.../item/SelectItemModel.java:73-80`);
- `UnbakedSwitch.MAP_CODEC = SelectItemModelProperties.CODEC.dispatchMap("property", …)` → поле `"property"`
  (`:103`), список свойств — `.../properties/select/SelectItemModelProperties.java:20-31`;
- поле `"cases"` и внутри каждого — `"when"` (одно значение **или** список, `compactListCodec`) и `"model"`
  (`SelectItemModelProperty.Type#createCasesFieldCodec` `:42-44`, `SelectItemModel.SwitchCase#codec` `:59-67`).

### `minecraft:block_state` или `minecraft:component`?
Оба существуют, выбирать надо по тому, **где реально лежит значение**:
- `ItemBlockState` (`"property": "minecraft:block_state"`, поле `"block_state_property"`) читает
  `stack.get(DataComponents.BLOCK_STATE).properties().get(<имя>)` и отдаёт **строку**
  (`.../properties/select/ItemBlockState.java:24-29`);
- `ComponentContents` (`"property": "minecraft:component"`, поле `"component"`) отдаёт **значение компонента
  целиком**, и сравнение идёт по нему же (`.../properties/select/ComponentContents.java:22-37`).

Если мод, как DO, пишет вариант через `stack.update(DataComponents.BLOCK_STATE, …, props -> props.with(property, value))`,
то нужен именно `block_state`: `component` заставил бы сравнивать целиком карту `BlockItemStateProperties`.

### Не собирать JSON руками — есть ванильный хелпер
```java
ItemModelUtils.selectBlockItemProperty(Property<T> property,
                                       ItemModel.Unbaked fallback,
                                       Map<T, ItemModel.Unbaked> cases)
```
(`/opt/mc-src/net/minecraft/client/data/models/model/ItemModelUtils.java:176-180`) — сам берёт имя свойства
(`property.getName()`) и сериализованное имя каждого значения (`property.getName(value)`), сортирует кейсы
и строит `new ItemBlockState(...)`. Рядом: `select(...)`, `when(value, model)`, `rangeSelect(...)`,
`condition/hasComponent`, `inOverworld`, `isXmas`.

### Грабля с display-трансформами
`"cases"` подставляет **модель целиком**, вместе с её `display`
(`ModelRenderProperties.fromResolvedModel` → `resolvedModel.getTopTransforms()`,
`/opt/mc-src/net/minecraft/client/renderer/item/ModelRenderProperties.java:14-17`). Если направить кейс
прямо на блочную модель, у которой `display` нет, предмет **станет виден, но нарисуется неповёрнутым**.
Дешёвое решение — на каждый вариант генерировать крошечную item-модель
`{"parent": "<блочная модель варианта>", "display": {…}}` и указывать в кейсе её.
(В старом `overrides`-мире это тоже терялось — там кейс тоже подменял модель целиком, — так что
трансформы заодно чинятся.)

### Блоки, у которых нет своего провайдера, `items/*.json` не получают вообще
Ванильный автозаполнитель (§10) срабатывает только для блоков, обработанных **этим** провайдером
(фильтр `processedBlocks` в `ModelProviderItemInfoCollectorMixin`). Блок с рукописным blockstate'ом
мимо датагена останется совсем без item-definition и нарисуется чёрно-фиолетовым «missing model».
Для таких надо явно звать `itemModelOutput.accept(item, ItemModelUtils.plainModel(<рукописная модель>))`.

**Итоговая шпаргалка ломки:**

| 1.20/NeoForge | 26.2 |
|---|---|
| `models/item/x.json` → `"overrides": [{"predicate": {"mod:p": n}, "model": …}]` | `assets/<ns>/items/x.json` → `{"model":{"type":"minecraft:select", …}}` |
| `ItemProperties.register(item, id, fn)` | ничего: свойство выбирается декларативно из `SelectItemModelProperties` |
| `predicate` по float-ординалу | `"when"` по строковому значению blockstate-свойства или по значению компонента |
| модель предмета = `models/item/x.json` | модель предмета = `items/x.json`, а `models/item/x.json` — лишь геометрия, на которую он ссылается |

---

## 11. Обвязка сборки

- `fabricApi { configureDataGeneration { client = true } }` — `client = true` обязателен, иначе
  `FabricModelProvider` (он в `net.fabricmc.fabric.api.client.datagen.v1`) недоступен рантайму датагена.
- Loom монтирует `src/main/generated` **как ещё один resource-root главного sourceSet**
  (`/workspace/desolation/build.gradle:121-142` — там это прямо описано в комментарии).
  **Грабля:** если мод уже везёт сгенерированный контент в `src/main/resources` (типичная ситуация,
  когда датаген портируют не первым), после первого `runDatagen` `processResources` увидит каждый
  файл дважды. Лечится либо `duplicatesStrategy`, либо удалением дублей из `src/main/resources`.
- Строгая валидация (`strictValidation`) по умолчанию **выключена**. Именно поэтому
  «неполный» датаген не падает, а молча пишет что есть: и отсутствующие blockstate'ы, и
  отсутствующие лут-таблицы, и отсутствующие item-модели проверяются только под ней.
- `FabricDataGenerator.Pack#addProvider` имеет две формы: `Factory<T>` (`FabricPackOutput -> T`) и
  `RegistryDependentFactory<T>` (`(FabricPackOutput, CompletableFuture<HolderLookup.Provider>) -> T`);
  вторая нужна, когда провайдеру надо передать ещё что-то (например блочный tag-провайдер в item-овый):
  `pack.addProvider((output, registries) -> new MyItemTags(output, registries, blockTags));`

---

## 12. Формат данных: то, что ломается молча

- **Ингредиенты рецептов.** `Ingredient.CODEC` — `HolderSetCodec` над `Registries.ITEM`:
  принимает **строку** (`"minecraft:iron_ingot"`), **строку с `#`** (`"#c:strings"`) или список строк.
  Объектную форму `{"item": …}` / `{"tag": …}` он отвергает. Уже скопированные из старой версии
  рецепты надо конвертировать — в ките для этого лежит `porting-26.2/fix-recipes.py`
  (принимает путь к каталогу рецептов аргументом, идемпотентен, чужие `type`-ы не трогает).
  У Domum Ornamentum так чинились 56 из 136 файлов; остальные 80 — рецепты собственного
  сериализатора, у которых ингредиентов в JSON нет.
- **Item-model-definition (`assets/<ns>/items/<id>.json`)** обязателен с 1.21.4. Мод, портируемый
  с NeoForge 26.1, их скорее всего не содержит вовсе: NeoForge держал совместимость со старым
  `models/item/<id>.json`. Отсутствие файла не ломает сервер, но в клиенте предмет — «отсутствующая модель».
- **`"overrides"` в item-моделях мёртв** с 1.21.4. Ключ не вызывает ошибки, его просто никто не читает —
  и именно поэтому баг молчаливый: предмет становится невидим. Разбор целиком — §10a.
- **`DataProvider` сортирует ключи JSON** (`GsonHelper.writeValue(writer, root, KEY_COMPARATOR)`,
  `/opt/mc-src/net/minecraft/data/DataProvider.java:88`). Перегенерённые файлы будут отличаться от
  NeoForge-овских порядком ключей — это нормально и на diff-сверку с «оракулом» надо делать поправку.
