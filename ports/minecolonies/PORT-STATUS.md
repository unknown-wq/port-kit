# PORT-STATUS — MineColonies → Fabric / Minecraft 26.2

Живой документ порта (§11 бандла). **Пишет только оркестратор.** Агенты читают, но не правят:
всё для этого файла — срезы, отклонения, результаты — передают в финальном отчёте.

Закон порта — [`../PORTING-BUNDLE-26.2.md`](../PORTING-BUNDLE-26.2.md).
План этого мода — [`../PORT-PLAN.md`](../PORT-PLAN.md).

---

## Toolchain — готово, не переустанавливать

| | |
|---|---|
| Java | `/usr/lib/jvm/java-25-openjdk-amd64` |
| Gradle | `/opt/gradle-9.6.1/bin/gradle` — **никогда не `./gradlew`** (прокси отдаёт 403 на ассеты GitHub) |
| Проект | `/home/user/minecolonies/26.2` |
| Исходник (только чтение) | `/home/user/minecolonies/1.21.1` — **не редактировать** |
| Декомпилированная ваниль | `/opt/mc-src` — **7055 файлов, готово** |
| `/opt/mc-src` готов | **ДА** — не перегенерировать, только `grep -rn` |

Любая сборка:

```sh
cd /home/user/minecolonies/26.2 && JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64 \
  /opt/gradle-9.6.1/bin/gradle <task> --no-daemon 2>&1 | tee /tmp/errors.txt
```

**Одна инвокация Gradle одновременно.** Две параллельные — порча кэша Loom.

### Референс-моды на диске

Портированные и доведённые до зелёного сервера 26.2-моды. Бандл в каждом рецепте говорит
«скопируй форму из портированного мода» — вот они.

| Мод | Путь | Природа | Кому полезен |
|---|---|---|---|
| **Domum Ornamentum** | `/workspace/domum-ornamentum/26.2` | NeoForge 26.1 → Fabric 26.2, тот же LDT Team | всем; `build.gradle`, `fabric.mod.json`, entrypoints, `PORT-STATUS.md` и `PORT-GAPS.md` завершённого порта |
| **simple-planes** | `/workspace/simple-planes/26.2` | **NeoForge 1.21.1 → Fabric 26.2 — тот же маршрут, что у нас** | `simpleplanes.accesswidener` как прямой перевод AT→AW; экраны на `GuiGraphicsExtractor` |
| **BlockUI** | `/workspace/blockui/26.2` | одновременно зависимость и образец | весь GUI-слой |

### Зависимости

| Библиотека | Статус | Путь |
|---|---|---|
| Domum Ornamentum | ✅ портирован, приёмка зелёная (28/28 нужных классов на месте) | `/workspace/domum-ornamentum/26.2` |
| BlockUI | ✅ синхронизирован с `version/main` (`74651c8`) | `/workspace/blockui/26.2` |
| `com.ldtteam.common` | ✅ **внутри BlockUI**, 10/10 нужных классов | `/workspace/blockui/26.2/src/main/java/com/ldtteam/common` |
| Structurize | ✅ подключён, работает: структурные паки регистрируются на живом сервере | `/workspace/structurize/26.2` |

**Оба наших запроса к BlockUI закрыты** в `74651c8`:

* `97ee934` — **`ColouredVertexConsumer` возвращён** как публичный API. Агент D к тому моменту уже переписал `ColonyBorderRenderer` на кэш вершин + `submitCustomGeometry`, так что обёртка нам больше не нужна, но она снова есть.
* `64f586b` — **синк server-конфигов клиенту** (`ConfigSync`, `ConfigSyncManager`, `ConfigSyncMessage`). Это был наш приоритет №1: 56 из 65 настроек MineColonies серверные, и без синка клиент на удалённом сервере принимал решения по своим значениям.

⚠️ **Блокер, открытый на BlockUI:** на `74651c8` живы два краша в `com.ldtteam.common.language`, из-за которых **не стартует ни один зависимый мод** — ни MineColonies, ни Structurize. Разбор и патч: `HANDOFF-TO-BLOCKUI-2.md` и `BLOCKUI-RUNTIME-FIXES.patch`. PR готовится в самом репозитории BlockUI (ветка `claude/fix-mod-init-crashes`); до его merge наша сборка требует локально применённого патча.

**`ldtteam.common` закрывает сеть и конфиг.** `PlayMessageContext` написан прямой заменой
NeoForge'ового `IPayloadContext`, `ModNetworking.register()/registerClient()` — заменой
`PayloadRegistrar`, `ConfigValue.*` — заменой `ModConfigSpec.*`. Сигнатуры `PlayMessageType.forClient/forServer`
и конструкторы `AbstractClientPlayMessage` совпадают с тем, что мод уже пишет. Из 129 файлов,
берущих `IPayloadContext`, метод на нём вызывает **ровно один** — остальные 128 принимают
параметром и не трогают. Регистрация сети и конфига целиком в `core/MineColonies.java`.

---

## Прогресс

### Э0 — окружение и каркас ✅

| | |
|---|---|
| JDK 25, `unrar` | установлены |
| Gradle 9.6.1 | `/opt/gradle-9.6.1` из вендоренного `gradle-dist/` |
| `26.2/` каркас | `settings.gradle`, `gradle.properties`, `build.gradle` на Loom 1.17.13 |
| Пины | MC `26.2`, loader `0.19.3`, fabric-api `0.154.2+26.2`, Java 25, без `mappings` |
| `genSources` | ✅ 7055 файлов → `/opt/mc-src` |
| `fabric.mod.json` | написан, entrypoints `com.minecolonies.core.MineColonies` / `MineColoniesClient` |
| AccessWidener | ✅ 84 строки AT → 43 записи AW, `validateAccessWidener` зелёный |
| Точки входа | скелетные `ModInitializer` / `ClientModInitializer` — заполняет агент A |
| `build` | ✅ зелёный |
| `runServer` | см. «Приёмка» |

### Э2 — агенты

| Волна | Агент | Зона | Статус |
|---|---|---|---|
| 1 | **S** | стабы Structurize | ✅ 84 файла, 132 типа; ошибки Structurize 454 → 0 (стабы позже заменены настоящей библиотекой) |
| 1 | **B** | `core/colony/**` | ✅ 208 из 404 файлов тронуто; ошибки зоны 1433 → 1 |
| 1 | **A** | `api/**` | ✅ зона закрыта |
| 1 | **C** | `core/entity/**` | ✅ зона закрыта |
| 2 | **F** | точка входа, `apiimp/**`, `core/event/**` | ✅ 37 файлов; ошибки зоны ~700 → 13 (все в чужих файлах) |
| 2 | **E** | `core/generation/**` | ✅ 35 из 55 файлов + 2 новых; ошибки зоны **592 → 0** |
| 2 | **D** | `core/client/**` | ✅ 191 файл; ошибки зоны **~942 → 0** |
| 2 | **G** | остальной `core/**` | ✅ ~250 файлов; ошибки зоны → 0 |
| 3 | **H** | registry-id блоков и предметов | ✅ 83 файла; рантайм-дефект, компилятору невидимый |
| 3 | **I** | порядок datapack-листенеров | ✅ 4 файла; отложенная apply-стадия |

**Механика до агентов** (оркестратор): дерево переехало в `26.2/src`, 148 переехавших
импортов ванили перенаправлены, `ResourceLocation` → `Identifier` (2087 ссылок + 1648
конструкторов), `IPayloadContext` → `PlayMessageContext` (268), `ModConfigSpec` →
`ConfigValue` (6).

**JEI и JourneyMap припаркованы** — 3826 строк в 25 файлах выведены из компиляции через
`optional-integrations.txt`, файлы на месте. Разрыв чистый: `Compatibility.jeiProxy` и так
по умолчанию no-op, ссылок снаружи нет. Вернуть = удалить строку из списка.

**`Tuple` решён глобально**: `net.minecraft.util.Tuple` в 26.2 нет, у мода есть свой с тем
же `getA()/getB()` — на него переведены все 52 оставшихся файла, 5 полных ссылок и стабы.

### Ошибки компиляции

| Момент | Ошибок | Файлов |
|---|---|---|
| Базовая линия (сразу после переезда) | 9650 | 856 |
| После стабов Structurize | 8520 | — |
| После зоны B | 7314 | 538 |
| После зоны C | 6764 | — |
| Замена стабов на настоящий Structurize | 6974 | — |
| После зоны F | 1134 | 140 |
| После зоны E | 658 | — |
| После зоны D | 260 | — |
| После зоны G | **0** | **0** |

Замена стабов на живую библиотеку стоила **+104 ошибки**, из них лишь 32 упоминают
`structurize`. Это и есть отдача от того, что стабы генерировались из настоящих исходников
1.21.1, а не выдумывались.

### Э1, Э3–Э6

Не начаты.

---

## AccessWidener — что не пережило пять версий

84 строки AT дали 59 уникальных записей: **43 перенесены, 16 мертвы**. Каждая мёртвая —
это правка в коде мода, а не в AW. Полный разбор с причинами — в комментариях
`src/main/resources/minecolonies.accesswidener`, коротко:

| Что | Стало |
|---|---|
| `ResourceLocation.<init>(String,String)` | класса нет: `resources.Identifier` + `Identifier.fromNamespaceAndPath(...)` |
| `RenderStateShard.setupState` | класса нет — 26.x переписал рендер-пайплайн |
| `HumanoidArmorLayer.armorTrimAtlas` | тримы уехали в `EquipmentLayerRenderer` |
| `HumanoidArmorLayer.getArmorModel` / `renderArmorPiece` | **живы, но сигнатуры другие** — берут render state, не сущность |
| `DistanceManager.tickets` | → `ticketStorage` типа `TicketStorage` |
| `Sheep.ITEM_BY_DYE` | поля нет; сам класс уехал в `world.entity.animal.sheep` |
| `Entity.updateFluidOnEyes()` | метода нет |
| `GoalSelector.profiler` | не поле: `Profiler.get()` внутри `tick()` |
| `ThrownPotion.applySplash(...)` ×2 | класс распался на `AbstractThrownPotion` / `ThrownSplashPotion` / `ThrownLingeringPotion`, метода нет нигде |
| `AbstractMinecart.lerpSteps/X/Y/Z/XRot/YRot` | интерполяция уехала в `Entity.InterpolationHandler` и `NewMinecartBehavior` |
| `AbstractFurnaceBlockEntity.isLit()` | → поле `litTimeRemaining` |
| `Block.canSurvive(...)` | уехал вверх в `BlockBehaviour`, там `protected` |
| `AbstractArrow`, `AbstractMinecart` | живы, но на пакет ниже: `projectile.arrow.*`, `vehicle.minecart.*` |

---

## Отложенное — ждёт первого зелёного `runDatagen`

**Дубликаты ресурсов (те же грабли, что описаны в `PORT-GAPS.md` у Domum Ornamentum).**
`src/main/generated` смонтирован вторым resource-root'ом главного sourceSet, и
`processResources` упадёт на пересечении с `src/main/resources`. Пересечение посчитано —
**39 файлов**, и датаген из них реально владеет:

* `assets/minecolonies/models/item/cooked_rice.json` — единственное пересечение по моделям;
* `data/minecolonies/colony/quests/**` (~38 файлов) — **не косметика**:
  `QuestTranslationProvider` выносит литеральный английский текст в `lang/quests.json` и
  подставляет ключи. В `src/main/resources` лежит *авторская* версия с литералами, в
  `src/main/generated` — *отгружаемая* с ключами. Победить обязана сгенерированная, иначе
  квесты потеряют переводимость.

Рецепт: после зелёного `runDatagen` и сверки с оракулом удалить эти файлы из
`src/main/resources`.

### Ожидаемые расхождения с оракулом `1.21.1/src/datagen/generated` — не деградации

* 3 рецепта `minecolonies:composting` — поле `input` меняет форму: NeoForge
  `CompoundIngredient` (голый массив) → Fabric `{"fabric:type":"fabric:any","ingredients":[…]}`.
  Набор предметов тот же.
* `data/minecolonies/loot_modifiers/**`, `data/neoforge/loot_modifiers/**`,
  `data/neoforge/data_maps/**` больше не пишутся — их заменил рантайм-код (см. «Восстановлено»).
* `assets/minecolonies/items/*.json` — **новые файлы, которых в оракуле нет.** С 1.21.4
  item model definition обязателен для каждого предмета, а в `src/main/resources` их нет
  вовсе. Без них **все предметы мода — розово-чёрный куб.**
* `#minecraft:trim_templates` в 26.2 удалён из ваниллы — его прежнее содержимое
  (18 `*_armor_trim_smithing_template`) выписано поимённо.

---

## Contract deviations

_(Любая сигнатура, которую агент был вынужден изменить против контракта. Интегратор читает первым.)_

---

## Disabled content

### Защита колонии — 6 разрешений не работают (агент B, ступень 3)

Все в `ColonyPermissionEventHandler`. Причина одна: в Fabric нет соответствующего события.
**Это заметная потеря для игрока — колония перестаёт быть защищённой от этих действий.**

| Разрешение | Было (NeoForge) |
|---|---|
| `PLACE_BLOCKS` / `PLACE_HUTS` | `BlockEvent.EntityPlaceEvent` |
| `EXPLODE` — и весь конфиг `turnOffExplosionsInColonies` | `ExplosionEvent.Start` / `.Detonate` |
| `TOSS_ITEM` | `ItemTossEvent` |
| `PICKUP_ITEM` | `ItemEntityPickupEvent.Pre` |
| `FILL_BUCKET` | `VanillaGameEvent` FLUID_PICKUP |
| `SHOOT_ARROW` | `ArrowLooseEvent` |

Сохранены и работают: `BREAK_BLOCKS`, `BREAK_HUTS`, `ACCESS_HUTS`, `ACCESS_TOGGLEABLES`,
`RIGHTCLICK_BLOCK`, `RIGHTCLICK_ENTITY`, `OPEN_CONTAINER`, `THROW_POTION`, `USE_SCAN_TOOL`,
`ATTACK_CITIZEN`, `ATTACK_ENTITY`, подавление урона стражником своей колонии в рейде.

**Не считать это окончательным.** Как минимум `PLACE_BLOCKS` восстановим через
`UseBlockCallback` — установка блока идёт через использование предмета по блоку, а этот
коллбек уже подключён для `RIGHTCLICK_BLOCK` и умеет отменять. Вернуться к этому после
зелёной сборки.

### Точечные деградации

| Что | Последствие |
|---|---|
| `TravellingManager` перешёл с `NbtUtils.writeBlockPos` на `BlockPos.CODEC` | **формат сейва этого поля изменился** — старые миры прочитают `BlockPos.ZERO` |
| `entity.isAddedToLevel()` (расширение NeoForge, 11 мест) → `!entity.isRemoved()` | не отличает «ещё не добавлен» от «удалён» |
| `LivingDamageEvent.Pre#setNewDamage(0)` → `ALLOW_DAMAGE` возвращает `false` | Fabric умеет только отменить урон целиком, не обнулить; в этом месте эффект тот же |
| `contains(key, TYPE)` → `contains(key)` | тип NBT-значения больше не проверяется, только наличие ключа |
| `Capabilities.ItemHandler.BLOCK` → `blockEntity instanceof Container` | определение «это контейнер» стало ванильным, а не капабилити-based (C4) |
| `build_goggles`: оверрайд модели `minecraft:disabled` выкинут | очки строителя не переключаются на «выключенную» текстуру; ждёт регистрации `ConditionalItemModelProperty` в зоне D |
| `ItemNbtCalculator`: `instanceof ArmorItem` → `EQUIPPABLE` в слот брони | шире оригинала — `dyed_color` попадёт также к тыкве, головам и элитре (в оракуле было ровно 44 предмета) |
| `DatagenLootTableManager` читает только ванильный дата-пак | вложенная ссылка на *свою* лут-таблицу даст неполный список дропов (с записью в лог); сегодня таких нет |
| `getKnownBlocks` / `getKnownEntityTypes` удалены (в 26.2 нет у супертипа) | потеряна датаген-проверка «не забыл ли блок»; содержимое таблиц не изменилось |
| **`SpearItemTileEntityRenderer` убран** — `BlockEntityWithoutLevelRenderer` удалён, Fabric-аналога `IClientItemExtensions#getCustomRenderer` нет (ступень 4) | копьё в инвентаре и в руке — плоская item-модель. Чинится датагеном: `"minecraft:special"` в `items/spear.json` |
| Фонарь на пугале (`BlockRenderDispatcher#renderSingleBlock`) | пугало рисуется без фонаря |
| Креатив-плейсхолдер над колони-флагом (`ItemRenderer#renderStatic`) | нет подсказки при держании баннера |
| Ветка ванильных рецептов в `RestaurantMenuModuleWindow` (`Level#getRecipeManager` на клиенте нет) | разбор ингредиентов идёт только по кастомным рецептам MineColonies |
| `IClientItemExtensions#getArmPose` | предметы чужих модов не переопределяют позу рук цитизена |
| `ParticleTypes.DRAGON_BREATH` → `END_ROD` при создании колонии | в 26.2 это `ParticleType<PowerParticleOption>`, а `VanillaParticleMessage` принимает только `SimpleParticleType` — другой эффект |
| `Model#renderToBuffer` в 26.2 финальный и рисует **весь** `root()` | у дефолтной (fallback) модели цитизена, испечённой из `ModelLayers.PLAYER`, теперь рисуются оверлеи (`jacket`, `*_sleeve`, `*_pants`), которых в 1.21.1 не было. Собственные job-модели мода не затронуты. **Компилятор это не поймает** |

### Восстановлено после отчёта агента E

Две потери, которые агент E оставил как данные без потребителя, оркестратор подключил:

| Что было мертво | Чем закрыто |
|---|---|
| **Колонийские культуры не выпадали из ванильных блоков, сундуки припасов не появлялись в 27 ванильных чест-таблицах** — NeoForge global loot modifiers на Fabric нет | `EventHandler#onLootTableLoad` теперь читает `DefaultLootModifiersProvider` напрямую: модификатор «добавить таблицу T при условии C» стал пулом с одной `NestedLootTable.lootTableReference(T)` под `C`. Гейт `GenerateSupplyLoot` (конфиг `generateSupplyLoot`) сохранён |
| **Предметы мода нельзя было класть в ванильный компостер** — NeoForge data maps на Fabric нет | `DefaultDataMapsProvider.compostables()` заливается в `CompostableRegistry.INSTANCE` на `TAGS_LOADED` |

Ещё две — после отчёта агента D, в `ClientRegistryHandler`:

| Что было мертво | Чем закрыто |
|---|---|
| Оверлеи колони-карты и планшета на предмете в инвентаре | оба декоратора переписаны на `ExtractItemDecorationsCallback` и фильтруют стек сами (коллбек глобальный, а не по предмету) |
| Кавалерийская лошадь **не компилировалась**: `RegistrationHelper#register` инвариантен по рендер-стейту — модель `HorseRenderer` это `EntityModel<EquineRenderState>`, а слой `RenderLayer<HorseRenderState,…>`, так не зарегистрировать даже ванильный `HorseMarkingLayer` | `HorseRenderer` в 26.2 `final`, поэтому появился свой `CavalryHorseRenderer`: он добавляет `CavalryOverlayLayer` сам и **единственный** может прочитать боевую готовность с сущности — слои её больше не видят, значение едет на рендер-стейте |

Все четыре — на `TAGS_LOADED` / в момент загрузки таблиц / в клиентской регистрации, а не в `onInitialize`: таблица
компостируемости выводится из компонента `FOOD` каждого предмета, который во время
`onInitialize` ещё не привязан (та же ловушка, из-за которой туда же вынесен
`ModEquipmentTypes.initRegisterEquipmentTiers()`).

> Поправка к отчёту агента E: в fabric-api `0.154.2+26.2` класс называется
> **`CompostableRegistry`**, а не `CompostingChanceRegistry` — проверено по джару
> `fabric-content-registries-v0-11.2.2`.

---

## Verification

| Шаг | Результат |
|---|---|
| `compileJava` | ✅ зелёный на каркасе (2 файла точек входа) |
| `build` | ✅ зелёный, `validateAccessWidener` проходит |
| `runDatagen` | ✅ **зелёный и воспроизводимый** — 5039 файлов, сверен с оракулом `1.21.1/src/datagen/generated` (см. ниже) |
| `runServer` | ✅ **зелёный на чистом мире с полным кодом мода.** `Done (6.327s)! For help, type "help"`, **ноль строк `/ERROR]`**. Данные загрузились по-настоящему: 161 рецепт для 16 крафтеров, 208 исследований в 4 ветках, 103 эффекта, квесты, 1761 предмет с NBT-ключами |

Это уже приёмка **порта**, а не каркаса: в сборке весь код мода, датаген отработал и сверен
с оракулом, сервер поднялся и разобрал все свои датапаки без единой ошибки.

**Чего эта приёмка принципиально не покрывает: клиент.** Дисплея в контейнере нет,
`runClient` не запускается. Для `client/**` — 314 файлов и весь GUI — устанавливается
**только чистая компиляция**, и выдавать это за проверенную работоспособность нельзя.
Для мода, у которого GUI составляет половину ценности, это существенная дыра; закрывает
её пользователь вручную по чеклисту Э6 в плане.
