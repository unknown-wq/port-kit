# FINDINGS-A — копилка знаний агента A (Structurize → Fabric / MC 26.2)

Только то, чего **не было** в порт-ките (`PORT-ANY-MOD-26.2.md`, `PORT-CHEATSHEET.md`,
`NEOFORGE-TO-FABRIC-26.2.md`, `NOTES-A/B/C.md`). Каждая находка с подтверждением.

---

## Тулчейн и Gradle

### Конфигураций `mod*` в Loom 1.17 / 26.2 не существует
- **Было:** `modImplementation files("libs/foo.jar")`.
- **Стало:** `Could not find method modImplementation() for arguments [file collection]`.
  Игра неообфусцирована, ремапить нечего, Loom не регистрирует `modImplementation` /
  `modApi` / `modRuntimeOnly` вообще. Работает `implementation files("libs/…")`;
  Fabric Loader в dev находит мод по `fabric.mod.json` на classpath.
- **Подтверждено:** лог сборки `/home/user/Structurize/26.2`.
- **Комментарий:** единственное место, где инструкция разошлась с реальностью; прав Loom.

### AccessTransformer → AccessWidener, заголовок `official`
- **Стало:** `src/main/resources/structurize.accesswidener`, шапка `accessWidener<TAB>v2<TAB>official`,
  разделитель — **табуляция**, подключение `loom { accessWidenerPath = file(...) }`.
  Приватное поле, которое надо и писать, требует двух строк: `accessible` + `mutable`.
- **Комментарий:** Loom валидирует каждую строку по именам Mojang и **несуществующий член
  валит сборку целиком** — мёртвые строки AT переносить нельзя, только выписывать
  комментарием. Из 13 строк AT Structurize живыми оказались 8; мертвы `RenderStateShard`,
  `GlStateManager` (Blaze3D переписан), `ChunkPalettedStorageFix.FLOWER_POT_MAP/NOTE_BLOCK_MAP`.

### Ошибки в логе Gradle дублируются
javac печатает их и в stdout, и в сводку задачи — считать только уникальные тройки
«файл : строка : текст». И: `cmd 2>&1 > file` перенаправляет stderr в **терминал**,
а не в файл; писать `cmd > file 2>&1`.

---

## Реестры

### `BlockEntityType.Builder` удалён
`new BlockEntityType<>(BlockEntitySupplier<? extends T>, Set<Block>)`.
**Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/entity/BlockEntityType.java:18`.

### Константы разъехались с типами: `EntityTypeIds`, `BlockEntityTypeIds`
Объекты — в `EntityTypes` / `BlockEntityTypes`, а **`ResourceKey`** — в
`net.minecraft.world.entity.EntityTypeIds` / `net.minecraft.world.level.block.entity.BlockEntityTypeIds`.
**Подтверждено:** `EntityTypeIds.java:13`, `BlockEntityTypeIds.java:9`.
**Комментарий:** для датагена подарок — `TagAppender#add` как раз хочет `ResourceKey`,
`tag.add(EntityTypeIds.ARMOR_STAND)` короче, чем `BuiltInRegistries.ENTITY_TYPE.getResourceKey(...)`.

### `DataComponentType` — `DeferredHolder` не нужен
Поля становятся просто `DataComponentType<D>` (`Registry.register(BuiltInRegistries.DATA_COMPONENT_TYPE, id, type)`),
и **все 15 call-site'ов компилируются без правки** — ни один не звал `.get()`.
Законное исключение из контракта C1.

### `CreativeModeTab.Builder` моду недоступен
`FabricCreativeModeTab.builder()…build()` + `Registry.register(BuiltInRegistries.CREATIVE_MODE_TAB, key, tab)`;
строку/колонку раздаёт `fabric-creative-tab-api-v1`.
**Подтверждено:** `/workspace/domum-ornamentum/26.2/.../block/ModCreativeTabs.java:30`.

---

## NBT: всё стало Optional

### `CompoundTag`: геттеры вернули `Optional`, `getAllKeys` переименован
`getCompound/getInt/getString/getList` → `Optional<…>`. Старая форма:
`getCompoundOrEmpty(k)`, `getIntOr(k,def)`, `getStringOr(k,def)`, `getListOrEmpty(k)`,
`getBooleanOr`, `getLongOr`, `getFloatOr`, `getDoubleOr`, `getByteOr`, `getShortOr`.
`getAllKeys()` → `keySet()`. `contains(String, byte)` больше нет, только `contains(String)`.
**Подтверждено:** `/opt/mc-src/net/minecraft/nbt/CompoundTag.java:193,271,275,287-371`.

### `BlockEntity` сохраняется через `ValueInput` / `ValueOutput`
`protected void loadAdditional(ValueInput)` / `protected void saveAdditional(ValueOutput)`;
`ValueInput#lookup()` даёт `HolderLookup.Provider`. **Сырого `CompoundTag` из `ValueInput`
достать нельзя** — ни ваниль, ни `FabricValueInput` (`keySet`, `contains`,
`getOptionalLongArray`, `getOptionalByteArray` — и всё).
**Подтверждено:** `BlockEntity.java:105,109`; `ValueInput.java`; `javap FabricValueInput`.
**Рабочий обходной путь для legacy-кода на `CompoundTag`:** хранить старый блок под одним
ключом через `CompoundTag.CODEC` —
`output.store("blueprintDataProvider", CompoundTag.CODEC, tag)` /
`input.read("blueprintDataProvider", CompoundTag.CODEC)`.
Формат на диске байт-в-байт как в 1.21.1.
См. `blockentities/interfaces/IBlueprintDataProviderBE.java:97,166`.

### `BlockEntity#saveWithId(Provider)` и `saveToItem` удалены
Остались `saveWithId(ValueOutput)` / `saveWithFullMetadata(ValueOutput)`.
Чтобы получить `CompoundTag`:
`TagValueOutput.createWithContext(ProblemReporter.DISCARDING, provider)` → `be.saveWithId(output)`
→ `output.buildResult()`. Вместо `saveToItem` — `stack.applyComponents(be.collectComponents())`.
**Подтверждено:** `BlockEntity.java:125,311`;
`/workspace/domum-ornamentum/26.2/.../AbstractMateriallyTexturedBlockEntity.java:49`.

### `BlockEntity.DataComponentInput` → `net.minecraft.core.component.DataComponentGetter`
**Подтверждено:** `BlockEntity.java:275`.

### `BlockEntity#removeComponentsFromTag(CompoundTag)` удалён
0 вхождений в `/opt/mc-src`.

### `ItemStack.parseOptional(Provider, CompoundTag)` удалён
`ItemStack.OPTIONAL_CODEC.parse(dynamicOps, tag).result().orElse(ItemStack.EMPTY)`.
**Подтверждено:** `ItemStack.java:123`.

---

## Предметы и блоки

### `InteractionResultHolder` удалён; `Item#use` возвращает `InteractionResult`
`InteractionResult` — sealed interface: `SUCCESS`, `SUCCESS_SERVER`, `CONSUME`, `FAIL`, `PASS`.
**Подтверждено:** `Item.java:188`, `InteractionResult.java:11-15`; файла `InteractionResultHolder.java` нет.

### `Item#canAttackBlock` → `Item#canDestroyBlock(ItemStack, BlockState, Level, BlockPos, LivingEntity)`
Пятый параметр — `LivingEntity`, не `Player`; телу почти всегда нужен
`if (!(user instanceof Player player)) return super.canDestroyBlock(...)`.
**Подтверждено:** `Item.java:169`.

### `Item#appendHoverText` — пять параметров
`appendHoverText(ItemStack, Item.TooltipContext, TooltipDisplay, Consumer<Component>, TooltipFlag)`,
`TooltipDisplay` из `net.minecraft.world.item.component`. Помечен `@Deprecated`, но живой.
**Подтверждено:** `Item.java:322-326`.

### `Item.Properties#setNoRepair()` удалён
Починка задаётся положительно — `repairable(Item)` / `repairable(TagKey<Item>)`;
по умолчанию предмет непочиняемый, `.setNoRepair()` просто вычёркивается.
**Подтверждено:** `Item.java:437,441`.

### Два хука pick-block слились в один
Было `getCloneItemStack(LevelReader, BlockPos, BlockState)` **и**
`getCloneItemStack(BlockState, HitResult, LevelReader, BlockPos, Player)`.
Стало — один `protected ItemStack getCloneItemStack(LevelReader, BlockPos, BlockState, boolean includeData)`
на `BlockBehaviour`; публичная точка входа `BlockState#getCloneItemStack(LevelReader, BlockPos, boolean)`.
`HitResult` и `Player` ушли.
**Подтверждено:** `BlockBehaviour.java:408,893`.

### `LiquidBlockContainer#canPlaceLiquid` берёт `LivingEntity`, не `Player`
**Подтверждено:** `LiquidBlockContainer.java:13`.

### `BlockState#rotate(LevelAccessor, BlockPos, Rotation)` — это был NeoForge
Остался только `rotate(Rotation)`.
**Подтверждено:** `BlockBehaviour.java:600`.

### `Registry#getTag(TagKey)` удалён
Спрашивать холдер: `object.builtInRegistryHolder().is(tagKey)`.
На реестре остались `getTagOrEmpty(TagKey)` и `getTags()`.
**Подтверждено:** `Registry.java:137,141`.

---

## Игрок, уровень, звук

### `Level.isClientSide` стало приватным полем
Метод `level.isClientSide()`. Механическая замена `\.isClientSide\b(?!\()` → `.isClientSide()`.
**Подтверждено:** `Level.java:165`.

### `Player#displayClientMessage` и `Entity#playNotifySound` удалены
`player.sendSystemMessage(component)` (на `ServerPlayer` есть `sendSystemMessage(Component, boolean overlay)`);
`player.playSound(sound, vol, pitch)` — `SoundSource` из сигнатуры ушёл.
**Подтверждено:** `Player.java:397,1343`; `playNotifySound` — 0 вхождений во всём `/opt/mc-src`.
**Комментарий:** тихая семантическая разница — `playNotifySound` играл только слушателю,
`playSound` слышат окружающие.

### `LevelHeightAccessor#getMinBuildHeight()` → `getMinY()`
**Подтверждено:** `LevelHeightAccessor.java:9`.

### `Entity#getPickedResult(HitResult)` — это был NeoForge
Ванильный `@Nullable ItemStack getPickResult()` без аргументов.
**Подтверждено:** `Entity.java:3852`.

### `Minecraft#screen` больше не публичное поле
`Minecraft.getInstance().gui.screen()`; ставить — `gui.setScreen(...)`.
**Подтверждено:** `Gui.java:218,222`.

### `net.minecraft.util.Tuple` удалён
0 вхождений `class Tuple` в `/opt/mc-src`. Обходной путь — свой `Tuple<A,B>` с
`getA()`/`getB()`, тогда правка в 14 файлах сводится к строке импорта.

### `CommandSourceStack`: числовой уровень прав стал `PermissionSet`
Пятый аргумент — `PermissionSet`; готовые значения в
`net.minecraft.server.permissions.LevelBasedPermissionSet`:
`ALL`, `MODERATOR`, `GAMEMASTER`, `ADMIN`, `OWNER` (уровни 0–4).
**Подтверждено:** `CommandSourceStack.java:70`, `LevelBasedPermissionSet.java:5-9`.

### `BaseCommandBlock#createCommandSourceStack()` требует аргументы
`createCommandSourceStack(ServerLevel level, CommandSource source)`.
**Подтверждено:** `BaseCommandBlock.java:162`.

### `ServerPlayer#getServer()` больше нет
`player.level().getServer()`.

---

## Fake level / рендер-инфраструктура

### `Level` в 26.2 требует ровно 29 нереализованных абстрактных методов
`sendBlockUpdated`, `playSeededSound` ×2, `tickRateManager`, `explode`, `getEntities()` (protected),
`dragonParts`, `getEntity(int)`, `clockManager`, `gatherChunkSourceStats`, `setRespawnData`,
`getRespawnData`, `getMapData`, `destroyBlockProgress`, `getScoreboard`, `recipeAccess`,
`potionBrewing`, `fuelValues`, `environmentAttributes`, `getChunkSource`, `levelEvent`,
`gameEvent`, `getBlockTicks`, `getFluidTicks`, `getSeaLevel`, `getUncachedNoiseBiome`,
`enabledFeatures`, `players`, `getWorldBorder`.

Новое против 1.21.1: `clockManager()`, `environmentAttributes()`, `recipeAccess()`,
`setRespawnData`/`getRespawnData` (вместо `getSharedSpawnPos`), `explode(...)` с
`WeightedList<ExplosionParticleInfo>`.

Конструктор: `Level(WritableLevelData, ResourceKey<Level>, RegistryAccess, Holder<DimensionType>,
boolean isClientSide, boolean isDebug, long biomeZoomSeed, int maxChainedNeighborUpdates)`.
`WritableLevelData` = `LevelData` + `setSpawn(LevelData.RespawnData)`, реализуется анонимкой на 6 методов.

**Приём для получения списка** (работает для любого абстрактного ванильного класса; javac
показывает только первый недостающий метод):
```java
Class<?> c = Class.forName("net.minecraft.world.level.Level", false, L.class.getClassLoader()); // без инициализации!
// обойти суперклассы + интерфейсы, собрать abstract-методы, вычесть конкретные по (имя + типы параметров)
```
С `initialize = true` падает `IllegalArgumentException: Not bootstrapped (called from registry minecraft:game_event)`.

### `BlockAndTintGetter` и `getShade` исчезли
Остался `net.minecraft.world.level.BlockAndLightGetter`; затенение граней уехало в
клиентский `BlockModelLighter`.
**Подтверждено:** `ls /opt/mc-src/net/minecraft/world/level/` — `BlockAndTintGetter.java` нет.

### `LevelEntityGetter<T extends EntityAccess>` — типовая ловушка
Методы объявлены как `<U extends T> void get(EntityTypeTest<T, U>, …)`. Для `T = Entity`
писать `<U extends Entity>`, а **не** `<U extends EntityAccess>` — иначе
`name clash … neither overrides the other` плюс `type argument U is not within bounds`.
**Подтверждено:** `LevelEntityGetter.java:16,20`.

---

## Сеть Fabric

### Имена методов реестра пейлоадов
Не `playS2C()` / `playC2S()`, а **`PayloadTypeRegistry.serverboundPlay()`** и
**`PayloadTypeRegistry.clientboundPlay()`** (плюс `serverboundConfiguration()` /
`clientboundConfiguration()`).
**Подтверждено:** `javap PayloadTypeRegistry` из `fabric-networking-api-v1-6.3.3+72073ef09e.jar`;
`/workspace/simple-planes/26.2/.../SimplePlanesNetworking.java:24`.
**Комментарий:** `ServerPlayNetworking.Context` даёт `server()`, `player()` (`ServerPlayer`),
`responseSender()`; `ClientPlayNetworking.Context` — `client()`, `player()` (`LocalPlayer`),
`responseSender()`. Отправка с клиента — статический `ClientPlayNetworking.send(payload)`
без явного соединения.

### `CustomPacketPayload.Type` — record с одним `Identifier`
`new CustomPacketPayload.Type<>(Identifier.fromNamespaceAndPath(modId, name))`;
статический `createType(String)` вешает namespace `minecraft` и моду не годится.
**Подтверждено:** `CustomPacketPayload.java:57`.

---

## Датаген на Fabric

### Провайдер тегов для реестра без готового флейвора
Fabric даёт `FabricTagsProvider.BlockTagsProvider` / `ItemTagsProvider` / `EntityTypeTagsProvider`,
но **не** блок-энтити. Годится базовый
`FabricTagsProvider<T>(FabricPackOutput, ResourceKey<? extends Registry<T>>, CompletableFuture<HolderLookup.Provider>)`.
**Подтверждено:** `javap net.fabricmc.fabric.api.datagen.v1.provider.FabricTagsProvider`.

### Ссылка на чужой тег требует `forceAddTag`
`addTag(BlockTags.LEAVES)` валит датаген с «missing following references» — ванильные теги
датагену не видны. Ставить `forceAddTag` (**не** `addOptionalTag`, тот пишет
`"required": false` и молча деградирует).
**Подтверждено:** `javap FabricTagAppender`; разбор —
`/workspace/domum-ornamentum/26.2/.../datagen/utils/BlockTagAppender.java:15-38`.

---

## Организационное

### Граф зависимостей Structurize не режется по пакетам
Временные `exclude` на «чужие» пакеты, чтобы агент фазы 1 видел только свои ошибки,
**неприменимы**: транзитивное замыкание зоны A требует **103 из 138** чужих файлов,
а обратное замыкание вырезает **24 из 55** файлов зоны A, включая `Structurize.java`,
`ModBlocks`, `ModItems`, `ModDataComponents`, `ClientConfiguration`.

Рабочая замена — фильтр лога по путям своей зоны:
```sh
grep -oE '/com/ldtteam/structurize/(api|blocks|items|blockentities|component|tag|config|datagen|compat)/[^:]*:[0-9]+: error' \
  /tmp/errors.txt | sort -u
```
Ложных срабатываний почти нет: ошибка внутри тела чужого класса не мешает javac
разрешить его сигнатуру.
