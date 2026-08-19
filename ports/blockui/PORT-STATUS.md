# PORT-STATUS — BlockUI → Fabric / Minecraft 26.2

Живой документ порта (§11 бандла). **Пишет только оркестратор.** Агенты читают, но не правят:
всё для этого файла — срезы, отклонения, результаты — передают в финальном отчёте.

---

## Toolchain — готово, не переустанавливать

| | |
|---|---|
| Java | `/usr/lib/jvm/java-25-openjdk-amd64` (openjdk 25.0.3) |
| Gradle | `/opt/gradle-9.6.1/bin/gradle` — **никогда не `./gradlew`** (403 на ассеты GitHub) |
| Проект | `/home/user/BlockUI/26.2` |
| Исходник (только чтение) | `/home/user/BlockUI/26.1.2` — **не редактировать** (§9 DON'T 7) |
| Декомпилированная ваниль | `/opt/mc-src` — **7055 файлов, готово** |
| `/opt/mc-src` готов | **ДА** — не перегенерировать, только `grep -rn` |
| Референс-моды на диске | **четыре, см. таблицу ниже** |

Любая сборка:
```sh
cd /home/user/BlockUI/26.2 && JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64 \
  /opt/gradle-9.6.1/bin/gradle <task> --no-daemon 2>&1 | tee /tmp/errors.txt
```
**Одна инвокация Gradle одновременно.** Две параллельные — порча кэша Loom.

### Референс-моды на диске — все четыре из бандла

Это **портированные и доведённые до зелёного сервера** 26.2-моды. Бандл в каждом рецепте говорит
«скопируй форму из портированного мода» — вот они. `26.2/` внутри каждого репозитория — это уже порт,
соседние `1.21.1/` и `26.1/` — исходники до порта, полезны как «было → стало».

| Мод | Путь | Природа | Кому полезен |
|---|---|---|---|
| **Domum Ornamentum** | `/workspace/domum-ornamentum/26.2` | **NeoForge 26.1 → Fabric 26.2, тот же LDT Team** — ближайший аналог этой задачи | **всем**; A: `build.gradle`, `fabric.mod.json`, entrypoints; есть `PORT-STATUS.md` и `PORT-GAPS.md` завершённого порта |
| **simple-planes** | `/workspace/simple-planes/26.2` | NeoForge 1.21.1 → Fabric 26.2 | **A: `simpleplanes.accesswidener` — прямой перевод AT→AW с комментарием**; C/D: 4 экрана на `GuiGraphicsExtractor` |
| **desolation** | `/workspace/desolation` | Fabric 1.21.6 → 26.1.2 → 26.2 | A: `desolation.accesswidener` (крупный, с секциями); `client/hud/DesolationHudElements.java` — **живой `HudElementRegistry`** |
| **Fabric-LuckyTNTMod** | `/workspace/fabric-luckytntmod` | Yarn 1.21 → 26.2, две части (`TntLib` + `tntmod`) | `tntmod/.../client/overlay/OverlayTick.java` — `GuiGraphicsExtractor` в оверлее; скрипты `port-*.sh/py` |

**Приоритет источников истины для агента** (§9 DO 1–2):

1. **референс-мод** — там та же задача уже решена, копировать форму, а не сочинять;
2. `/opt/mc-src` — декомпилированная ваниль 26.2, `grep -rn`; **выше бандла по авторитету**;
3. `javap` по джарникам fabric-api в `/root/.gradle/caches/modules-2/files-2.1/net.fabricmc.fabric-api/`
   — единственный способ узнать форму Fabric API, которой нет ни в ваниле, ни в референсе;
4. `/home/user/BlockUI/PORTING-BUNDLE-26.2.md` — цитаты из него в отчёте помечать «из бандла»:
   он ниже по авторитету, чем первые три, и содержит известные ошибки.

**Референс-моды — только для чтения.** Не редактировать, не собирать, Gradle в них не запускать.

### Уже подтверждено оркестратором на этом окружении

Чтобы агенты не тратили на это попытки:

- `ResourceLocation.java` в `/opt/mc-src/net/minecraft/resources/` **отсутствует**, есть `Identifier.java`.
- `GuiGraphics.java` в `/opt/mc-src/net/minecraft/client/gui/` **отсутствует**, есть `GuiGraphicsExtractor.java`.
- **Конфигураций `modImplementation`/`modApi` у Loom 1.17.13 нет** — ремапить нечего, только
  `implementation`. Это уже стоило одного прогона Gradle.
- Форма `build.gradle`/`gradle.properties`/`settings.gradle` выровнена по
  `/workspace/domum-ornamentum/26.2` и собирается: `genSources` зелёный.
- AccessWidener подключается через `loom { accessWidenerPath = file(...) }` **и** строку
  `"accessWidener": "blockui.accesswidener"` в `fabric.mod.json`
  (образец — simple-planes, у которого есть обе).

---

## Rules (выжимка §9 + §10 — читать первым)

**DO**
1. Любую версионно-зависимую сигнатуру подтвердить `grep -rn '<symbol>' /opt/mc-src/`
   или `javap` по джарнику fabric-api. Без подтверждения — не писать.
2. Работать **от ошибок, а не от файлов**: первые ~30 ошибок → открыть только падающие строки
   (`Read` с offset/limit) → починить → пересобрать.
3. Держаться своего списка файлов. Нужна чужая правка — **написать в отчёте**, не править.
4. Диффы маленькие и механические.
5. Если `/opt/mc-src` противоречит бандлу или этому файлу — **прав `/opt/mc-src`**, сделать по нему
   и явно сказать об этом в отчёте. Инструкции содержат ошибки; это правило их и вылавливает.

**DON'T**
1. Не запускать `./gradlew` и ничего не качать (403). Gradle — только если роль разрешает.
2. Не коммитить и не пушить: это делает оркестратор.
3. Не изобретать имена методов. Не подтвердил после двух grep-ов → §10.
4. Не писать yarn-имена (`MinecraftClient`, `World`, `NbtCompound`, `Text`, `Vec3d`, `DrawContext`,
   `class_XXXX`), **никакого `ResourceLocation`**, **никакого `Identifier.of`**.
   Класс — `net.minecraft.resources.Identifier`, фабрика — `Identifier.fromNamespaceAndPath`.
   `GuiGraphics` в 26.2 **не существует** — есть `GuiGraphicsExtractor`.
5. Не доверять собственной памяти по сигнатурам в диапазоне 1.21.2 → 26.2: она устарела.
6. Не редактировать `26.1.2/` и не перегенерировать `/opt/mc-src`.
7. Вопросов пользователю не задавать.

**§10 — «не выходит → отключаем, но код сохраняем».** Сопротивляется после ~двух честных попыток —
не блокировать сборку и не удалять код:
1. отключить строку регистрации;
2. заглушить тело, оригинал оставить рядом:
   ```java
   // TODO(port-26.2): DISABLED — <одна строка: почему>
   /* … оригинальный код нетронутым … */
   ```
3. функциональная деградация вместо отключения, если она есть.

Каждый срез — строкой в отчёте для раздела «Disabled content». **Зелёная сборка важнее полноты фич.**

---

## Контракты (§5) — заморожены до старта агентов

| № | Контракт | Владелец файла |
|---|---|---|
| **K1** | **`BOGuiGraphics` остаётся фасадом с неизменной публичной формой.** Его зовут 22 файла. Переписывается **только сам файл** — против `GuiGraphicsExtractor`. Никто, кроме C, не трогает `GuiGraphicsExtractor` напрямую. | C |
| **K2** | **Точки входа.** `mod/BlockUI.java` → `ModInitializer` (общий, минимальный: `MOD_ID`, `NAMESPACE_TO_ATLAS_MAP`, `resLoc`, `isClient`, вызов `ContainerHook.init()`). Новый `mod/BlockUIClient.java` → `ClientModInitializer`, и **вся** клиентская регистрация только в нём. | A |
| **K3** | **Сеть сохраняет публичную форму.** `PlayMessageType`, `AbstractPlayMessage`, `AbstractServerPlayMessage`, `AbstractClientPlayMessage`, `AbstractUnsidedPlayMessage`, `IClientboundDistributor`, `IServerboundDistributor` — имена типов и публичных методов не меняются. Entrypoint дёргает ровно два: `register()` и `registerClient()`. **На эту форму завязаны Structurize и MineColonies.** | B |
| **K4** | **Конфиг — срез по §10.** `ModConfigSpec` не имеет аналога ни в Fabric, ни в ванили. `AbstractConfiguration` / `Configurations` / `ClientConfigHelper` деградируют до полей со старыми дефолтами, **сохраняя call-site `XXX.get()`**. | B |
| **K5** | **`ModelData` вырезается** (аналога в Fabric нет). Затрагивает `FakeLevel`, `FakeChunk` (B) и `ItemIconWithBlockState`, `BlockStateRenderingData` (D). Параметр удаляется из сигнатур — **это изменение публичного API**, обязательная строка в «Contract deviations». | B + D |
| **K6** | **`FMLEnvironment` → одна точка: `BlockUI.isClient()`** поверх `FabricLoader.getInstance().getEnvironmentType() == EnvType.CLIENT`. Объявляет A; зовут 7 файлов у B и C, каждый — только её. | объявляет A |
| **K7** | **Владение общими файлами.** `build.gradle`, `settings.gradle`, `gradle.properties`, `fabric.mod.json`, `blockui.accesswidener`, `BlockUIClient.java` — редактор **только A**. Этот файл — только оркестратор. | A |
| **K8** | **AccessTransformer → AccessWidener**, 14 записей, заголовок `accessWidener v1 official`. Целиком на A. От неё зависит `OutOfJarResourceLocation extends Identifier` у агента C. | A |

---

## Ownership — списки файлов, пересечений нет

Пути относительно `/home/user/BlockUI/26.2/`.

### Агент A — скелет, сборка, лоадер (11 файлов + сборка)
```
build.gradle, settings.gradle, gradle.properties
src/main/resources/fabric.mod.json                       (новый, из neoforge.mods.toml)
src/main/resources/blockui.accesswidener                 (новый, из accesstransformer.cfg)
src/main/resources/META-INF/neoforge.mods.toml           (удалить)
src/main/resources/META-INF/accesstransformer.cfg        (удалить)
src/main/java/com/ldtteam/blockui/mod/BlockUI.java
src/main/java/com/ldtteam/blockui/mod/BlockUIClient.java (новый)
src/main/java/com/ldtteam/blockui/mod/ClientEventSubscriber.java
src/main/java/com/ldtteam/blockui/mod/ClientLifecycleSubscriber.java
src/main/java/com/ldtteam/blockui/mod/Log.java
src/main/java/com/ldtteam/blockui/mod/BlockStateTestGui.java
src/main/java/com/ldtteam/blockui/mod/ScrollingListsGui.java
src/main/java/com/ldtteam/blockui/mod/container/ContainerHook.java
src/main/java/com/ldtteam/blockui/mod/item/**            (НЕТ — это D)
```
**Gradle: разрешён.** Коммиты — нет.

### Агент B — `com.ldtteam.common` (28 файлов, ~5 500 строк)
```
src/main/java/com/ldtteam/common/network/**     7 файлов
src/main/java/com/ldtteam/common/config/**      3 файла
src/main/java/com/ldtteam/common/language/**    3 файла
src/main/java/com/ldtteam/common/codec/**       3 файла
src/main/java/com/ldtteam/common/util/**        2 файла
src/main/java/com/ldtteam/common/fakelevel/**  10 файлов
src/test/java/com/ldtteam/blockui/common/codec/XmlOpsTest.java
```
**Gradle запрещён.** Самопроверка — «Быстрая проверка типов» ниже.

### Агент C — рендер-ядро и парсер XML (30 файлов, ~4 000 строк)
```
src/main/java/com/ldtteam/blockui/BOGuiGraphics.java     ← K1, ключевой файл порта
src/main/java/com/ldtteam/blockui/UiRenderMacros.java
src/main/java/com/ldtteam/blockui/Pane.java
src/main/java/com/ldtteam/blockui/BOScreen.java
src/main/java/com/ldtteam/blockui/PaneParams.java
src/main/java/com/ldtteam/blockui/Parsers.java
src/main/java/com/ldtteam/blockui/Loader.java
src/main/java/com/ldtteam/blockui/PaneBuilders.java
src/main/java/com/ldtteam/blockui/Color.java
src/main/java/com/ldtteam/blockui/Alignment.java
src/main/java/com/ldtteam/blockui/MouseEventCallback.java
src/main/java/com/ldtteam/blockui/package-info.java
src/main/java/com/ldtteam/blockui/util/**   (17 файлов: texture/4, color/5, records/2,
                                             resloc/1, cursor/1, + SafeError, SingleBlockGetter,
                                             SpacerTextComponent, ToggleableTextComponent)
src/test/java/com/ldtteam/blockui/util/color/IColourTest.java
```
**Gradle запрещён.**

### Агент D — виджеты, вьюхи, хуки (43 файла, ~6 500 строк)
```
src/main/java/com/ldtteam/blockui/controls/**   19 файлов
src/main/java/com/ldtteam/blockui/views/**      14 файлов
src/main/java/com/ldtteam/blockui/hooks/**       7 файлов
src/main/java/com/ldtteam/blockui/mod/item/**    2 файла (BlockStatePipRenderer,
                                                  BlockStateRenderingData)
src/main/java/com/ldtteam/blockui/support/DataProviders.java
```
**Gradle запрещён.** Пишет против фасада **K1**, а не против `GuiGraphicsExtractor`.

### Быстрая проверка типов без Gradle (для B, C, D)
```sh
cd /home/user/BlockUI/26.2
MCJAR=$(find ~/.gradle /root/.gradle . -path '*minecraftMaven*' -name 'minecraft-merged-*26.2*.jar' \
        ! -name '*sources*' 2>/dev/null | head -1)
CP=$(find ~/.gradle/caches/modules-2/files-2.1 /root/.gradle/caches/modules-2/files-2.1 \
        -name '*.jar' ! -name '*sources*' 2>/dev/null | tr '\n' ':')$MCJAR
javac -nowarn -proc:none -Xmaxerrs 3000 --release 25 -cp "$CP" -d /tmp/out-<роль> \
      $(find src/main/java -name '*.java') 2>&1 | head -120
```
Оговорки: access wideners не применены → «has private access» на расширенных членах — **ложное
срабатывание**. Вывод резать `head -120`. Миксинов в моде нет, исключать нечего.

---

## Checklist

- [ ] **Шаг 0 — оркестратор:** окружение, `genSources` → `/opt/mc-src`, копия исходников, `PORT-STATUS.md`
- [ ] **A** — `gradle build` доходит до `compileJava`, зависимости и AccessWidener приняты Loom'ом;
      остаточные ошибки только в файлах B/C/D; тестовое окно доступно по кейбинду
- [ ] **B** — `com.ldtteam.common` без единого `net.neoforged`, форма K3 цела
- [ ] **C** — рендер-ядро без `net.neoforged`, K1 соблюдён
- [ ] **D** — виджеты без `net.neoforged`, пишут только через `BOGuiGraphics`
- [ ] **Интеграция** — `compileJava` зелёный
- [ ] **Интеграция** — `build` зелёный
- [ ] **Приёмка** — `runServer` доходит до `Done (N.NNNs)!`, ноль `/ERROR]` вне allowlist
- [ ] **Ручная проверка пользователем** — клиент, тестовое окно открывается и работает

---

## Contract deviations

*(пусто — заполняется оркестратором из финальных отчётов агентов)*

---

## Disabled content

*(пусто — журнал §10, по строке на срез)*

---

## Verification

*(пусто — результаты `compileJava` / `build` / `runServer`)*

**Заранее известное ограничение приёмки.** BlockUI — библиотека GUI: на выделенном сервере она
не делает почти ничего. `runServer` проверяет здесь ровно одно — **безопасность загрузки классов**
(общий код не тянет клиентские типы в поля, супертипы, интерфейсы и аннотации). Дисплея в контейнере
нет, `runClient` не запустить, поэтому **весь GUI-слой останется в статусе «чисто компилируется,
никогда не исполнялся»** до ручной проверки пользователем. Это не выдавать за проверенное.
