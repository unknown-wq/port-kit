# План порта BlockUI → Fabric / Minecraft 26.2

Составлен по `PORTING-BUNDLE-26.2.md` (§2 маршрут, §4 разведка, §5 контракты, §6 разбиение,
§9 правила, §10 деградация, §12 цикл, §13 приёмка). Статус: **черновик, ждёт утверждения.**

---

## 0. Разведка (§4) — сделана, цифры ниже

| | значение |
|---|---:|
| Java-файлов | **109** (107 main + 2 test) |
| Строк Java | **21 946** |
| Файлов с `net.neoforged.*` | **24** (22 % файлов, но 100 % риска) |
| Миксинов | **0** — пакета `mixin` нет вообще |
| Записей AccessTransformer | **14** (`META-INF/accesstransformer.cfg`) |
| Блоков / предметов / сущностей / рецептов / датагена / ворлдгена | **нет ни одного** |
| Внешних зависимостей | **нет** (`neoforge.mods.toml` объявляет только `neoforge` + `minecraft`) |
| Ресурсы | 5 XML интерфейса + XSD, 3 языка, 1 атлас-конфиг, 10 текстур, 1 тег |

**Что это означает практически.** Целые главы бандла к BlockUI не применяются: §8 «Регистрация»,
«Сущности и NBT», NOTES-A целиком (реестры/меню/рецепты/датаген), NOTES-B (сущности/NBT), приложение
про датаген DO. Применяются: **NOTES-C** (клиент, экраны, `GuiGraphicsExtractor`), сеть из NOTES-B §11–12,
и приложение DO про блочные модели/`ModelData`.

BlockUI — это на 90 % клиентская GUI-библиотека и на 10 % общий слой `com.ldtteam.common`,
от которого зависят Structurize и MineColonies.

---

## 1. Маршрут (§2): **один хоп, ось версии почти пустая, ось лоадера — вся работа**

Исходник — 26.1.2 на официальных именах Mojang (проверено: 25 файлов уже импортируют
`net.minecraft.resources.Identifier`, ванильного `ResourceLocation` в коде ноль).
По таблице §2 это строка «Fabric, уже Mojang-имена (26.1.x)» → **один хоп 26.1 → 26.2**.

Но добавляется вторая ось — **смена лоадера NeoForge → Fabric**, и именно она даёт весь объём:
entrypoints, регистрация клиентских хуков, сеть, конфиг, AccessTransformer → AccessWidener.

**Следствие для §7 (массовые ренеймы):** классического скрипта ренеймов Yarn→Mojang здесь
**не будет** — переименовывать нечего. Вместо него один прогон
`porting-26.2/port-resolve-imports.py` по готовому `/opt/mc-src`: он поймает классы, которые
между 26.1.2 и 26.2 просто переехали в другой пакет (заведомо — `RenderType` →
`net.minecraft.client.renderer.rendertype`). Отдельным коммитом, до правок агентов.

Порт живёт в новой папке **`26.2/`**; `26.1.2/` — только для чтения (§9 DON'T 7).

---

## 2. Замороженные контракты (§5) — до старта агентов

| № | Контракт | Владелец |
|---|---|---|
| **K1** | **`BOGuiGraphics` остаётся фасадом с той же публичной формой.** Его зовут 22 файла. Переписывается **только сам файл** — против `GuiGraphicsExtractor`; сигнатуры методов не меняются. Это аналог контракта C1 из §5 («229 вызовов `.get()` не трогаются») и главный рычаг всего порта. | C |
| **K2** | **Точки входа.** `mod/BlockUI.java` → `ModInitializer` (только `NAMESPACE_TO_ATLAS_MAP`, `resLoc`, `ContainerHook` тег). Новый `mod/BlockUIClient.java` → `ClientModInitializer`, и **вся** клиентская регистрация живёт только в нём. | A |
| **K3** | **Сеть.** `com/ldtteam/common/network/**` сохраняет публичную форму (`PlayMessageType`, `AbstractServerPlayMessage`, `AbstractClientPlayMessage`, дистрибьюторы). Ровно два имени, которые дёргает entrypoint: `register()` и `registerClient()`. **Форму менять нельзя — на неё завязаны Structurize и MineColonies.** | B |
| **K4** | **Конфиг вырезается по §10.** `ModConfigSpec` не имеет аналога ни в Fabric, ни в ванили. `AbstractConfiguration`/`Configurations`/`ClientConfigHelper` деградируют до полей со старыми дефолтами, **сохраняя call-site `XXX.get()`**. Запись в «Disabled content». | B |
| **K5** | **`ModelData` вырезается** (NOTES-C §1: аналога нет). Затрагивает `FakeLevel`, `FakeChunk`, `ItemIconWithBlockState`, `BlockStateRenderingData`. Параметр удаляется из сигнатур — **это изменение публичного API**, обязательная строка в «Contract deviations» для будущего порта Structurize. | B (fakelevel) + D (два клиентских) |
| **K6** | **`FMLEnvironment` → одна точка.** `BlockUI.isClient()` поверх `FabricLoader.getInstance().getEnvironmentType() == EnvType.CLIENT`. 7 файлов зовут только её. | объявляет A, зовут B/C |
| **K7** | **Владение общими файлами.** `26.2/build.gradle`, `settings.gradle`, `gradle.properties`, `fabric.mod.json`, `blockui.accesswidener`, `BlockUIClient.java` — редактор **только A**. `26.2/PORT-STATUS.md` — пишет **только оркестратор**, агенты отдают материал в финальном отчёте. | — |
| **K8** | **AccessTransformer → AccessWidener** (14 записей) — целиком на A, заголовок `accessWidener v1 official`. | A |

---

## 3. Разбиение по файлам (§6) — 4 агента, пересечений нет

Делим **по файлам, а не по пакетам**, как требует §6.

### Агент A — скелет, сборка, лоадер (первым и в одиночку)

**Файлы (9 + сборка):**
```
26.2/build.gradle, settings.gradle, gradle.properties
26.2/src/main/resources/fabric.mod.json          (из neoforge.mods.toml)
26.2/src/main/resources/blockui.accesswidener    (из accesstransformer.cfg, 14 записей)
26.2/src/main/java/com/ldtteam/blockui/mod/BlockUI.java
26.2/src/main/java/com/ldtteam/blockui/mod/BlockUIClient.java        (новый)
26.2/src/main/java/com/ldtteam/blockui/mod/ClientEventSubscriber.java
26.2/src/main/java/com/ldtteam/blockui/mod/ClientLifecycleSubscriber.java
26.2/src/main/java/com/ldtteam/blockui/mod/Log.java
26.2/src/main/java/com/ldtteam/blockui/mod/BlockStateTestGui.java
26.2/src/main/java/com/ldtteam/blockui/mod/ScrollingListsGui.java
26.2/src/main/java/com/ldtteam/blockui/mod/container/ContainerHook.java
```
**Gradle: разрешён (A один в чекауте).** Коммиты — нет, коммитит оркестратор.

Главная работа A — перевести **семь** NeoForge-регистраций, у каждой свой уровень неизвестности:

| NeoForge-хук | План | Риск |
|---|---|---|
| `AddClientReloadListenersEvent` (грузит `Loader`) | `ResourceLoader.get(PackType.CLIENT_RESOURCES).registerReloadListener(id, listener)` — бандл §NOTES-A 4 | низкий, форма подтверждена |
| `ClientTickEvent` | `ClientTickEvents.END_CLIENT_TICK` — NOTES-C §4 | низкий |
| `TagsUpdatedEvent` | `CommonLifecycleEvents.TAGS_LOADED` | низкий, подтвердить `javap` |
| `ModMismatchEvent` | удалить целиком (в Fabric нет версионного рукопожатия — NOTES-B §11) | нет |
| `RenderGuiLayerEvent` + `VanillaGuiLayers` | `HudElementRegistry` + `VanillaHudElements` — NOTES-C §4 | средний: у BlockUI перехват, а не добавление слоя |
| `InputEvent.MouseScrollingEvent` | прямого колбэка в Fabric нет → **скорее всего первый миксин мода** на `MouseHandler` | **высокий** |
| `RegisterTextureAtlasesEvent`, `RegisterRenderPipelinesEvent`, `RegisterPictureInPictureRenderersEvent` | аналоги в бандле **не описаны** → искать `javap`-ом по `fabric-api-0.154.2+26.2`; нет — миксин или §10 | **высокий, главная неизвестность порта** |

**Done-критерий A:** `gradle build --no-daemon` доходит до `compileJava`, зависимости резолвятся,
AccessWidener принимается Loom'ом; остаточные ошибки компиляции — только в файлах B/C/D.

### Агент B — `com.ldtteam.common` (28 файлов, ~5 500 строк)

```
common/network/**      7 файлов  — IPayloadContext / PayloadRegistrar / PacketDistributor → Fabric
common/config/**       3 файла   — ModConfigSpec → §10 срез (K4)
common/language/**     3 файла   — FMLEnvironment, ServerLifecycleHooks
common/codec/**        3 файла   — XmlOps 1232 стр., чистый DataFixerUpper, риск низкий
common/util/**         2 файла   — BlockToItemHelper (CreativeModeTabRegistry → вырезать)
common/fakelevel/**   10 файлов  — FakeLevel 2113 стр. + FakeChunk 873 стр.
```
**Gradle запрещён** (§6). Самопроверка — «Быстрая проверка типов» из §3.

`FakeLevel` — самый крупный файл мода и единственное место, где дельта ванили 26.1.2 → 26.2 бьёт
всерьёз: он реализует `Level` целиком. Плюс `PartEntity`, `FakePlayerFactory`, `ServerLifecycleHooks`,
`NeoForgeProxy`, `Lazy` — все NeoForge-only, все под §10.

Это **та самая библиотека, от которой зависят 36 файлов Structurize и 209 импортов MineColonies** —
поэтому K3/K5 здесь жёстче, чем где-либо ещё.

### Агент C — рендер-ядро и парсер XML (29 файлов, ~4 000 строк)

```
blockui/BOGuiGraphics.java        ← K1, ключевой файл всего порта
blockui/UiRenderMacros.java  911 стр. — RenderPipeline, свои 4 пайплайна
blockui/Pane.java            887 стр.
blockui/BOScreen.java        419 стр. — extract-then-render (NOTES-C §5)
blockui/PaneParams.java, Parsers.java, Loader.java, PaneBuilders.java,
blockui/Color.java, Alignment.java, MouseEventCallback.java, package-info.java
blockui/util/**  (13 файлов: texture/4, color/5, records/2, resloc/1, cursor/1, + 4 в корне util)
```
**Gradle запрещён.**

Узкое место: `util/resloc/OutOfJarResourceLocation extends Identifier` работает только если
AccessWidener агента A снял `final` с `Identifier` и открыл его `protected` конструктор —
единственная жёсткая связка между A и C, поэтому она вынесена в контракт K8.

### Агент D — виджеты, вьюхи, хуки (43 файла, ~6 500 строк)

```
blockui/controls/**   19 файлов — Button, TextField 684, AbstractTextElement 557, ItemIcon, EntityIcon…
blockui/views/**      14 файлов — BOWindow, ScrollingList*, ZoomDragView 423, DropDownList…
blockui/hooks/**       7 файлов — HookManager, HookRegistries 375, HookWindow, TriggerMechanism…
blockui/mod/item/**    2 файла  — BlockStatePipRenderer 341 (PictureInPicture), BlockStateRenderingData
blockui/support/DataProviders.java
```
**Gradle запрещён.**

Пишет **против фасада K1**, а не против `GuiGraphicsExtractor` напрямую — в этом весь смысл
контракта. Точечные ломки: `EntityIcon` (рендер сущности в GUI → NOTES-C §6),
`ItemIconWithBlockState` + `BlockStateRenderingData` (`ModelData` → K5),
`BlockStatePipRenderer` (регистрацию делает A, сам класс — D).

### Кто интегратор

Роль D-интегратор из §6 играют **оркестратор + свежие sweeper-агенты** по циклу §12:
оркестратор гоняет `compileJava` между фазами и раздаёт ошибки, а на каждый цикл красной сборки
нанимается свежий sweeper с коротким брифом (список ошибок + §10 + «сигнатуры грепать по
`/opt/mc-src`»), максимум **4 цикла**. Четыре рабочих агента A–D при этом заняты разбиением
исходника, а не интеграцией — иначе один из четырёх простаивал бы всю фазу 2.

---

## 4. Фазы (§12)

**Шаг 0 — оркестратор, сам.**
`gradle-dist/install.sh` → Java 25 + Gradle 9.6.1 → минимальный `26.2/build.gradle` с пинами §3
→ `genSources` **один раз** → распаковка в `/opt/mc-src` (~7055 файлов; Loom 1.17 может не оставить
джар, а записать хеш-кэш `~/.gradle/caches/fabric-loom/decompile/v1.zip` — разбирать скриптом)
→ копирование `26.1.2/src` → `26.2/src` **байт-в-байт**, отдельным коммитом
→ прогон `port-resolve-imports.py`, отдельным коммитом
→ `26.2/PORT-STATUS.md` (§11) → commit + push.

**Фаза 1 — A один.** Сборка, entrypoints, AccessWidener, семь хуков. Оркестратор компилирует,
коммитит, пушит.

**Фаза 2 — B, C, D параллельно.** Без Gradle, файлы не пересекаются. Оркестратор между отчётами
сам гоняет `compileJava` и раздаёт ошибки.

**Фаза 3 — интеграция.** `compileJava` → первые ~30 ошибок → правка → повтор; затем `build`
(тут применяются ресурсы и AW), затем `runServer` — один запуск на цикл.
Каждый цикл обязан либо уменьшить число ошибок, либо применить срез по §10. Максимум 4 цикла.

Ветка одна: `claude/mod-porting-plan-4-agents-wkqt7y`, `git push -u origin` с ретраями 2/4/8/16 с.

---

## 5. Приёмка (§13) — и честная оговорка

```sh
cd 26.2 && export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64
G=/opt/gradle-9.6.1/bin/gradle
$G compileJava --no-daemon
$G build       --no-daemon
mkdir -p run && echo "eula=true" > run/eula.txt
$G runServer   --no-daemon
```
Датагена у мода нет — шаг `runDatagen` из §13 не применяется.

**Оговорка, которую нельзя замалчивать.** BlockUI — библиотека GUI: на выделенном сервере она
не делает почти ничего. `runServer` здесь проверяет ровно одно — **безопасность загрузки классов**
(§14.4): что общий код не тянет клиентские типы в поля, супертипы и интерфейсы. Это ценно, но это
не проверка функциональности. Дисплея в контейнере нет, `runClient` не запустить, поэтому
**весь GUI-слой — 90 % мода — останется в статусе «чисто компилируется, никогда не исполнялся»**.
Так и будет записано в `PORT-STATUS.md → Verification`, а не выдано за проверенное.

Из этого следует приоритет §10 при срезах: сначала жертвуем визуальными эффектами
(курсоры, свои пайплайны, PiP-рендер блокстейта), в последнюю очередь — парсером XML и
`com.ldtteam.common`, потому что на них завязаны Structurize и MineColonies.

---

## 6. Зоны риска, по убыванию

1. **Три `Register*Event` без описанного аналога** (текстурные атласы, рендер-пайплайны,
   PictureInPicture-рендереры). Главная неизвестность. Решается `javap`-ом по fabric-api
   в первый же час фазы 1; если аналога нет — миксин, если и он не выходит — §10.
2. **AccessWidener из 14 записей AT.** У AW нет вилдкардов — `TooltipRenderUtil *` придётся
   разворачивать поимённо. `public-f net.minecraft.resources.Identifier` (снятие `final`) — это
   `extendable class`, а не `accessible`. Ошибка здесь роняет сборку целиком.
3. **`MouseScrollingEvent`** — вероятный первый миксин в моде, у которого миксинов не было.
4. **`FakeLevel` 2113 строк** — единственное место, где дельта ванили бьёт всерьёз.
5. **`ModelData` (K5)** — вырезание меняет публичный API, который читают Structurize и MineColonies.
6. **`OutOfJarResourceLocation extends Identifier`** — связка C ↔ AccessWidener агента A.
7. **`ModConfigSpec` (K4)** — гарантированный срез по §10, вопрос только в объёме.

---

## 7. Экономика (§9)

Окружение ставится один раз, `genSources` — один раз, `/opt/mc-src` не перегенерируется никем
(§6: зона оркестратора). Агенты B, C, D Gradle не запускают вообще. Каждый агент получает §1, §8,
§9, §10 + свою роль по шаблону §15.1; полную карту API свежим sweeper'ам не выдаём — их ошибки
уже конкретны. `runServer` — только в фазе 3, максимум один раз за цикл.
