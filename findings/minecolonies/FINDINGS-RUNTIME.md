# FINDINGS — MineColonies, рантайм-слой

Порт: NeoForge / MC 1.21.1 → Fabric / MC 26.2. 2051 файл, 9650 ошибок компиляции на старте.

Всё, что ниже, **компилятор не ловит**. Каждая запись стоила отдельного падения на живом запуске
и найдена только потому, что лестница приёмки шла до конца: `build` → `runDatagen` → `runServer`.
Компиляция дала ноль сигналов ни об одной из них.

Порядок соответствует тому, в каком они выстреливают, если идти по лестнице сверху вниз.

---

## Записи

### Компоненты предметов больше не привязаны к моменту регистрации

- **Было (NeoForge 1.21.1):** компоненты фиксировались при создании `Item`; `new ItemStack(item)`
  работал в любой момент после регистрации.
- **Стало (26.2):** `Item#<init>` только кладёт инициализатор в
  `BuiltInRegistries.DATA_COMPONENT_INITIALIZERS`. Реально привязывает их
  `ReloadableServerResources#updateComponentsAndStaticRegistryTags()`, и **больше никто**. Любой
  `new ItemStack(...)` до этого момента падает с
  `NullPointerException: Components not bound yet` из `Holder$Reference#components`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/item/Item.java:136,141`,
  `/opt/mc-src/net/minecraft/core/component/DataComponentInitializers.java:53,101`,
  `/opt/mc-src/net/minecraft/core/Holder.java:265`
- **Комментарий:** это самая дорогая запись во всём порте — она выстреливает в **четырёх разных
  местах**, и каждое выглядит как отдельный баг:
  1. статический инициализатор, который трогают на mod init (`RecruitmentItemsListener` строил
     `Map<Integer, ItemStack>` в `static final`);
  2. **весь датаген** — привязки там не происходит вообще, а `FabricDataGenerator.Pack#addProvider`
     вызывает фабрику провайдера сразу, так что падает даже конструктор провайдера;
  3. **декодирование рецептов** — оно идёт внутри того же релоада, но раньше привязки;
  4. **любой reload-листенер** — см. отдельную запись ниже.

  Ваниль обходит это тем, что хранит `ItemStackTemplate`, а не `ItemStack`. Если модель данных мода
  стоит на настоящих `ItemStack` (у нас ~300 мест: `ItemStorage`, `IRecipeStorage`, кастомные
  рецепты), переписывать её не надо — в датагене достаточно одной строки в начале генератора:

  ```java
  generator.getRegistries().thenAccept(provider ->
    BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(provider)
      .forEach(DataComponentInitializers.PendingComponents::apply));
  ```

  В рантайме так нельзя — там надо откладывать (следующая запись).

### Reload-листенер не имеет права строить `ItemStack`

- **Было (NeoForge 1.21.1):** `AddReloadListenerEvent`, листенер разбирал датапак и сразу строил
  свои `ItemStack`.
- **Стало (26.2):** `SimpleReloadInstance` над `result.listeners()` отрабатывает **до** того, как
  вызовут `updateComponentsAndStaticRegistryTags()`. Значит компоненты во время работы листенера
  ещё не привязаны, и разбор падает с `Item <id> does not have components yet`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/server/ReloadableServerResources.java:103` против
  `/opt/mc-src/net/minecraft/server/MinecraftServer.java:1550` и
  `/opt/mc-src/net/minecraft/server/WorldLoader.java:74`
- **Комментарий:** лечится откладыванием apply-стадии. Точка слива — **`CommonLifecycleEvents.TAGS_LOADED`**,
  а не `ServerLifecycleEvents.END_DATA_PACK_RELOAD`: Fabric инжектит `TAGS_LOADED` в `TAIL` самого
  `updateComponentsAndStaticRegistryTags`, то есть он общий для обоих путей, а `END_DATA_PACK_RELOAD`
  вызывается только из `MinecraftServer#reloadResources` и **не покрывает первый старт мира** — ровно
  тот путь, на котором сервер и падает.

  Вторая грабля тут же: **сливать очередь надо в порядке регистрации листенеров, а не в порядке
  прибытия.** Парковка происходит по завершении prepare-стадии, а они идут параллельно — это гонка.
  У нас `quests` выиграли её у `research`, и каждый квест с целью `minecolonies:research` молча
  выбрасывался с «research is null»: три обучающих квеста исчезли, сервер при этом стартовал.

### `BlockBehaviour.Properties` и `Item.Properties` требуют id до конструктора

- **Было (NeoForge 1.21.1):** мод строил блок, потом регистрировал его; id проставлялся реестром.
- **Стало (26.2):** `BlockBehaviour#<init>` вычисляет лут-ключ и descriptionId из `Properties`
  немедленно — `effectiveDrops()` делает `Objects.requireNonNull(this.id, "Block id not set")`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/state/BlockBehaviour.java:106,1155,1278`
- **Комментарий:** в ките это уже описано как пример к шаблону, но там нет второй половины, которая
  ломается **молча**: `BlockItem` больше не заимствует descriptionId у своего блока, дефолт стал
  `item.<ns>.<path>`. Ваниль ставит префикс в `Items#registerBlock`
  (`/opt/mc-src/net/minecraft/world/item/Items.java:2076`); без вызова `useBlockDescriptionPrefix()`
  **все block-item'ы теряют переводы** — в языковых файлах-то `block.<ns>.*`. У нас это 82 предмета,
  и ни одной ошибки в логе.

  Если имя блока — instance-метод (`getHutName()`), до `super(...)` его не вызвать; имя приходится
  делать параметром конструктора. Тогда обязательно добавьте проверку, что конструкторный аргумент
  совпадает с тем, что возвращает геттер: иначе блок зарегистрируется под одним именем, а
  лут-таблица и языковой ключ будут указывать на другое — тоже молча.

### Реестр с дефолтом, который никто не регистрирует, роняет игру на старте

- **Было (NeoForge 1.21.1):** `new RegistryBuilder<>(key).sync(true).defaultKey(<ns>:null)` — при том,
  что под этим именем ничего не регистрировалось. NeoForge это терпел.
- **Стало (26.2):** `BuiltInRegistries#validate` разрешает дефолт **каждого** defaulted-реестра во
  время `bootStrap()`, и незаполненный дефолт даёт
  `NullPointerException: Cannot invoke "Holder$Reference.value()" because "this.defaultValue" is null`
  до заглавного экрана.
- **Подтверждено:** `/opt/mc-src/net/minecraft/core/registries/BuiltInRegistries.java:313,334,340`,
  `/opt/mc-src/net/minecraft/core/DefaultedMappedRegistry.java:44`
- **Комментарий:** у нас так было объявлено 16 из 18 реестров мода. Такой реестр — defaulted только
  на бумаге: любой lookup, дошедший до дефолта, разыменовал бы тот же null. Правильный ответ —
  сделать их обычными (`FabricRegistryBuilder.create`, не `createDefaulted`), а `createDefaulted`
  оставить там, где дефолт действительно регистрируется.

### Типы аргументов команд обязаны регистрироваться на mod init

- **Было (NeoForge 1.21.1):** `ArgumentTypeInfos#registerByClass` из статического блока на самом типе.
- **Стало (26.2):** `ArgumentTypeRegistry.registerArgumentType` пишет в настоящий реестр, а статический
  блок на типе выполнится только когда команду впервые собирают — внутри `Commands.<init>` при первой
  загрузке датапаков, когда реестр уже заморожен:
  `IllegalStateException: Registry is already frozen (trying to add key <ns>:<arg>)`.
- **Подтверждено:** стек `Commands.<init>` → `ReloadableServerResources.<init>` →
  `MappedRegistry.validateWrite`; `/opt/mc-src/net/minecraft/core/MappedRegistry.java:90`
- **Комментарий:** на NeoForge статический блок проходил, потому что `registerByClass` заполнял только
  map классов, а не реестр. Переносить в общий `ModArgumentTypes`, который зовут из точки входа.

### `PathNavigation` больше не терпит `createPathFinder() == null`

- **Было (1.21.1):** мод, полностью заменяющий поиск пути, возвращал из `createPathFinder` `null` —
  объект не использовался.
- **Стало (26.2):** конструктор `PathNavigation` на серверном уровне сразу разыменовывает результат,
  чтобы подключить захват отладки путей.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/entity/ai/navigation/PathNavigation.java:62-66`
- **Комментарий:** следствие выглядит совершенно не как проблема навигации — **ни одна сущность мода
  не может быть создана**, в логе `Couldnt analyze animal: <ns>:<entity>`. Лечится возвратом
  настоящего, но неиспользуемого `new PathFinder(new WalkNodeEvaluator(), maxVisitedNodes)`.

### `runDatagen` гоняет генераторы всех модов на classpath

- **Было:** зависимости подключались так, что их датаген не участвовал.
- **Стало (26.2 / Loom 1.17):** зависимости, подключённые как `implementation files(...)`, видны Fabric
  как обычные моды со своими `fabric-datagen` entrypoint'ами. Все они пишут **в ваш** каталог, и
  `HashCache` каждого прогона удаляет файлы, которых этот прогон не писал.
- **Подтверждено:** `net.fabricmc.loom.api.fabricapi.DataGenerationSettings#getModId`; в логе
  `Running data generator for <чужой мод>`
- **Комментарий:** симптом — **вывод меняется от запуска к запуску**, и чистый прогон даёт чужие
  ассеты. Лечится `fabricApi { configureDataGeneration { modId = project.mod_id } }`. Пока это не
  сделано, любая сверка с оракулом бессмысленна.

### `BlockLootSubProvider` / `EntityLootSubProvider` требуют таблицу для всего в игре

- **Было (NeoForge 1.21.1):** `getKnownBlocks()` / `getKnownEntityTypes()` ограничивали проверку своими.
- **Стало (26.2):** этих методов нет; `generate(BiConsumer)` обходит весь `BuiltInRegistries.BLOCK` и
  падает на первом же чужом блоке: `Missing loottable 'minecraft:blocks/stone' for 'minecraft:stone'`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/data/loot/BlockLootSubProvider.java:839,851`,
  `/opt/mc-src/net/minecraft/data/loot/EntityLootSubProvider.java:120,131`
- **Комментарий:** для сущностей есть аккуратный выход — конструктор с **двумя** `FeatureFlagSet`:
  `allowed` = всё, `required` = `FeatureFlagSet.of()`. Для блоков так нельзя: там один флаг-сет, и он
  же гейтит цикл, который таблицы **выдаёт**, так что пустой набор просто не запишет ничего. Для
  блоков надо переопределить `add(Block, LootTable.Builder)`, запоминая свои таблицы, и отдавать в
  `generate(BiConsumer)` только их.

### `TagAppender#getBuilder()` возвращает `null` у того аппендера, который отдаёт ваниль

- **Стало (26.2):** `getBuilder()` — это default-метод фабриковского `FabricTagAppender`, и его тело
  буквально `return null`. Реализация приходит миксином на `TagAppender$1`, а `TagsProvider#tag(...)`
  и фабриковский `FabricTagsProvider#builder(...)` отдают `TagAppender.forBuilder(...)`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/data/tags/TagAppender.java:34-59`;
  `FabricTagAppender#getBuilder` в `fabric-data-generation-api-v1` (байткод: `aconst_null; areturn`)
- **Комментарий:** если нужен сырой `TagBuilder` — берите его у провайдера через
  `getOrCreateRawBuilder(key)` и таскайте рядом с аппендером, а не через `getBuilder()`.

### Ссылки на **свои** теги в датагене резолвятся только через lookup провайдера

- **Стало (26.2):** `BuiltInRegistries.ITEM.getOrThrow(TagKey)` находит только **привязанные** теги. В
  рантайме они привязаны, в датагене — нет, и тег, который вы прямо сейчас генерируете, даёт
  `Missing tag <ns>:<tag>`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/core/MappedRegistry.java:372-380` — у lookup'а,
  который отдаёт `HolderLookup.Provider` провайдера, `getOrThrow(TagKey)` вызывает
  `getOrCreateTagForRegistration` и создаёт holder-set по требованию.
- **Комментарий:** тем же путём идёт ванильный `RecipeProvider` (`this.items.getOrThrow(tag)`).

### Свои динамические записи не видны валидатору тегов, если писать их кодек-провайдером

- **Стало (26.2):** `FabricCodecDataProvider` пишет json, но ничего не кладёт в
  `HolderLookup.Provider`, против которого `TagsProvider#run` валидирует ссылки. Тег
  `minecraft:bypasses_armor`, ссылающийся на ваш тип урона, роняет весь прогон:
  `Couldn't define tag ... missing following references`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/data/tags/TagsProvider.java:79`
- **Комментарий:** записи надо дополнительно бутстрапить в `DataGeneratorEntrypoint#buildRegistry`.
  Двойной записи не будет, если `FabricDynamicRegistryProvider` этот реестр не перечисляет.

### `src/main/generated` может пересекаться с `src/main/resources` — и это не всегда мусор

- **Комментарий:** `processResources` падает на дубликате, и рефлекс «удалить копию из resources»
  бывает неверным. У нас 38 из 39 пересечений — квесты, где копия в `resources` является **входом**
  датагена: `QuestTranslationProvider` читает авторскую версию с литеральным английским, выносит
  строки в `lang/quests.json` и пишет в `generated` отгружаемую версию с ключами. Удалите авторскую —
  и генератор начнёт читать собственный вывод: все 637 строк квестов станут собственными ключами,
  без единой ошибки в логе. Правильный ответ — `duplicatesStrategy` в `processResources`, generated
  монтируется после resources и выигрывает.

---

## Сверка датагена с оракулом — что считать нормой

После зелёного `runDatagen` мы продиффили весь вывод с оракулом предыдущей версии
(`1.21.1/src/datagen/generated`). Полезно знать заранее, что расхождения будут массовыми и почти все
законные:

- **Текстуры сравнивайте по пикселям, а не по байтам.** У нас 3481 сгенерированная иконка
  различалась побайтно и оказалась **попиксельно идентичной** — разница только в метаданных
  PNG-кодировщика.
- Из 396 различающихся JSON **все** различия — эволюция ванильных кодеков: опущенные дефолты
  (`bonus_rolls`, `category`, `count`, `cookingtime`), ингредиенты, свёрнутые из `{"item": "x"}` в
  строку `"x"`, теги из `{"tag": "x"}` в `"#x"`.
- Расхождение, которое **надо чинить, а не записывать**: если свёртка задела **ваш собственный**
  формат. У нас стоимости исследований писались как `{"tag": …}`, а стали `{"item": "#…"}` — это ломает
  сторонние датапаки. Дешевле научить свой кодек читать обе формы (`Codec.withAlternative`), чем
  объявлять несовместимость.
- Новые файлы, которых в оракуле нет: с 1.21.4 **обязателен item model definition на каждый предмет**
  (`assets/<ns>/items/*.json`). Без них все предметы мода — розово-чёрный куб.

---

## Чего эта копилка не покрывает

Клиент. В контейнере нет дисплея, `runClient` не поднимается, поэтому для клиентского слоя (у нас
314 файлов и весь GUI) установлено только «компилируется». Все записи выше проверены на выделенном
сервере и в датагене.
