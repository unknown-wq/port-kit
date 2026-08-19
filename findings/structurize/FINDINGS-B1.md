# FINDINGS-B1 — копилка знаний агента B1 (сеть, события, команды, management)

Только то, чего **не было** в порт-ките (`PORT-ANY-MOD-26.2.md`, `PORT-CHEATSHEET.md`,
`NEOFORGE-TO-FABRIC-26.2.md`, `NOTES-*.md`) и в `FINDINGS-A.md`. Каждая находка с подтверждением.

---

## Ваниль 26.2 — переименования и переезды

### `Inventory#getSelected()` → `getSelectedItem()`, поле `selected` спрятано
- **Было (1.21.1):** `player.getInventory().getSelected()`, `inventory.selected` (публичное поле).
- **Стало (26.2):** `getSelectedItem()`; слот — `getSelectedSlot()` / `setSelectedSlot(int)`,
  само поле `private int selected`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/entity/player/Inventory.java:56,66,70,78`.
- **Комментарий:** задевает `AbsorbBlockMessage`, `ItemMiddleMouseMessage`, `ClientEventSubscriber`.
  `setSelectedSlot` кидает `IllegalArgumentException` на не-хотбарный индекс — раньше поле писалось молча.

### `FriendlyByteBuf`: `readResourceLocation` / `writeResourceLocation` → `readIdentifier` / `writeIdentifier`
- **Подтверждено:** `/opt/mc-src/net/minecraft/network/FriendlyByteBuf.java:579,583`.
- **Комментарий:** переименование идёт следом за `ResourceLocation` → `Identifier`; на проводе
  формат тот же (`readUtf(32767)` + `Identifier.parse`), совместимость пакетов не ломается.

### `Registry#get(Identifier)` теперь возвращает `Optional<Holder.Reference<T>>`
- **Было:** `BuiltInRegistries.ENTITY_TYPE.get(id)` → `@Nullable EntityType<?>`.
- **Стало:** `get(...)` отдаёт `Optional<Holder.Reference<T>>`; «старое» поведение — `getValue(Identifier)`
  и `getValue(ResourceKey<T>)`, оба `@Nullable T`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/core/Registry.java:65,67,72,76`.
- **Комментарий:** самая тихая ловушка порта — `get` компилируется в `var`, и `null`-проверка
  превращается в проверку непустого `Optional`, которая всегда true.

### `Registry` сам является `HolderGetter` — `asLookup()` удалён
- **Было:** `NbtUtils.readBlockState(BuiltInRegistries.BLOCK.asLookup(), tag)`.
- **Стало:** `Registry<T> extends IdMap<T>, Keyable, HolderLookup.RegistryLookup<T>` → передавать
  сам реестр: `NbtUtils.readBlockState(BuiltInRegistries.BLOCK, tag)`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/core/Registry.java:26`;
  `/opt/mc-src/net/minecraft/nbt/NbtUtils.java:127`.

### `LevelRenderer#setBlocksDirty` уехал в `LevelExtractor`
- **Было:** `Minecraft.getInstance().levelRenderer.setBlocksDirty(x0,y0,z0,x1,y1,z1)`.
- **Стало:** `Minecraft.getInstance().levelExtractor.setBlocksDirty(...)`, класс
  `net.minecraft.client.renderer.extract.LevelExtractor`, поле публичное и финальное.
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/Minecraft.java:283`;
  `/opt/mc-src/net/minecraft/client/renderer/extract/LevelExtractor.java:422`.
- **Комментарий:** там же `setSectionDirty`, `setSectionDirtyWithNeighbors`, `allChanged` —
  вся «пометить грязным» часть `LevelRenderer` из 1.21.1.

### `Minecraft#getProfiler()` удалён → `Profiler.get()`
- **Стало:** `net.minecraft.util.profiling.Profiler.get()` возвращает `ProfilerFiller` текущего
  потока; `push`/`pop` те же. Вне тика отдаёт `InactiveProfiler.INSTANCE`, то есть безопасен.
- **Подтверждено:** `/opt/mc-src/net/minecraft/util/profiling/Profiler.java:47`.

### `Screen.hasControlDown()` / `hasShiftDown()` больше нет
- **Было:** статические хелперы на `Screen`, доступные из любого места.
- **Стало:** состояние модификаторов раздаётся только внутри input-событий
  (`event.hasControlDownWithQuirk()`). Вне события читать с окна:
  `InputConstants.isKeyDown(Minecraft.getInstance().getWindow(), InputConstants.KEY_LCONTROL)`.
  Маковская подмена Ctrl→Cmd вынесена в флаг
  `net.minecraft.client.input.InputQuirks.REPLACE_CTRL_KEY_WITH_CMD_KEY`
  (клавиши `KEY_LSUPER` = 343 / `KEY_RSUPER` = 347).
- **Подтверждено:** `/opt/mc-src/com/mojang/blaze3d/platform/InputConstants.java:129,131,135,195`;
  `/opt/mc-src/net/minecraft/client/input/InputQuirks.java:10`;
  `/opt/mc-src/net/minecraft/client/gui/screens/Screen.java:134` (единственное оставшееся
  употребление — через event).

### `InteractionResult` — sealed interface, `switch` по константам не компилируется
- **Было:** `switch (result) { case PASS: ... case FAIL: ... default: ... }` — enum.
- **Стало:** `sealed interface` с записями `Success` / `Fail` / `Pass` / `TryEmptyHandInteraction`;
  `PASS`, `FAIL`, `SUCCESS`, `SUCCESS_SERVER`, `CONSUME` — это статические поля, а не enum-константы,
  поэтому `case PASS:` даёт `cannot find symbol: variable PASS`. Заменяется на
  `result instanceof InteractionResult.Pass` / `instanceof InteractionResult.Fail`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/InteractionResult.java:5-16,22,30`.
- **Комментарий:** `FINDINGS-A` фиксирует сам факт sealed-интерфейса; тут важно следствие —
  каждый `switch` по `InteractionResult` в коде мода надо разворачивать в `instanceof`-цепочку.
  Сравнение по `==` с `InteractionResult.PASS` тоже ненадёжно: `Pass` — record, `SUCCESS`
  проверять через `consumesAction()`.

### `GameProfileArgument.getGameProfiles` отдаёт `NameAndId`, а не `GameProfile`
- **Было:** `Collection<com.mojang.authlib.GameProfile>`, `profile.getId()` / `getName()`.
- **Стало:** `Collection<net.minecraft.server.players.NameAndId>` — record `(UUID id, String name)`,
  методы `id()` / `name()`, есть конструктор из `GameProfile` и `createOffline(String)`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/commands/arguments/GameProfileArgument.java:30`;
  `/opt/mc-src/net/minecraft/server/players/NameAndId.java:11,17`.

### `SharedConstants.getCurrentVersion()` — геттеры стали аксессорами record-а
- **Было:** `SharedConstants.getCurrentVersion().getDataVersion().getVersion()`.
- **Стало:** `WorldVersion#dataVersion()` → `net.minecraft.world.level.storage.DataVersion`,
  это `record DataVersion(int version, String series)` → `.version()`.
  Также `id()`, `name()`, `protocolVersion()`, `packVersion(PackType)` (вместо `getPackVersion`).
- **Подтверждено:** `/opt/mc-src/net/minecraft/WorldVersion.java:9`;
  `/opt/mc-src/net/minecraft/world/level/storage/DataVersion.java:5`;
  `/opt/mc-src/net/minecraft/SharedConstants.java:198`.

---

## NBT — то, чего нет в `FINDINGS-A`

### `ListTag`: индексные геттеры тоже стали `Optional`
`getCompound(int)` → `Optional<CompoundTag>` / `getCompoundOrEmpty(int)`;
`getInt(int)` → `Optional<Integer>` / `getIntOr(int, def)`;
аналогично `getString/getStringOr`, `getShort/getShortOr`, `getDouble`, `getFloat`,
`getList/getListOrEmpty`, `getIntArray`, `getLongArray`.
**Подтверждено:** `/opt/mc-src/net/minecraft/nbt/ListTag.java:254-314`.

### `CompoundTag#getList(String, int tagType)` — второго аргумента больше нет
`getList("blocks", Tag.TAG_COMPOUND)` → `getListOrEmpty("blocks")` (или `getList(String)` →
`Optional<ListTag>`). Проверка типа элементов ушла внутрь: `getCompoundOrEmpty(i)` вернёт пустой
тег, если элемент другого типа.
**Подтверждено:** `/opt/mc-src/net/minecraft/nbt/CompoundTag.java:359,363`.

### `Tag#getAsString()` → `Optional<String> asString()`
`(modsList.get(i)).getAsString()` → `.asString().orElse("")`.
**Подтверждено:** `/opt/mc-src/net/minecraft/nbt/Tag.java:51`;
`/opt/mc-src/net/minecraft/nbt/StringTag.java:92`.

---

## Fabric API — эквиваленты событий NeoForge

Версии на проекте: `fabric-lifecycle-events-v1 4.1.3`, `fabric-command-api-v2 3.1.0`,
`fabric-rendering-v1`, `fabric-events-interaction-v0 5.2.6`, `fabric-resource-loader-v0`.

### `RegisterCommandsEvent` → `CommandRegistrationCallback.EVENT` (три аргумента)
`register(CommandDispatcher<CommandSourceStack>, CommandBuildContext, Commands.CommandSelection)`.
`CommandSelection` — третий параметр, ровно то, что давал `event.getCommandSelection()`.
**Подтверждено:** `javap net.fabricmc.fabric.api.command.v2.CommandRegistrationCallback`
из `fabric-command-api-v2-3.1.0+00cb03469e.jar`.

### `LevelTickEvent.Pre` → `ServerTickEvents.START_LEVEL_TICK` (только серверные уровни)
`StartLevelTick#onStartTick(ServerLevel)`. Клиентский уровень сюда не приходит — если старый
обработчик делал что-то и на клиенте, вторую половину надо ставить на
`ClientTickEvents.START_LEVEL_TICK` из клиентского entrypoint-а.
**Подтверждено:** `javap ServerTickEvents$StartLevelTick`, `ClientTickEvents` из
`fabric-lifecycle-events-v1-4.1.3+4575b05f9e.jar`.

### `FMLDedicatedServerSetupEvent` не имеет прямого аналога
Ближайшее — `ServerLifecycleEvents.SERVER_STARTING`, но оно срабатывает и для встроенного сервера.
Точная семантика восстанавливается явной проверкой `server.isDedicatedServer()`.
**Подтверждено:** `/opt/mc-src/net/minecraft/server/MinecraftServer.java:1342`;
`javap ServerLifecycleEvents$ServerStarting` (`onServerStarting(MinecraftServer)`).
**Комментарий:** без проверки в одиночной игре серверный загрузчик пакетов запускается вторым
экземпляром поверх клиентского и ломает состояние синхронизации.

### `ClientPlayerNetworkEvent.LoggingOut` → `ClientPlayConnectionEvents.DISCONNECT`
`Disconnect#onPlayDisconnect(ClientPacketListener, Minecraft)`.
**Подтверждено:** `javap ClientPlayConnectionEvents$Disconnect` из `fabric-networking-api-v1`.

### `InputEvent.MouseScrollingEvent` — общего события колеса в Fabric API НЕТ
Есть только `ClientHotbarScrollEvents` (`fabric-events-interaction-v0`):
`ALLOW#allowScroll(Inventory, int currentSlot, int newSlot, double scrollX, double scrollY) → boolean`,
плюс `BEFORE` / `AFTER`. Миксин оборачивает `Inventory.setSelectedSlot` внутри `MouseHandler`,
то есть это ровно тот путь, который NeoForge-обработчик отменял через `setCanceled(true)`;
возврат `false` = отмена.
**Подтверждено:** `javap net.fabricmc.fabric.api.event.client.player.ClientHotbarScrollEvents`
и `javap -c net.fabricmc.fabric.mixin.event.interaction.client.MouseHandlerMixin`
(`wrapSelectedSlot`: `Inventory.getSelectedSlot` → `ALLOW.invoker().allowScroll`)
из `fabric-events-interaction-v0-5.2.6+8f57f7ee9e.jar`.
**Комментарий:** колесо при открытом экране и колесо без смены слота сюда не приходят —
для них нужен либо `ScreenMouseEvents` (`fabric-screen-api-v1`), либо свой миксин на `MouseHandler`.

### `RenderGuiLayerEvent.Pre` + `setCanceled` → `HudElementRegistry.replaceElement`
Отмены как таковой нет: элемент **заменяется** обёрткой.
`HudElementRegistry.replaceElement(Identifier, Function<HudElement, HudElement>)`,
идентификаторы ванильных элементов — в `VanillaHudElements` (`HEALTH_BAR`, `FOOD_BAR`, `HOTBAR`,
`CROSSHAIR`, …; это замена `VanillaGuiLayers`). Сам `HudElement` — функциональный интерфейс
`void extractRenderState(GuiGraphicsExtractor, DeltaTracker)`: чтобы «отменить», просто не звать
исходный. Есть и `removeElement(Identifier)`, `addFirst`, `addLast`, `attachElementBefore/After`.
**Подтверждено:** `javap HudElementRegistry`, `VanillaHudElements`, `HudElement`
из `fabric-rendering-v1`.
**Комментарий:** имена изменились — `VanillaGuiLayers.PLAYER_HEALTH` → `VanillaHudElements.HEALTH_BAR`,
`FOOD_LEVEL` → `FOOD_BAR`.

### `RegisterClientTooltipComponentFactoriesEvent` → `ClientTooltipComponentCallback.EVENT`
Не отображение «класс → фабрика», а цепочка фильтров:
`ClientTooltipComponent getClientComponent(TooltipComponent)`, **`null` = пропустить дальше**,
берётся первый ненулевой ответ. Значит `instanceof` пишется руками.
**Подтверждено:** `javap -c net.fabricmc.fabric.api.client.rendering.v1.ClientTooltipComponentCallback`
(`lambda$static$1`: цикл по слушателям, `ifnull` → следующий, иначе `areturn`).

### `RegisterClientReloadListenersEvent` → `ResourceManagerHelper` + обязательный `Identifier`
`ResourceManagerHelper.get(PackType.CLIENT_RESOURCES).registerReloadListener(listener)`,
где listener — `IdentifiableResourceReloadListener`; проще всего
`SimpleSynchronousResourceReloadListener` (`getFabricId()` + `onResourceManagerReload(ResourceManager)`).
NeoForge-овские анонимные `SimplePreparableReloadListener` без имени не годятся —
Fabric требует id для сортировки.
**Подтверждено:** `javap ResourceManagerHelper`, `SimpleSynchronousResourceReloadListener`
из `fabric-resource-loader-v0`.

### `net.neoforged.fml.ModList` → `FabricLoader`
`ModList.get().getModContainerById(id).isPresent()` → `FabricLoader.getInstance().isModLoaded(id)`;
`ModList.get().getMods()` → `FabricLoader.getInstance().getAllMods()` (`ModContainer#getMetadata().getId()`).
Версия мода (`…getModInfo().getVersion()`) в сети больше не нужна: у Fabric-пейлоада нет
протокольной версии, у `PayloadRegistrar#versioned` аналога не существует.

---

## Команды

### `EnumArgument` (NeoForge) заменять на строковый аргумент, а не на свой `ArgumentType`
В ванили и в Fabric API аналога `net.neoforged.neoforge.server.command.EnumArgument` нет.
Свой `ArgumentType` потребовал бы ещё и `ArgumentTypeInfo`, зарегистрированного в
`BuiltInRegistries.COMMAND_ARGUMENT_TYPE`, иначе дерево команд не сериализуется клиенту.
Дёшево и без реестра: `StringArgumentType.word()` + `.suggests(...)` на
`SharedSuggestionProvider.suggest(Stream<String>, SuggestionsBuilder)` и ручной разбор.
Важно: `context.getArgument(name, MyEnum.class)` при этом **упадёт в рантайме**, потому что в
контексте лежит `String` — все call-site'ы надо переводить на свой геттер.
**Подтверждено:** `/opt/mc-src/net/minecraft/commands/SharedSuggestionProvider.java:226,238,244`;
реализация — `26.2/src/main/java/com/ldtteam/structurize/commands/AbstractCommand.java`
(`newEnumArgument` / `getEnum`).

---

## Организационное

### `typecheck.sh` надо запускать из `26.2/`, иначе он молча даёт «0 ошибок»
`find src/main/java` из чужого каталога возвращает пустой список, javac компилирует ноль файлов
и скрипт печатает `0` — самый опасный из возможных ответов. В агентских обёртках рабочий каталог
между вызовами `Bash` сбрасывается, поэтому команду надо начинать с
`cd /home/user/Structurize/26.2`. В скрипт добавлена явная проверка каталога.
