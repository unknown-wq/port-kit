# FINDINGS-INTEGRATION — копилка знаний агента-интегратора (фаза 3)

Зона: подключение BlockUI, переезд с восстановленной `compat/common` на настоящую
`com.ldtteam.common`, расшивка BER, ресурсные долги, первый `runServer`.

Только то, чего **не было** в порт-ките, в `FINDINGS-A/B1/B2/D.md` и в `PORT-GAPS.md`.

---

## 0. Главный результат: восстановленная по call-site'ам библиотека совпала с настоящей

Переезд `com.ldtteam.structurize.compat.common.*` → `com.ldtteam.common.*` — **три `sed`-подстановки
на 36 файлов и ровно 4 ошибки компиляции**, все в двух entrypoint-ах. Ни одного из 25 сообщений,
ни одного конфига, ни одного `fakelevel`-потребителя править не пришлось.

Это само по себе находка: **контракт, восстановленный по call-site'ам, оказался точным** —
потому что call-site'ы и есть контракт. Расходятся только те места, где call-site'ов в моде
не было: регистрация, bootstrap, side-специфика.

### Три подстановки, которые сделали переезд

```sh
sed -i \
 -e 's/com\.ldtteam\.structurize\.compat\.common\.config\.ModConfigSpec\.ConfigValue/com.ldtteam.common.config.ConfigValue/g' \
 -e 's/com\.ldtteam\.structurize\.compat\.common\.config\.ModConfigSpec\./com.ldtteam.common.config.ConfigValue./g' \
 -e 's/com\.ldtteam\.structurize\.compat\.common\./com.ldtteam.common./g' \
 $(grep -rl 'com\.ldtteam\.structurize\.compat\.common' --include=*.java . | grep -v '/compat/common/')
```
Порядок обязателен: `ModConfigSpec.ConfigValue` надо схлопнуть **до** общего `ModConfigSpec.` →
`ConfigValue.`, иначе получится `com.ldtteam.common.config.ConfigValue.ConfigValue`.

---

## 1. Чем настоящая `com.ldtteam.common` отличается от восстановленной по call-site'ам

Для будущего порта MineColonies это и есть список мест, где «оно скомпилировалось» ≠ «оно то же самое».

### 1.1 Иерархия сообщений: появился корень `AbstractUnsidedPlayMessage`

- **Восстановлено:** `AbstractPlayMessage implements CustomPacketPayload` — корень;
  `AbstractServerPlayMessage`/`AbstractClientPlayMessage extends AbstractPlayMessage`.
- **На самом деле:** корень — **package-private** `abstract class AbstractUnsidedPlayMessage
  implements CustomPacketPayload`, а `AbstractPlayMessage` — это **двусторонний** вариант, брат
  `AbstractServerPlayMessage` и `AbstractClientPlayMessage`, а не их предок.
- **Подтверждено:** `/workspace/blockui/26.2/.../common/network/AbstractUnsidedPlayMessage.java:9`.
- **Следствие:** `PlayMessageType<T extends AbstractUnsidedPlayMessage>`, и границы трёх фабрик
  разные: `forServer` требует `AbstractServerPlayMessage`, `forClient` — `AbstractClientPlayMessage`,
  `forBothSides` — `AbstractPlayMessage`. Наш вариант с общим предком компилировал те же call-site'ы,
  но **разрешал бы `forServer(..., ClientMessage::new)`** — настоящая библиотека это ловит типами.
- **Комментарий:** корень package-private ⇒ сообщение мода не может наследоваться от него напрямую;
  выбор «односторонний/двусторонний» навязан конструкцией.

### 1.2 Отправка стала интерфейсами-миксинами, а не методами базового класса

- **Восстановлено:** `sendToServer()`, `sendToPlayer(ServerPlayer)`, `sendToAllClients()` — три метода
  прямо на `AbstractPlayMessage`.
- **На самом деле:** `IServerboundDistributor` (один метод `sendToServer()`) и
  `IClientboundDistributor` (**восемь**: `sendToPlayer(ServerPlayer)`, `sendToPlayer(Collection)`,
  `sendToDimension(ServerLevel)`, `sendToTargetPoint(...)`, `sendToAllClients()`,
  `sendToTrackingEntity(Entity)`, `sendToTrackingEntityAndSelf(Entity)`,
  `sendToPlayersTrackingChunk(...)`).
- **Подтверждено:** `IClientboundDistributor.java:24-109`, `IServerboundDistributor.java:8-15`.
- **Следствие:** направление отправки теперь проверяется компилятором. В нашей копии серверное
  сообщение могло позвать `sendToAllClients()`; теперь нет.
- **Для MineColonies:** там `PacketDistributor` использовался богаче, чем в Structurize (мы зовём
  три цели из девяти) — все девять уже есть, изобретать не надо.

### 1.3 `PlayMessageType` — record с 12 перегрузками и без `registerClientReceivers()`

- **На самом деле:** `record PlayMessageType<T>(Type<T> id, StreamCodec<...> codec,
  boolean allowNullPlayer, @Nullable PayloadAction client, @Nullable PayloadAction server)`,
  **12** фабрик: `{forClient,forServer,forBothSides}` × {фабрика-конструктор, готовый `StreamCodec`}
  × {короткая, с `(playerNullable, executeOnNetworkThread)`}. Фабрика-конструктор — обычный
  `BiFunction<RegistryFriendlyByteBuf, PlayMessageType<T>, T>`, свой интерфейс не нужен.
- **`register()` сам вешает клиентский приёмник** через `ModNetworking.hookClientReceiver(this)`,
  который **очередирует** его до вызова `ModNetworking.registerClient()`.
- **Следствие:** статического «пройтись по всем зарегистрированным и повесить клиентские приёмники»
  больше нет; в клиентском entrypoint зовётся `ModNetworking.registerClient()`.
- **Грабли, которых мы избежали:** `allowNullPlayer=false` (по умолчанию) — сообщение с `null`
  игроком **молча не исполняется**, в лог падает `WARN "Invalid packet received for - <класс>"`.
  В нашей копии такой проверки не было вовсе.
- **Подтверждено:** `PlayMessageType.java:21-25,32-203,220-233,236-255`.

### 1.4 `PlayMessageContext`: `flow()` вместо `isClientSide()`, `enqueueWork` возвращает future

- **На самом деле:** `player()`, **`PacketFlow flow()`**, `server()`,
  **`CompletableFuture<Void> enqueueWork(Runnable)`** (выполняет inline, возвращает завершённый future
  либо `failedFuture`).
- **Комментарий:** в Structurize ни одно из 25 сообщений контекст не читает, поэтому разница не
  всплыла. В MineColonies `IPayloadContext#enqueueWork(...).thenRun(...)` встречается — там форма
  с `CompletableFuture` важна.

### 1.5 `ServerLifecycleHooks` вместо самодельного `NetworkContext`

Держатель текущего `MinecraftServer` — `com.ldtteam.common.util.ServerLifecycleHooks`
(`getCurrentServer()`), инициализируется из `ModNetworking.register()`, который зовёт **BlockUI**
из своего общего entrypoint (`BlockUI.java:35`). Зависимому моду делать ничего не надо.
**Грабли:** вешается на `SERVER_STARTING`/`SERVER_STOPPED` (не `SERVER_STARTED`) — сервер доступен
уже во время старта.

### 1.6 `IFakeLevelBlockGetter` заметно богаче

Абстрактны только `getSizeX()` и `getSizeZ()`; всё остальное — `default`: `getMinX/Y/Z`,
`getMaxX/Y/Z` (**max включающий**, `min + size - 1`), `isPosInside`, `isPosOutside`, `getFluidState`
(за пределами AABB → `Fluids.EMPTY`), `getRawBlockState`, `getRawBlockStateFunction`,
**`getAABB()`** (конец эксклюзивный, `max + 1`), `describeSelfInCrashReport`.
**Подтверждено:** `IFakeLevelBlockGetter.java:16-127`.
**Следствие:** `getAABB()`, которого не хватало агенту D (`FINDINGS-D.md §10`), в настоящей
библиотеке есть; ручное построение AABB в `BlueprintRenderer` можно снять.

### 1.7 `FakeLevel` собран из четырёх дополнительных классов

Наш `FakeLevel` был одним файлом на 29 абстрактных методов. Настоящий тянет `FakeChunk`,
`FakeChunkSource`, `FakeLevelChunkSection`, `FakeLevelData`, `FakeLevelEntityGetterAdapter`,
`FakeLevelLightEngine` — то есть **настоящий чанк-сорс и настоящий light engine**, а не заглушки.
Дополнительно `realLevel()`, `getWorldPos()`, `getBrightness/getRawBrightness/getSkyDarken/
isBrightOutside`, `getHeight(Heightmap.Types,int,int)`.

`IFakeLevelLightProvider` тоже богаче: `forceOwnLightLevel()`, `getBlockLight`, `getSkyDarken`, плюс
default `getDayTime()`, `getSkyLight`, `getBrightness(LightLayer,BlockPos)`, `getRawBrightness(BlockPos,int)`.
**`getShade` там тоже нет** — наша деградация не была ошибкой, её сделали одинаково в обоих портах.

### 1.8 Конфиги: `ConfigValue` вместо `ModConfigSpec`, и персистентности нет вообще

`com.ldtteam.common.config.ConfigValue` (+ вложенные `BooleanValue`, `IntValue`, `LongValue`,
`DoubleValue`, `EnumValue`, `RestartType`, пустой токен `Builder`), и `Configurations`
**ничего не хранит на диске** — контракт K4 порта BlockUI, осознанный §10-срез.

| | наше | настоящее |
|---|---|---|
| конструктор `Configurations` | `(modId, clientF, serverF, commonF)` | `(clientF, serverF, commonF)` — **без modId** |
| конструктор `AbstractConfiguration` | `(Builder)` | `(Builder, String modId)` |
| сеттер значения | `setRaw` / `Configurations#set` | `ConfigValue#set` + `save()` + `Configurations#set` |
| метаданные | только `getPath()` | `getPath()`, **`getTranslationKey()`**, **`getComment()`**, `getDefault()` |
| набор `defineXxx` | boolean/int/double/string/enum | + `defineLong`, `defineList`, `defineListAllowEmpty` (по 3 перегрузки), `requiresWorldRestart/GameRestart/requires` |
| клиентский конфиг на сервере | создавался всегда | `BlockUI.isClient() ? ... : null` — **`getClient()` на выделенном сервере равен `null`** |

**Важно для порта GUI:** `client/gui/AbstractBlueprintManipulationWindow` строит страницу настроек
из `getTranslationKey()`/`getComment()` — в нашей копии их не было, в настоящей есть, так что
агенту C правки сводятся к строке импорта.

**Регрессия:** значения конфига больше **не сохраняются между запусками**.

### 1.9 `BlockToItemHelper`, `Codecs`, `LanguageHandler` — надмножества наших

- `BlockToItemHelper`: наши `getItemStack(state, be, player)` и `getItem(state)` на месте плюс
  `getItemStack(ServerLevel, BlockPos)`, `getItemStack(Level, BlockPos, Player)`,
  `getItemStackUsingPlayerPick(...)`, `saveBeToItem(...)`.
- `Codecs`: наш `forEnum(Class)` плюс `forArray`, `streamForArray`, `withEmpty`, `streamWithEmpty`,
  `wrapNullable`, `wrapNullableField`.
- `LanguageHandler`: `translateKey`, `setMClanguageLoaded`, `loadLangPath` совпали 1:1; `format(...)`
  в настоящей библиотеке **нет** (мы его добавляли, Structurize его не звал).
- `codec/XmlOps`, `codec/XmlValue`, `util/CompoundTagToClassReflection`,
  `language/{Client,Server}Locale`, `config/ClientConfigHelper` — типы, о существовании которых
  по call-site'ам Structurize узнать было нельзя вовсе.

### 1.10 Что из этого следует для порта MineColonies

1. **Библиотеку восстанавливать не надо** — она едет в jar-е BlockUI; MineColonies подключает
   `implementation files("libs/blockui-*.jar")` и `"blockui": "*"` в `depends`.
2. Механическая часть порта сети MineColonies = смена импортов. Ловушки ровно три:
   `registerClientReceivers()` → `ModNetworking.registerClient()`; `context.isClientSide()` →
   `context.flow()`; отправка «не в ту сторону» перестала компилироваться (см. 1.2).
3. **Конфиг MineColonies потеряет персистентность** — там конфигов на порядок больше, и это
   заметнее. Если её надо вернуть, чинить **один раз в BlockUI** (`Configurations` + `ConfigValue#save`),
   а не в каждом моде.
4. `ModNetworking.register()` из своего entrypoint-а звать не надо — BlockUI сделал.

---

## 2. Подключение BlockUI как зависимости

- `implementation files("libs/blockui-0.0.1.jar")` + `"blockui": "*"` в `depends` — сработало
  с первого раза, ровно как с Domum Ornamentum (`modImplementation` в Loom 1.17 не существует).
- **Fabric Loader ругается на fabric.mod.json самого BlockUI:**
  `The mod "blockui" contains invalid entries in its mod json: - Unsupported root entry "credits"`.
  WARN, загрузку не ломает; чинится в BlockUI (`credits` — не поле схемы 1, содержимое надо
  переносить в `authors`/`contributors`).

---

## 3. Рантайм-грабли, найденные первым `runServer` (компилятор их не видел)

### 3.1 `DataVersion` мода блокирует старт — 26.2 это `4903`

- **Симптом:** `RuntimeException: You are trying to run old mod on much newer vanilla` из
  `Structurize.checkDataFixer()`, **до** регистрации чего-либо; сервер не стартует вообще.
- **Причина:** `blueprints/v1/DataVersion` заканчивался на `v1_21_1(3955)` и `UPCOMING(3956)`;
  проверка `DataFixers.getDataFixer().getSchema(Integer.MAX_VALUE - 1).getVersionKey() >=
  UPCOMING.getDataVersion() * 10` при ванили 26.2 всегда истинна.
- **Данные версии 26.2 — `4903`.** Подтверждено: `/opt/mc-src/net/minecraft/DetectedVersion.java:28`
  (`new DataVersion(4903, "main")`). Старшая схема в `DataFixers.java` — `addSchema(4892)`,
  то есть ключ < 49040 и проверка проходит с `UPCOMING = 4904`.
- **Лечение:** `v26_2(4903, "26.2", UPCOMING)` + `UPCOMING(4903 + 1, ...)`.
- **Обобщение для любого порта:** мод, который сверяется с `SharedConstants` /
  `DataFixers.getDataFixer()`, падает на старте **до** всего остального. Такую проверку надо искать
  грепом по `getDataFixer\|SharedConstants.getCurrentVersion` **до** первого `runServer`.

### 3.2 Ингредиенты рецептов: `{"tag": …}` / `{"item": …}` больше не парсятся

- **Симптом:** `Couldn't parse data file 'structurize:<recipe>' … No key fabric:type in
  MapLike[{"tag":"c:ingots/iron"}]`. Рецептов в игре просто нет, всё остальное грузится.
- **Стало:** ингредиент — **строка**: предмет `"minecraft:iron_ingot"`, тег `"#minecraft:logs"`.
- **Подтверждено:** `/workspace/domum-ornamentum/26.2/src/main/generated/data/domum_ornamentum/recipe/white_paper_extra.json`
  (`"key": {"X": "minecraft:paper"}`) и `white_floating_carpet.json` (`"#c:strings"`).
- **Комментарий:** ошибка сообщает только **первый** сбойный ключ в файле — «починил один,
  получил следующий». Чинить скриптом сразу все ключи всех рецептов:
  ```python
  for name, v in key.items():
      if isinstance(v, dict):
          key[name] = ('#' + v['tag']) if 'tag' in v else v['item']
  ```
- **Отдельно:** в Structurize рецепты — **рукописные ресурсы**, а не датаген, поэтому `runDatagen`
  их бы не поймал.

### 3.3 `runServer` и stdin: команды через RCON, а не через пайп

Loom 1.17 **не пробрасывает stdin** в задачу `runServer` — `printf 'stop\n' | gradle runServer`
не делает ничего. Чтобы проверить дерево команд и реестры на живом сервере:

```sh
# в 26.2/run/server.properties после первого запуска
enable-rcon=true
rcon.password=<любой>
# rcon.port=25575 по умолчанию
```
дальше — 20-строчный клиент на сокетах (`struct.pack('<ii', id, type)`, тип 3 = auth, 2 = command).
Единственный способ выполнить команду на dev-сервере без клиента.

**Что проверять этим способом после каждого порта:**

| Команда | Что доказывает |
|---|---|
| `help <modid>` | дерево команд мода сериализовалось (ловит несериализуемые `ArgumentType`) |
| `summon minecraft:item ~ ~ ~ {Item:{id:"<mod>:<item>",count:1}}` | предмет зарегистрирован, `setId` не забыт, lang-ключ есть |
| `forceload add 0 0` + `setblock 0 100 0 <mod>:<block>` | блок зарегистрирован |
| `data get block …` | блок-сущность сохраняется/читается |

`setblock` без `forceload` отвечает `That position is not loaded` — спавн-чанки RCON-у не помогают.

### 3.4 Убить зависший dev-сервер

`pkill -f "[d]evlaunch"` — процесс называется `net.fabricmc.devlaunchinjector.Main`. Скобка вокруг
первой буквы обязательна, иначе `pkill` найдёт собственную командную строку.

---

## 4. Мелочи, подтверждённые на практике

- **`"render_type": "translucent"`** кладётся в корень JSON-модели блока — замена удалённого
  `ItemBlockRenderTypes.setRenderLayer`. Это и есть новый канал.
- **Ключ категории кейбиндов** — `key.category.<namespace>.<path>` (`id.toLanguageKey("key.category")`),
  старый `key.<mod>.categories.general` мёртв.
- **AccessWidener на приватный вложенный класс** требует **трёх** строк, и класс идёт первым:
  ```
  accessible	class	net/minecraft/util/datafix/fixes/ChunkPalettedStorageFix$MappingConstants
  accessible	field	net/minecraft/util/datafix/fixes/ChunkPalettedStorageFix$MappingConstants	FLOWER_POT_MAP	Ljava/util/Map;
  accessible	field	net/minecraft/util/datafix/fixes/ChunkPalettedStorageFix$MappingConstants	NOTE_BLOCK_MAP	Ljava/util/Map;
  ```
  Обращение из кода — через полное имя владельца:
  `ChunkPalettedStorageFix.MappingConstants.FLOWER_POT_MAP`. Заодно расшитый код тянет NBT-ренеймы:
  `getString(k)`/`getInt(k)`/`getBoolean(k)` → `getStringOr(k, "")` / `getIntOr(k, 0)` / `getBooleanOr(k, false)`.
- **Мёртвые строки AccessWidener удаляются без последствий** — `Frustum.cubeInFrustum(DDDDDD)I`
  и `Camera.setPosition(Vec3)` сняты, сборка и `runServer` зелёные.
- **`WARN "Failed loading packs from main folder path: ."`** от `ServerStructurePackLoader` —
  не регрессия порта, а отсутствие каталога `blueprints/` в свежем `run/`; так же вело себя 1.21.1.
