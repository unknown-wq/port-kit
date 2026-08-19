# FINDINGS-B2 — копилка знаний агента B2 (Structurize → Fabric / MC 26.2)

Зона: `placement/**`, `storage/**`, `util/**` (кроме `WorldRenderMacros`), `operations/**`,
`blueprints/**`, `client/gui/util/ItemPositionsStorage.java`.

Только то, чего **не было** в порт-ките и в `FINDINGS-A.md`. Каждая находка с подтверждением.

---

## Самое дорогое: `/opt/mc-src` уже с применённым AccessWidener'ом

### `fabric-transitive-access-wideners-v1` расширяет доступ ещё до нашего `.accesswidener`
- **Было:** ожидание, что «protected/private в `/opt/mc-src`» = «недоступно из мода».
- **Стало:** 519 мест в `/opt/mc-src` помечены комментарием
  `Access widened by fabric-transitive-access-wideners-v1 to accessible` — Loom применяет
  транзитивные AW из fabric-api **автоматически**, до и независимо от нашего
  `structurize.accesswidener`.
- **Подтверждено:** `grep -rn 'Access widened by fabric-transitive-access-wideners' /opt/mc-src/ | wc -l` → 519;
  `/opt/mc-src/net/minecraft/world/item/context/BlockPlaceContext.java:28-31`.
- **Комментарий:** в кэше Loom проекта лежат **два** ремапнутых jar'а:
  ```
  .gradle/loom-cache/minecraftMaven/net/minecraft/minecraft-merged-043a8b3edf/26.2/…  # только транзитивные AW fabric-api
  .gradle/loom-cache/minecraftMaven/net/minecraft/minecraft-merged-36d31c239f/26.2/…  # + наш structurize.accesswidener
  ```
  Прогон javac по второму даёт настоящую картину без ложных срабатываний.
  `typecheck.sh` с тех пор переключён на него (берёт самый новый по mtime).
  Практический вывод: **прежде чем чинить `has protected access`, посмотри в `/opt/mc-src`, нет ли
  там комментария про transitive-access-wideners** — чинить нечего.
- Конкретно на зоне B2 это `BlockPlaceContext(Level, Player, InteractionHand, ItemStack, BlockHitResult)`:
  в `/opt/mc-src` он `public` с этим комментарием, в сыром deobf-jar — `protected`.

---

## NBT / ValueInput / ValueOutput

### `Entity#save` / `Entity#load` перешли на `ValueOutput` / `ValueInput`, `EntityType.by` — тоже
- **Было:** `entity.save(CompoundTag)`, `entity.load(CompoundTag)`, `EntityType.by(CompoundTag)`,
  `type.create(Level)`.
- **Стало:**
  ```java
  final ValueInput in = TagValueInput.create(ProblemReporter.DISCARDING, level.registryAccess(), tag);
  final Optional<EntityType<?>> type = EntityType.by(in);
  final Entity e = type.get().create(level, EntitySpawnReason.LOAD);
  e.load(in);

  final TagValueOutput out = TagValueOutput.createWithContext(ProblemReporter.DISCARDING, level.registryAccess());
  e.save(out);
  final CompoundTag result = out.buildResult();
  ```
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/entity/Entity.java:2061,2139`;
  `EntityType.java:300,342`; `world/level/storage/TagValueInput.java:40`;
  `TagValueOutput.java:27,152`; `util/ProblemReporter.java:18`.
- **Комментарий:** `TagValueInput.create` берёт **сырой** `CompoundTag` — это официальный мост
  legacy-кода в новый API, писать свой не надо. `EntitySpawnReason.LOAD` — правильный режим
  для десериализации из NBT (`EntitySpawnReason.java:21`). Ровно этот паттерн повторился в
  4 файлах: `blueprints/v1/Blueprint`, `blueprints/v1/BlueprintUtils`, `placement/StructurePlacer`,
  `util/ChangeStorage`.

### `BlockEntity#saveWithFullMetadata(HolderLookup.Provider)` **жив** (уточнение к FINDINGS-A)
- FINDINGS-A утверждает, что `saveWithId(Provider)`/`saveToItem` удалены и остались только
  `ValueOutput`-варианты. Для `saveWithFullMetadata` это **не так**: перегрузка с `Provider`,
  возвращающая `CompoundTag`, на месте и работает без обходных путей.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/entity/BlockEntity.java:112`
  (`public final CompoundTag saveWithFullMetadata(final HolderLookup.Provider registries)`),
  рядом `:120` — `ValueOutput`-перегрузка.

### `BlockEntity#loadWithComponents` — один аргумент, `ValueInput`
- **Было:** `be.loadWithComponents(CompoundTag, HolderLookup.Provider)`.
- **Стало:** `be.loadWithComponents(ValueInput)`;
  `be.loadWithComponents(TagValueInput.create(ProblemReporter.DISCARDING, level.registryAccess(), tag))`.
- **Подтверждено:** `BlockEntity.java:100,186`.

### `CompoundTag#store(String, Codec, T)` заменяет `putUUID`
- **Было:** `tag.putUUID("UUID", uuid)`.
- **Стало:** `tag.store("UUID", UUIDUtil.CODEC, uuid)` — формат тот же (int[4]).
- **Подтверждено:** `CompoundTag.java:490`; `/opt/mc-src/net/minecraft/core/UUIDUtil.java:23`.

### `ListTag`: типизированного `getList(String, int)` больше нет
- **Было:** `tag.getList("x", Tag.TAG_COMPOUND)`, `list.getCompound(i)`, `list.getDouble(i)`,
  `list.getString(i)`.
- **Стало:** `tag.getListOrEmpty("x")`; у самого `ListTag` — `getCompoundOrEmpty(int)`,
  `getDoubleOr(int, double)`, `getStringOr(int, String)`, `getIntOr`, `getShortOr`, `getFloatOr`.
  Голые `getX(int)` возвращают `Optional`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/nbt/ListTag.java:254-314`;
  `CompoundTag.java:359,363`.

### `Tag#getAsString()` → `Tag#asString()` и он `Optional<String>`
- **Подтверждено:** `/opt/mc-src/net/minecraft/nbt/Tag.java:51`.

---

## Мир, блоки, предметы

### `ChunkPos` стал `record` — поля `x`/`z` больше не читаются напрямую
- **Было:** `pos.x`, `pos.z`. **Стало:** `pos.x()`, `pos.z()`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/ChunkPos.java:19`.
- **Комментарий:** javac ругается «`x` has private access in ChunkPos» — легко принять за
  проблему AccessWidener'а, но это обычный record.

### `DimensionType#ultraWarm()` удалён — уехал в `EnvironmentAttributes`
- **Было:** `level.dimensionType().ultraWarm()`.
- **Стало:** `level.environmentAttributes().getDimensionValue(EnvironmentAttributes.WATER_EVAPORATES)`.
- **Подтверждено:** `ultraWarm` — **0 вхождений** во всём `/opt/mc-src`;
  `/opt/mc-src/net/minecraft/world/attribute/EnvironmentAttributes.java:110`;
  `EnvironmentAttributeSystem.java:104` (`getDimensionValue`), `:114` (`getValue(attr, Vec3, interp)`);
  `Level.java:1103` (`public abstract EnvironmentAttributeSystem environmentAttributes()`).
- **Комментарий:** весь блок «свойств измерения» (`natural`, `piglinSafe`, `bedWorks`, …) переехал
  в `EnvironmentAttributeMap`/`EnvironmentAttributes`; `DimensionType` — record с полем
  `EnvironmentAttributeMap attributes`, старых булевых аксессоров у него нет.

### `FarmBlock` → `FarmlandBlock`
- **Подтверждено:** `ls /opt/mc-src/net/minecraft/world/level/block/` — есть `FarmlandBlock.java`,
  `FarmBlock.java` отсутствует.

### `DirectionProperty` удалён → `EnumProperty<Direction>`
- **Подтверждено:** в `/opt/mc-src/net/minecraft/world/level/block/state/properties/` остался только
  `EnumProperty.java`; `BlockStateProperties.java:53,57`; `HorizontalDirectionalBlock.java:11`.

### `DripstoneThickness` → `SpeleothemThickness`
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/state/properties/SpeleothemThickness.java:5`;
  `BlockStateProperties.java:138`; `PointedDripstoneBlock.java:65`.

### Крашеная терракота стала `ColorCollection<Block>`
- **Было:** `Blocks.PINK_GLAZED_TERRACOTTA`, `Blocks.MAGENTA_GLAZED_TERRACOTTA`, …
- **Стало:** `Blocks.GLAZED_TERRACOTTA.pick(DyeColor.PINK)` — одна константа
  `ColorCollection<Block> GLAZED_TERRACOTTA`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/Blocks.java:3665`;
  `/opt/mc-src/net/minecraft/world/level/block/ColorCollection.java:15,90` (`pick(DyeColor)`).
- **Комментарий:** то же самое случилось с шалкерами (`DYED_SHULKER_BOX`), бетоном, коврами и т.д. —
  ищи `ColorCollection.registerBlocks` в `Blocks.java`, прежде чем чинить «пропавшую» константу.

### `Entity#moveTo(...)` → `Entity#snapTo(...)`
- Все перегрузки (`Vec3`, `double x,y,z`, `+yRot,xRot`, `BlockPos`) переименованы 1:1.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/entity/Entity.java:1784-1800`.

### `BucketItem#content` protected, но есть публичный `getContent()`
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/item/BucketItem.java:35,159`.

### `LiquidBlock#fluid` protected и геттера нет — брать через `FluidState`
- **Было:** `((LiquidBlock) block).fluid.getBucket()`.
- **Стало:** `blockState.getFluidState().getType().getBucket()`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/LiquidBlock.java:58,130`.

### `ItemStack#getCraftingRemainingItem()` был NeoForge; ваниль — `Item#getCraftingRemainder()`
- **Стало:**
  ```java
  final ItemStackTemplate rem = stack.getItem().getCraftingRemainder();
  final ItemStack container = rem == null ? ItemStack.EMPTY : rem.create();
  ```
  Возвращается **`ItemStackTemplate`**, не `ItemStack`; стек делает `create()`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/item/Item.java:284`;
  `/opt/mc-src/net/minecraft/world/item/ItemStackTemplate.java:19,78`.

### `GameData.getBlockItemMap()` (NeoForge) → `Item.BY_BLOCK`
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/item/Item.java:109`, рядом `:131` — `Item.byBlock(Block)`.

### `ResourceKey#location()` → `ResourceKey#identifier()`
- **Подтверждено:** `/opt/mc-src/net/minecraft/resources/ResourceKey.java:64,68`.
- **Комментарий:** следствие переименования `ResourceLocation` → `Identifier`, но метод
  переименован тоже — `location()` не осталось даже как deprecated.

### `RegistryAccess#registryOrThrow` → `lookupOrThrow`
- `registryOrThrow` — 0 вхождений. И `Registry<T> extends … HolderLookup.RegistryLookup<T>`
  (`Registry.java:26`), поэтому `NbtUtils.readBlockState(HolderGetter<Block>, tag)` принимает
  `BuiltInRegistries.BLOCK` напрямую (`NbtUtils.java:127`) — `asLookup()` больше не нужен.

### `Level#markAndNotifyBlock` — это был NeoForge
- Ванильного аналога-одной-строкой нет; клиентскую половину делает
  `level.sendBlockUpdated(pos, oldState, newState, flags)` (`Level.java:313`),
  соседей — `level.blockUpdated(...)`.
- **Комментарий:** в Structurize оба call-site'а (undo/redo в `ChangeStorage`) шли **сразу после**
  полноценного `level.setBlock(pos, state, UPDATE_FLAG)`, который уже делает и рассылку, и
  обновление соседей. Замена на `sendBlockUpdated` эквивалентна по наблюдаемому поведению.

### `BlockState#getCloneItemStack` — публичная точка входа только на `BlockState`
- Уточнение к FINDINGS-A: `BlockBehaviour#getCloneItemStack(LevelReader, BlockPos, BlockState, boolean)`
  **protected**, звать её у блока извне нельзя. Публичный вход —
  `blockState.getCloneItemStack(LevelReader, BlockPos, boolean includeData)`.
- **Подтверждено:** `BlockBehaviour.java:408` (protected) и `:894` (public, на `BlockState`).
- **Комментарий:** для `CropBlock` реализация игнорирует level/pos (`CropBlock.java:175-176`),
  поэтому `blockState.getCloneItemStack(null, null, false)` безопасно.

### `SurfaceRules$Context` — конструктор и `updateY` поменяли форму
- **Было (1.21.1):** `Context(SurfaceSystem, RandomState, ChunkAccess, NoiseChunk,
  Function<BlockPos,Holder<Biome>>, Registry<Biome>, WorldGenerationContext)` и
  `updateY(int,int,int,int,int,int)`.
- **Стало (26.2):** `Context(SurfaceSystem, RandomState, ChunkAccess, NoiseChunk,
  Function<BlockPos,Holder<Biome>>, WorldGenerationContext, @Nullable Set<Holder<Biome>> possibleBiomes)`
  — **`Registry<Biome>` из сигнатуры убран, в хвост добавлен nullable набор биомов**;
  `updateY(stoneDepthAbove, stoneDepthBelow, waterHeight, blockY)` — четыре аргумента.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/levelgen/SurfaceRules.java:311-320,337`.
- **Комментарий:** PORT-STATUS обещал только смену арности `updateY`; про перестановку аргументов
  конструктора там ничего нет. `possibleBiomes` можно передавать `null`.

### `LevelHeightAccessor`: `getMaxBuildHeight()` = `getMaxY() + 1`
- FINDINGS-A даёт только `getMinBuildHeight() → getMinY()` (значения совпадают).
  Для верха значения **не совпадают**: 1.21.1 `getMaxBuildHeight()` = `minY + height`,
  26.2 `getMaxY()` = `minY + height - 1`. Механическая замена без `+1` сдвигает границу цикла.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/LevelHeightAccessor.java:11-13`.

### `ChunkPalettedStorageFix.FLOWER_POT_MAP` / `NOTE_BLOCK_MAP` спрятаны в приватный вложенный класс
- **Стало:** `private static final Map<String, Dynamic<?>>` внутри
  `ChunkPalettedStorageFix$MappingConstants`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/util/datafix/fixes/ChunkPalettedStorageFix.java:196,237,835,919`.
- **Комментарий:** именно поэтому две строки AT Structurize оказались «мёртвыми» (см. FINDINGS-A) —
  они мертвы не потому, что полей нет, а потому, что сменился владелец. Оживить можно тремя
  строками AccessWidener:
  ```
  accessible	class	net/minecraft/util/datafix/fixes/ChunkPalettedStorageFix$MappingConstants
  accessible	field	net/minecraft/util/datafix/fixes/ChunkPalettedStorageFix$MappingConstants	FLOWER_POT_MAP	Ljava/util/Map;
  accessible	field	net/minecraft/util/datafix/fixes/ChunkPalettedStorageFix$MappingConstants	NOTE_BLOCK_MAP	Ljava/util/Map;
  ```

---

## Fabric-специфика

### `net.fabricmc.fabric.api.entity.FakePlayer` — замена NeoForge `FakePlayer`, но конструктор закрыт
- **Стало:** `FakePlayer.get(ServerLevel)` / `FakePlayer.get(ServerLevel, GameProfile)`;
  конструктор `protected`. Класс `extends ServerPlayer`, лежит в модуле
  **`fabric-events-interaction-v0`** (не в entity-модуле, как можно подумать по пакету).
- **Подтверждено:** `javap` из `fabric-events-interaction-v0-5.2.6+8f57f7ee9e.jar`.
- **Грабли:** `get(...)` кэширует инстанс на `ServerLevel` — это **не** новый объект на каждый вызов.
  Код, который менял состояние fake-игрока (`setItemInHand`, `setYRot`), теперь мутирует общий
  инстанс. В Structurize это безопасно (всё в одном тике, синхронно), но в общем случае — источник
  тихих багов.

### `@OnlyIn(Dist.CLIENT)` → `@Environment(EnvType.CLIENT)`, **не** «просто удалить»
- Fabric Loader физически вырезает `@Environment`-помеченные поля/методы/классы на «чужой» стороне
  (`net.fabricmc.loader.impl.transformer.EnvironmentStrippingData`) — семантика ровно как у `@OnlyIn`.
- **Комментарий:** удалять аннотацию нельзя. В общем классе (`storage/rendering/types/BlueprintPreviewData`)
  тела клиентских методов ссылаются на `Minecraft`/`ClientLevel`; на выделенном сервере этих классов
  нет вовсе, а верификатор HotSpot проверяет **все** методы класса при линковке — без стриппинга
  загрузка `BlueprintPreviewData` на dedicated server кончается `NoClassDefFoundError`.

### `ModList` / `IModInfo` → `FabricLoader` / `ModContainer`
- **Стало:**
  ```java
  for (final ModContainer mod : FabricLoader.getInstance().getAllMods()) {
      final String modId = mod.getMetadata().getId();
      mod.findPath("blueprints/" + modId).ifPresent(modPaths::add);   // Optional<Path>!
      modList.add(modId);
  }
  ...
  FabricLoader.getInstance().isModLoaded(id)
  ```
- **Подтверждено:** `javap net.fabricmc.loader.api.FabricLoader` / `ModContainer` из
  `fabric-loader-0.19.3.jar`.
- **Грабли:** NeoForge `findResource` возвращал `Path`, существующий или нет; Fabric `findPath`
  возвращает **пустой `Optional`**, если ресурса нет. Оригинальный код Structurize брал «владельца»
  пака как `modPath.toString().split("/")[1]` — с реальным `Path` это мусор; правильно
  `modPath.getFileName().toString()`.

### Соответствие событий NeoForge → Fabric, использованное в зоне B2

| NeoForge | Fabric | Модуль |
|---|---|---|
| `ServerTickEvent.Post` | `ServerTickEvents.END_SERVER_TICK` → `(MinecraftServer)` | `fabric-lifecycle-events-v1` |
| `LevelTickEvent.Post` | `ServerTickEvents.END_LEVEL_TICK` → `(ServerLevel)` | `fabric-lifecycle-events-v1` |
| `ClientTickEvent.Post` | `ClientTickEvents.END_CLIENT_TICK` → `(Minecraft)` | `fabric-lifecycle-events-v1` |
| `ClientTickEvent.Pre` (+`EventPriority.HIGHEST`) | `ClientTickEvents.START_CLIENT_TICK` | `fabric-lifecycle-events-v1` |
| `PlayerEvent.PlayerLoggedOutEvent` | `ServerPlayConnectionEvents.DISCONNECT` → `(handler, server)`, игрок в `handler.player` | `fabric-networking-api-v1` |

- **Грабли:** `PlayerLoggedOutEvent` в NeoForge приходил **на обе стороны** (у Structurize на клиенте
  он чистил `RenderingCache`), а `ServerPlayConnectionEvents.DISCONNECT` — строго серверное.
  Клиентскую половину надо перевешивать отдельно.

### `net.neoforged.neoforge.common.util.TriPredicate` — аналога на Fabric нет
- Три параметра, метод `test(A,B,C)`. Восстанавливается вложенным `@FunctionalInterface` в 4 строки.

### `Minecraft#isSingleplayer()` → `hasSingleplayerServer()`
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/Minecraft.java:2506,2510`; `isSingleplayer` — 0 вхождений.

### `GameProfile` стал record: `getName()` → `name()`
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/entity/player/Player.java:1683`.

---

## Организационное

### Работать «от ошибок» окупается нелинейно
Зона B2 стартовала с 367 ошибок (219 своих + 148 чужого `WorldRenderMacros`). Первые два
механических прохода — одна `sed`-замена импортов (`Tuple`, `IItemHandler`, `compat.common.*`) и
разбор `BlueprintUtil` — сняли 40% зоны. Итог: 0 ошибок в зоне, при этом общее число ошибок по
дереву упало с 805 до 78 — большая часть чужих `cannot find symbol` была следствием
неразрешимых сигнатур в `blueprints/**` и `util/**`.
