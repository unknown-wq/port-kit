# Порт-бандл Minecraft 26.2 — всё в одном файле

Единый самодостаточный документ для порта **любого** мода на Fabric / Minecraft 26.2.
Склеен из `porting-26.2/` — там те же тексты отдельными файлами, если удобнее читать по частям.
Скрипты (`port-resolve-imports.py`, `fix-recipes.py`, `port-rename*.sh`) лежат только там.

Собран из пяти портов, каждый доведён до зелёного выделенного сервера:
`Fabric-LuckyTNTMod` (Yarn Fabric 1.21 → 26.2), `simple-planes` (NeoForge 1.21.1 → Fabric 26.2),
`LostCities` (Forge 1.20 → новый Fabric-мод), `desolation` (Fabric 1.21.6 → 26.1.2 → 26.2)
и `Domum-Ornamentum` (NeoForge 26.1 → Fabric 26.2) — последний единственный, проверенный
ещё и на живом клиенте.

## Что читать, если времени мало

1. **Часть I §1** — семь фактов, которые ломают наивный порт. До первой правки.
2. **Часть I §2** — сколько хопов нужно именно вашему исходнику.
3. **Часть I §3** — окружение. Ставится один раз, `./gradlew` не работает.
4. Дальше — по своей роли: **III** ядро/регистрация/датаген, **IV** логика/сущности/сеть,
   **V** клиент/модели/рендер.

## Оглавление

| Часть | Что внутри | Откуда |
|---|---|---|
| I | Универсальный план: маршрут, окружение, контракты, разбиение по агентам, деградация, приёмка, промпты | `PORT-ANY-MOD-26.2.md` |
| II | NeoForge → Fabric одним хопом: находки сборки и рантайма, уроки параллельной работы | `NEOFORGE-TO-FABRIC-26.2.md` |
| III | Ядро: entrypoint, регистрация, меню, рецепты, данные **+ датаген и item-модели** | `NOTES-A.md` |
| IV | Логика: сущности, NBT, апгрейды, сеть **+ мёртвые NeoForge-хуки** | `NOTES-B.md` |
| V | Клиент: рендереры, экраны, миксины **+ блочные модели и бейк 26.2** | `NOTES-C.md` |
| VI | Таблицы ренеймов по областям | `PORT-MOD-26.2.md` |
| VII | Готовые исправления повторяющихся ошибок компиляции | `PORT-CHEATSHEET.md` |
| VIII | Технический референс и пер-версионный hit-list ломок | `PORTING-GUIDE-26.2.md` |
| IX | Готовые промпты: оркестратор, агенты A/B/C/D, интегратор, свипер, веб-перепроверка | `prompts/` |
| X | Шаблоны: `PORT-STATUS.md`, `PORT-GAPS.md`, копилка находок, финальный отчёт агента | `templates/` |

## Три факта, которые теряются чаще всего

1. Цель — **`26.2`**, а не «1.26.2»: с 2026 года схема `year.drop.hotfix`.
2. С 26.1 игра **необфусцирована**: строки `mappings` в Gradle нет, Java **25**, Gradle 9.x.
   Forge/NeoForge уже на именах Mojang — миграции имён нет, ломаются сами API.
3. `ResourceLocation` в 26.2 **не существует**: класс — `net.minecraft.resources.Identifier`,
   фабрика — `Identifier.fromNamespaceAndPath(...)`. `Identifier.of(...)` тоже нет.

**Единственный источник истины — декомпилированные исходники игры в `/opt/mc-src` и уже
портированные 26.2-моды на диске. Если они противоречат этому документу — правы они.**


---

# Часть I. PORT-ANY-MOD-26.2 — универсальный план порта любого мода на Fabric / Minecraft 26.2


> **Что это.** Сводная инструкция для оркестратора и агентов, собранная из четырёх
> реально доведённых до зелёного сервера портов: `Fabric-LuckyTNTMod` (Yarn Fabric 1.21 → 26.2),
> `simple-planes` (NeoForge 1.21.1 → Fabric 26.2), `LostCities` (Forge 1.20 → новый Fabric 26.2 мод),
> `desolation` (Fabric 1.21.6 → 26.1.2 → 26.2).
> Здесь только то, что **переносится на любой мод**: факты о версии, маршрут, разбиение работы,
> дисциплина агентов, критерии приёмки и готовые промпты. Мод-специфические таблицы —
> в источниках из §16.
>
> **Этот файл — закон.** Оркестратор читает целиком. Агент читает **только** §1, §8, §9, §10
> и свою роль (совпадает со списком в промпте §15.1); из §3 агенту нужен лишь блок
> «Быстрая проверка типов», и только если его роль запрещает Gradle. §11 агент не читает —
> вместо него читается сам `PORT-STATUS.md`. §15 — материал оркестратора.
> Единственное, что выше этого файла по авторитету — **декомпилированные исходники игры**
> в `/opt/mc-src`. Если они противоречат документу — правы они, и агент обязан об этом сказать.

---

## 1. Факты, которые ломают наивный порт (прочитать до первой правки)

1. **Цель — `26.2`, а не «1.26.2».** С 2026 Minecraft Java использует схему `year.drop.hotfix`.
   Реальная последовательность: `… → 1.21.11` (последняя «1.x») `→ 26.1 (24.03.2026) → 26.1.1 →
   26.1.2 → 26.2 (16.06.2026)`. Если в задаче написано «1.26.2» — имеется в виду **26.2**.
   Писать `26.2` везде.
2. **Yarn и Intermediary мертвы после 1.21.11.** 26.1 — первый **необфусцированный** релиз:
   игра поставляется с именами Mojang. С 26.1 в Gradle **нет строки `mappings`** вообще
   (`officialMojangMappings()` тоже даст ошибку), нет `remapJar`, нет префикса `mod` у конфигураций.
3. **Java 21 → Java 25** начиная с 26.1. `options.release = 25`, `VERSION_25`,
   mixin `compatibilityLevel: JAVA_25`, Gradle 9.x.
4. **`ResourceLocation` в 26.2 НЕ СУЩЕСТВУЕТ.** Класс называется
   **`net.minecraft.resources.Identifier`** — Mojang принял это имя после расобфускации.
   Это **не** yarn-имя. Проверено: 0 совпадений `ResourceLocation` в `/opt/mc-src`, все три
   портированных мода импортируют `net.minecraft.resources.Identifier`.
   Фабрики: `Identifier.fromNamespaceAndPath(ns, path)`, `Identifier.parse(s)`,
   `Identifier.withDefaultNamespace(s)`. **`Identifier.of(...)` в 26.2 нет.**
   `ResourceKey` имя сохранил.
   *(Это самая дорогая ошибка в корпусе: две ранние редакции гайдов утверждали обратное,
   и оба раза её нашли агенты, которым разрешили спорить с документом.)*
5. **Запрещённые yarn-имена в 26.x:** `MinecraftClient`, `World`, `ServerWorld`, `Item.Settings`,
   `Block.Settings`, `NbtCompound`, `Text`, `Vec3d`, `DrawContext`, `class_XXXX`, `PlayerEntity`.
   Правильные: `Minecraft`, `Level`, `ServerLevel`, `Item.Properties`, `BlockBehaviour.Properties`,
   `CompoundTag`, `Component`, `Vec3`, **`GuiGraphicsExtractor`**, `Player`.
   ⚠ Здесь до порта Domum Ornamentum стояло `GuiGraphics` — **этого класса в 26.2 не существует**:
   в `/opt/mc-src/net/minecraft/client/gui/` лежит только `GuiGraphicsExtractor`, GUI работает по
   схеме extract-then-render. Правильную форму всегда содержал `NOTES-C.md` §5; §8 этого файла
   повторял ту же ошибку и тоже исправлен. Ровно тот случай, ради которого написано правило §9 DO-6.
6. **Тренировочные данные модели устарели по определению.** Всё в диапазоне 1.21.2 → 26.2
   переписывалось: рендер-стейты, Blaze3D/Vulkan, ValueInput/ValueOutput, ID-holder split.
   Сигнатуру, не подтверждённую в `/opt/mc-src` или в рабочем 26.2-моде на диске, **писать нельзя**.
7. **Зелёная компиляция дешёвая, зелёный запуск — дорогой.** В каждом из четырёх портов после
   зелёного `compileJava` оставались рантайм-баги, невидимые компилятору (§14).
   Приёмка — это загрузившийся выделенный сервер, а не `BUILD SUCCESSFUL`.

---

## 2. Определить маршрут порта (первое решение оркестратора)

Число хопов зависит **только от того, в каких именах написан исходник**, а не от расстояния версий.

| Исходник | Маршрут | Почему |
|---|---|---|
| **Fabric + Yarn, ≤1.21.11** | 4 стадии: `S1` до 1.21.11 (Yarn, Java 21) → `S2` Yarn→Mojang на 1.21.11 → `S3` 26.1 (Java 25, новый Loom) → `S4` 26.2. *(Стадии — S1–S4, чтобы не путать с агентами A–D из §6.)* | Миграция мэппингов переносит **имена, а не формы API**. Семантические ломки чинить, пока есть Yarn-параметры и Javadoc; мэппинги мигрировать только когда код уже компилится на 1.21.11 |
| **NeoForge / Forge (любой 1.20–1.21.x)** | **один хоп сразу в 26.2** | Forge/NeoForge уже на официальных мэппингах Mojang — миграции имён нет, компилятор полезен с первой минуты. Проверено на `simple-planes` (1.21.1 NeoForge) и `LostCities` (1.20 Forge) |
| **Fabric, уже Mojang-имена (26.1.x)** | один хоп 26.1 → 26.2 | Меняются только точечные API (§8, «26.2») |
| **Выделение части мода в новый мод** | новый Gradle-проект + перенос классов | Как `LostCities → lostbuildings`: скелет из работающего 26.2-мода, старые исходники — только источник для чтения, **никогда не редактировать** |

Дополнительные оси, которые надо посчитать отдельно от версии:
- **смена лоадера** (NeoForge/Forge → Fabric): entrypoints, регистрация, сеть, capabilities, события;
- **зависимости**: у GeckoLib/Biolith/Cloth/ModMenu свои мажорные скачки; у части модов
  (Trinkets, Terraform boat/wood, CCA) **сборки под 26.x нет** — решение «выпиливаем» принимает
  оркестратор до старта агентов и фиксирует письменно (§5).

Для Yarn-маршрута done-критерий каждой стадии — **зелёный build + смоук-тест**, прежде чем идти дальше.
Библиотеку портируем **до** мода, который на неё опирается.

---

## 3. Окружение: сделать один раз, оркестратором

Контейнер обычно пустой: Java 25 нет, Gradle свежего нет, **`./gradlew` не работает**
(egress-прокси отдаёт 403 на ассеты GitHub-релизов). **Никогда не запускать `./gradlew`
и не пытаться качать дистрибутив Gradle** — это гарантированно сожжёт попытку.

```sh
sudo apt-get update && sudo apt-get install -y openjdk-25-jdk-headless unrar   # update обязателен: устаревший индекс даёт 404; если вы root — без sudo
/home/user/Fabric-LuckyTNTMod/gradle-dist/install.sh    # многотомный RAR → /opt/gradle-9.6.1
export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64
/opt/gradle-9.6.1/bin/gradle --version                  # должен напечатать 9.6.1 ДО любой другой работы
```

Тот же дистрибутив продублирован в `simple-planes/gradle/install.sh`. Если ни один репозиторий
не склонирован — `add_repo unknown-wq/Fabric-LuckyTNTMod` (регистр важен) и взять `gradle-dist/` оттуда.
Maven-репозитории (Fabric, Terraformers, JitPack) через прокси **доступны** — зависимости резолвятся нормально.

Любая сборка:
```sh
cd <project> && JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64 \
  /opt/gradle-9.6.1/bin/gradle <task> --no-daemon 2>&1 | tee /tmp/errors.txt
```
**Одна инвокация Gradle на чекаут одновременно.** Две параллельные — порча кэша Loom.

### Декомпилированные исходники — единственный источник истины

Оркестратор запускает `genSources` **один раз** и распаковывает результат в **`/opt/mc-src/`**
(для 26.2 это ~7055 файлов), после чего фиксирует путь в `PORT-STATUS.md`.
Все остальные только `grep -rn <symbol> /opt/mc-src/` — **никто не перегенерирует**.

Две формы результата, обе встречались:
- сорс-джар в `<project>/.gradle/loom-cache/minecraftMaven/**/minecraft-merged-*-sources.jar` — просто распаковать;
- Loom 1.17 может не оставить джар вовсе, а записать хеш-адресуемый кэш
  `~/.gradle/caches/fabric-loom/decompile/v1.zip`: записи вида `LOOM` + `NAME <internal/class/name>` +
  `SRC <source>` с 4-байтными big-endian длинами. Разобрать в нормальное дерево пакетов скриптом,
  и уже его класть в `/opt/mc-src`.

### Пины версий 26.2 (проверены на всех четырёх модах)

| | значение |
|---|---|
| minecraft | `26.2` |
| fabric-loader | `0.19.3` |
| fabric-api | `0.154.2+26.2` |
| loom | `1.17.13`, плагин `id 'net.fabricmc.fabric-loom'` |
| gradle | `9.6.1` |
| java | `25` (`options.release = 25`, `VERSION_25`, `encoding = "UTF-8"`) |
| mappings | **строки нет** |

`fabric.mod.json`: `depends` → `fabricloader >=0.19.3`, `minecraft ">=26.2 <26.3"`, `java ">=25"`;
mixin-конфиг → `"compatibilityLevel": "JAVA_25"`. AccessWidener: заголовок `named` → **`official`**,
и **тело тоже перемаппить** (под `official` Loom валидирует пути по именам Mojang).
Mixin-тулинг тянуть не надо: `sponge-mixin` + MixinExtras приходят с лоадером.

### Быстрая проверка типов без Gradle (для агентов, которым Gradle запрещён)

```sh
# GRADLE_HOME кэша зависит от того, под кем гонялся Gradle: обычно ~/.gradle,
# но может быть /root/.gradle или <project>/.gradle. НЕ хардкодить — найти:
MCJAR=$(find ~/.gradle /root/.gradle . -path '*minecraftMaven*' -name 'minecraft-merged-*26.2*.jar' \
        ! -name '*sources*' 2>/dev/null | head -1)
CP=$(find ~/.gradle/caches/modules-2/files-2.1 /root/.gradle/caches/modules-2/files-2.1 \
        -name '*.jar' ! -name '*sources*' 2>/dev/null | tr '\n' ':')$MCJAR
javac -nowarn -proc:none -Xmaxerrs 3000 --release 25 -cp "$CP" -d /tmp/out \
      $(find src/main/java -name '*.java' ! -path '*/mixin/*') 2>&1 | head -120
```
Оговорки: mixin-аннотаций на этом classpath нет — миксины исключаются **по пути `*/mixin/*`**,
тем же паттерном, что и скрипт ренеймов §7 (исключение по имени `*Mixin.java` пропускает файлы
с другим неймингом и даёт ложные ошибки). Access wideners не применены — «has private access»
на расширенных членах здесь ложное срабатывание. Всё остальное — настоящие ошибки.
Вывод резать `head -120`: правило §9 «первые ~30 ошибок» действует и здесь, полный дамп
на тысячи строк — это выброшенные токены.

---

## 4. Разведка перед наймом агентов (делает оркестратор сам, это дёшево)

Без этих цифр нельзя ни поделить файлы, ни оценить риск:

1. `find src -name '*.java' | wc -l` и распределение по пакетам — что это за мод по объёму.
2. Что уже современно, а что нет: `grep -rl` по `DeferredRegister`, `@SubscribeEvent`,
   `IItemHandler`, `HudRenderCallback`, `getTexture(`, `readNbt`, `MinecraftClient`, `class_`.
3. **Список миксинов** — это всегда самая рискованная папка, и она никогда не мигрирует автоматически.
4. **Внешние зависимости**: есть ли у каждой сборка под 26.2. Нет — решение «удалить / заменить /
   написать свой @Invoker-миксин» принимается **сейчас**, письменно, с назначенным владельцем.
5. **Референсный мод на диске.** Всегда искать уже портированный 26.2-мод той же природы и
   объявить его образцом (worldgen → `desolation`; регистрация/сущности/взрывы/сеть →
   `Fabric-LuckyTNTMod/TntLib`; транспорт/меню/рецепты → `simple-planes/26.2`).
   Копировать паттерн дешевле, чем изобретать.
6. Прогнать `PORTING-GUIDE-26.2.md §3` (пер-версионный hit-list) как чек-лист grep-ов —
   получится персональный список зон риска этого мода.

---

## 5. Заморозить контракты ДО старта агентов

Самый крупный класс конфликтов у параллельных агентов — не API, а **контракты**
(«этот класс всё ещё отдаёт этот метод?»). Оркестратор фиксирует их письменно в `PORT-STATUS.md`,
и агент, которому нужен чужой тип, пишет **против контракта**, а не лезет в чужой файл.

Реальные примеры, которые сэкономили сотни правок:

- **C1 — форма полей реестра сохраняется.** Fabric регистрирует «жадно», но поля остаются
  `Supplier<T>` — и 229 вызовов `.get()` у трёх агентов не трогаются вообще:
  ```java
  public static <T extends Item> Supplier<T> register(String name, Function<Item.Properties, T> factory, Item.Properties props) {
      ResourceKey<Item> key = ResourceKey.create(Registries.ITEM, Identifier.fromNamespaceAndPath(MODID, name));
      T value = Registry.register(BuiltInRegistries.ITEM, key, factory.apply(props.setId(key)));
      return () -> value;
  }
  ```
- **C2 — entrypoints.** Кто создаёт `ModInitializer`, кто `ClientModInitializer`, и что вся
  клиентская регистрация (рендереры, слои моделей, экраны, кейбинды, HUD) живёт только во втором.
- **C3 — сеть.** Владелец `network/`, и ровно два имени метода (`register()` / `registerClient()`),
  которые дёргают общий и клиентский entrypoint.
- **C4 — capabilities отсутствуют.** NeoForge `ItemStackHandler`/`IItemHandler` → ванильный
  `SimpleContainer`; энергия/жидкости → обычные поля у владельца апгрейда, без Team Reborn Energy
  и Transfer API, если они не строго дешевле.
- **C5 — события.** `@EventBusSubscriber`/`@SubscribeEvent` удаляются, логика переезжает в
  Fabric-колбэки (`ServerTickEvents`, `UseEntityCallback`, `EntityTrackingEvents`, …), регистрируемые
  из соответствующего entrypoint.
- **C6 — владение общими файлами.** `build.gradle`, `fabric.mod.json`, `*.mixins.json`,
  клиентский entrypoint — у каждого **ровно один** редактор, названный поимённо.
  **`PORT-STATUS.md` тоже общий файл: пишет в него только оркестратор.** Агенты передают
  срезы §10 и отклонения от контрактов **в финальном отчёте**, оркестратор переносит в статус.
  Два параллельных агента, пишущих в один файл, — это затёртые записи, как и с любым другим файлом.

---

## 6. Разбиение работы между агентами

**Делить по файлам, а не по пакетам.** Именно это удержало трёх агентов от коллизий в
`simple-planes`: все `*Model.java` / `*Renderer.java` / `*Screen.java` ушли клиентскому агенту
**где бы они ни лежали**, в том числе глубоко внутри геймплейных пакетов.

Каноническое разбиение (масштабируется от 3 до 5 агентов):

| Агент | Зона | Когда |
|---|---|---|
| **A — ядро/скелет** | build-файлы, `fabric.mod.json`, entrypoint, `registry/**`, `block/**`, `item/**`, данные и ресурсы | **первым и в одиночку** — от него зависят все |
| **B — сущности/логика/сеть** | `entity/**`, геймплей, `network/**`, апгрейды/способности — но **без** `*Model/*Renderer/*Screen` | параллельно с C после A |
| **C — клиент** | `client/**`, все рендереры/модели/экраны/HUD, **и миксины** (или отдельный агент, если их много) | параллельно с B |
| **D — интегратор** | всё, что не компилится, полная сборка, датаген, единственный смоук-тест | после B и C |

Уточнения, оплаченные кровью:
- **Миксины — отдельная зона наивысшего риска.** `@Inject`/`@Redirect`/`@ModifyVariable` ссылаются
  на точные имена+дескрипторы, которые не мигрирует ни один инструмент. Если миксинов >5 —
  выделить агента только под них.
- **B и C не запускают Gradle вообще.** Компилирует A (пока один) и D. Иначе — порча кэша.
- **`/opt/mc-src` — зона оркестратора, у него единственное владение.** Агент проверяет только
  флаг готовности в `PORT-STATUS.md → Toolchain`. Если `/opt/mc-src` пуст или отсутствует —
  **остановиться и написать в отчёте**, не перегенерировать и не импровизировать (B и C
  физически не могут это починить: им запрещён Gradle).
- Агент, которому нужна правка в чужом файле, **пишет об этом в финальном отчёте**, а не правит.

---

## 7. Механические переименования — скриптом, не руками

Перед любой ручной правкой прогнать **один раз** скрипт массовых замен и закоммитить его результат
**отдельным коммитом**. Готовый образец: `Fabric-LuckyTNTMod/port-rename.sh` (+ `2..5` — добивки).
Он покрывает Yarn→Mojang; для Forge/NeoForge-источника нужен свой, короче (там правятся не имена
классов, а пути пакетов и точечные ренеймы).

Правила написания скрипта:
- источник строк — таблицы `PORT-MOD-26.2.md §4`, каждая строка → `perl -pi -e 's/…/…/g'`;
- применять по всем `src/**/*.java`, **исключая `*/mixin/*`**;
- три группы **в этом порядке**: (a) полные пути импортов, (b) голые имена классов с `\b`,
  (c) переименования методов (`.getWorld()`→`.level()`, `.setVelocity(`→`.setDeltaMovement(`, …);
- длинные имена заменять раньше их подстрок; пару `Registries`/`RegistryKeys` гонять через
  временный плейсхолдер, иначе они затрут друг друга;
- это **первый проход**, он не обязан быть идеальным — остаток ловит компилятор;
- `git diff --stat` для контроля вменяемости.

---

## 8. Карта изменений API: ловушки, которые встречаются в каждом порте

Полные таблицы — в `PORT-MOD-26.2.md §4` (Yarn→26.2, ~10 разделов) и `PORTING-GUIDE-26.2.md §3`
(по версиям). Здесь — то, что всплыло **во всех** портах:

**Регистрация**
- `Item.Properties` и `BlockBehaviour.Properties` требуют **`.setId(ResourceKey<…>)`**, иначе
  `NullPointerException: Item id not set` при регистрации.
- `EntityType.Builder.of(factory, MobCategory)`, `.sized/.clientTrackingRange/.updateInterval`,
  и `build(ResourceKey<EntityType<?>>)` — не `build(String)`.
- `EntityType#create(Level, EntitySpawnReason)` — второй аргумент обязателен.
- `BlockEntityType` — конструктор из 2 аргументов, без хвостового `null` дата-фиксера.
- yarn `RegistryKeys` → `net.minecraft.core.registries.Registries`;
  yarn `Registries` → `BuiltInRegistries`. Константы типов сущностей — в `EntityTypes` (мн. ч.).
- Кастомный реестр (замена NeoForge `RegistryBuilder`):
  `FabricRegistryBuilder.create(key).attribute(RegistryAttribute.SYNCED).buildAndRegister()`.

**Сущности и NBT**
- `defineSynchedData(SynchedEntityData.Builder)` вместо `initDataTracker()`;
  `SynchedEntityData.defineId(...)`, `b.define(ACCESSOR, default)`.
- NBT сущностей теперь кодек-ориентированный: `addAdditionalSaveData(ValueOutput)` /
  `readAdditionalSaveData(ValueInput)`; читать через `input.getIntOr/getShortOr/getStringOr`
  либо `input.read(name, CODEC)`.
- Ренеймы, задевающие все файлы: `getWorld()`→`level()`, `getVelocity`→`getDeltaMovement`,
  `damage(src,amt)`→`hurtServer(ServerLevel,src,amt)`, `getYaw/setYaw`→`getYRot/setYRot`,
  `spawnEntity`→`addFreshEntity`.

**Рендер (клиент)**
- Рендереры переписаны в модель **render-state**: `EntityRenderer<T, S extends EntityRenderState>`
  с `createRenderState()`, `extractRenderState(T, S, float)` и — в снапшоте 26.2 —
  **`submit(S, PoseStack, SubmitNodeCollector, CameraRenderState)`**, а не `render(...)`
  с `MultiBufferSource`. `getTexture(entity)` больше нет.
  **Форму копировать из портированного мода, а не сочинять.**
- Никакого сырого OpenGL/`GL11` — только Blaze3D (в 26.2 добавлен бэкенд Vulkan, обратный
  depth-buffer, OIT).
- `Minecraft.getInstance().setScreen(x)` → `minecraft.gui.setScreen(x)`.
- `DrawContext`/`GuiGraphics` → **`GuiGraphicsExtractor`** (класса `GuiGraphics` в 26.2 нет),
  `TextRenderer`→`Font`, виджеты → `client.gui.components.*`, лэйауты → `client.gui.layouts.*`.
  Экраны переписаны на extract-then-render: `render(...)` → `extractRenderState(...)`,
  `renderBg` → `extractBackground`, `renderLabels` → `extractLabels`. Таблица — `NOTES-C.md` §5.
- Слои рендера **не регистрируются кодом** — определяются по альфе спрайта / `"render_type"` в
  JSON модели. `BlockRenderLayerMap` удалён.
- Ванильный `@Nullable` — `org.jspecify.annotations.Nullable`; `javax.annotation.Nullable`
  на classpath 26.2 отсутствует.

**Прочее, что всплывает регулярно**
- `HudRenderCallback` удалён в 26.1 → `HudElementRegistry`.
- `ItemGroupEvents` → `CreativeModeTabEvents.modifyOutputEvent(ResourceKey<CreativeModeTab>)`.
- Сеть: `CustomPacketPayload` + `StreamCodec`, регистрация через
  `PayloadTypeRegistry.serverboundPlay()/clientboundPlay()`.
- 26.2 расщепил хранение id: `BlockIds`/`BlockItemIds`/`ItemIds`; в датагене
  `FabricTagsProvider.valueLookupBuilder(...)` → `builder(...)`, а `TagAppender.add` берёт
  `ResourceKey<T>` (оборачивать `.builtInRegistryHolder().key()`).
- Ингредиенты рецептов в JSON — просто строки-id (`"minecraft:iron_ingot"`), не `{"item": …}`.
- Дата-паки: `data/<ns>/<registry>/…` (пространство имён в пути).

**Ловушки миксинов (проверено дважды)**
- **Нельзя `@Inject` в HEAD абстрактного метода** — `Entity.readAdditionalSaveData` /
  `addAdditionalSaveData` абстрактны; целиться в конкретных вызывающих
  `load(ValueInput)` / `saveWithoutId(ValueOutput)`.
- Каждую цель `@Inject`/`@Redirect` перепроверять по `/opt/mc-src` вручную. Приватные статические
  `register` (например у `TrunkPlacerType`/`FoliagePlacerType`) вскрываются маленьким
  **@Invoker-миксином** — это штатное решение, а не хак.

---

## 9. Правила для агентов (не обсуждаются)

**DO**
1. Прежде чем писать — найти тот же паттерн в **портированном референсном моде** на диске.
2. Любую версионно-зависимую сигнатуру подтвердить `grep -rn '<symbol>' /opt/mc-src/`.
3. Работать **от ошибок, а не от файлов**: `compileJava` → первые ~30 ошибок →
   открыть **только** падающие строки (`Read` с offset/limit) → починить → пересобрать.
4. Держаться своего списка файлов; нужна чужая правка — написать в отчёте.
5. Держать диффы маленькими и механическими.
6. Если декомпилированный исходник противоречит этому документу — **следовать исходнику и
   явно сказать об этом**. Инструкции содержат ошибки; именно это правило их и вылавливает.

**DON'T**
1. Не запускать `./gradlew` и ничего не качать (403). Не запускать Gradle, если роль не разрешает.
2. Не коммитить и не пушить, если это делает оркестратор.
3. Не изобретать имена методов. Не подтвердил после двух grep-ов — §10.
4. Не писать yarn-имена, `class_XXXX`, `ResourceLocation`, `Identifier.of`.
5. Не доверять туториалам до 2026 года и собственной памяти по сигнатурам.
6. Не читать файлы «для контекста» и не перечитывать этот план — **грепать** его.
7. Не редактировать исходный (старый) модуль, из которого портируем, и не править скопированные
   1:1 JSON-данные.
8. Не задавать вопросов пользователю. Пользователя нет: решение принимается по этому плану и
   логируется в `PORT-STATUS.md`.

**Экономия токенов** (это не пожелание, а условие того, что порт вообще завершится):
окружение ставится один раз, `genSources` — один раз, механические ренеймы — скриптом.
`runServer` запускает **только роль D**, максимум один раз за цикл интеграции —
не «один на весь порт» (циклы §12 законно перезапускают его), а «никогда не роли A/B/C
и никогда дважды подряд без правок между запусками».

---

## 10. Правило «не выходит → отключаем, но код сохраняем»

Если конкретный кусок сопротивляется примерно **двум честным попыткам** — не блокировать сборку
и **не удалять код**. Спускаться по лестнице деградации и логировать:

1. Отключить **строку регистрации** — контента просто нет в игре, класс компилится.
2. Заглушить тело метода, оригинал оставить рядом:
   ```java
   // TODO(port-26.2): DISABLED — <одна строка: почему>
   /* … оригинальный код нетронутым … */
   ```
3. Функциональная деградация вместо отключения, если она есть: спавнеры не ставятся → дома
   генерируются без них; лут не привязывается → сундуки пустые; коррекция соединяемых блоков не
   портируется → лестницы/заборы ставятся без коррекции (косметика).
4. Целый объект данных не декодируется → выкинуть его из конфига, оставив рабочее большинство.

**Каждый срез — строкой в `PORT-STATUS.md` → «Disabled content» (файл, что, почему).**
Приоритет: серверный геймплей > клиентская визуалка > совместимость.
**Зелёная сборка важнее полноты фич.**

---

## 11. `PORT-STATUS.md` — живой документ порта

Создаёт **и ведёт только оркестратор** (см. C6): агенты читают его, но материал для него —
срезы, отклонения, результаты — передают в финальных отчётах, а вносит оркестратор
между фазами. Это убирает гонку на запись при параллельных B и C. Разделы:

- **Toolchain** — путь к Gradle, `JAVA_HOME`, готовность `/opt/mc-src` (y/n). Заголовок:
  «готово, не переустанавливать».
- **Rules** — краткая выжимка §9 + §10 (агент читает этот файл первым).
- **Контракты** — §5, поимённо.
- **Ownership** — списки файлов по агентам, без пересечений.
- **Checklist** — done-критерии каждого агента чекбоксами.
- **Contract deviations** — любая сигнатура, которую агент был вынужден изменить против контракта.
  Интегратор читает этот раздел первым.
- **Disabled content** — журнал §10, по строке на срез.
- **Verification** — результаты `compileJava` / `build` / `runDatagen` / `runServer`,
  и что осталось непроверенным (обычно клиент).

---

## 12. Оркестратор — автономный цикл

Оркестратор **никогда ничего не спрашивает у пользователя** и делает минимум работы сам:
окружение, разведка, контракты, компиляция, коммиты, найм агентов.

**Шаг 0 (сам):** окружение §3 → `genSources` → `/opt/mc-src` → разведка §4 → маршрут §2 →
контракты §5 → `PORT-STATUS.md` §11 → скрипт ренеймов §7 отдельным коммитом → commit + push.

**Фаза 1:** агент **A** один. Done: build-файлы на 26.2, скелет/регистрация компилятся.
Commit + push.

**Фаза 2:** агенты **B** и **C** параллельно (непересекающиеся файлы, **без Gradle**).
Оркестратор между их отчётами прогоняет `compileJava` сам и раздаёт ошибки.
Commit + push.

**Фаза 3:** агент **D** — интеграция: `compileJava` → первые ~30 ошибок → правка → повтор;
затем `build`, `runDatagen`, затем `runServer` (один запуск на цикл, только роль D).

**Цикл:** пока `build`/`runServer` красные → собрать список ошибок → нанять **свежего**
sweeper-агента (роль D) с этим списком и правом применять §10 → повторить.
Sweeper'у **не** выдавать полный набор чтения из §15.1 — только: список ошибок,
§10, правило «сигнатуры подтверждать grep-ом по `/opt/mc-src`» и путь к референсному моду.
Полная карта API §8 свежему sweeper'у не нужна — его ошибки уже конкретны.

Два жёстких ограничения:
1. **Каждый цикл обязан либо уменьшить число ошибок, либо применить срез по §10.**
   Всё, что пережило двух sweeper-ов, деградируется по §10 принудительно.
2. **Максимум 4 sweeper-цикла на порт.** Если после четвёртого сервер всё ещё красный —
   оркестратор останавливается и фиксирует в `PORT-STATUS.md → Verification` состояние
   «не доведено» с полным списком остаточных ошибок. Бесконечный найм свежих агентов —
   главный сценарий полного сжигания бюджета токенов.

**ERROR-строки не из мода:** если `/ERROR]` в логе гарантированно порождён сторонней
библиотекой или ванилью и не лечится срезом по §10 (в своём коде нечего отключать) —
оркестратор заносит эту строку в allowlist в `PORT-STATUS.md → Verification` с обоснованием,
и она перестаёт считаться против критерия приёмки §13. Иначе критерий «ноль ERROR»
невыполним и цикл не завершится никогда.

**После зелёного:** финальный коммит и пуш; `PORT-STATUS.md` со всеми чекбоксами и всеми срезами.

Git-дисциплина: работать на выделенной ветке, `git push -u origin <branch>`, при сетевой ошибке
до 4 ретраев с бэкоффом 2/4/8/16 с. PR не открывать: пользователя в цикле нет (§9 DON'T 8),
попросить некому — итог порта всегда просто запушенная ветка.

---

## 13. Приёмка

```sh
cd <project>
export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64
G=/opt/gradle-9.6.1/bin/gradle
$G compileJava --no-daemon        # 1
$G build       --no-daemon        # 2 — тут применяются миксины и обрабатываются ресурсы
$G runDatagen  --no-daemon        # 3 — если у мода есть датаген
mkdir -p run && echo "eula=true" > run/eula.txt
$G runServer   --no-daemon        # 4 — смоук-тест; запускает только роль D, один раз за цикл
```

**DONE =** сервер доходит до `Done (N.NNNs)! For help, type "help"` и в логе **ноль строк `/ERROR]`**,
не считая строк из allowlist в `PORT-STATUS.md → Verification` (сторонние/ванильные ERROR,
не лечащиеся через §10 — см. §12).
Если мод генерирует мир — генерация спавн-чанков уже прогоняет worldgen; при пробрасываемом stdin
полезно дослать проверочную команду (например `locate biome <ns>:<biome>`) и записать ответ.

Чего эта приёмка **не** покрывает: клиент. В контейнере нет дисплея — рендереры, модели, экраны и
HUD никогда не исполнялись, для них установлена только чистая компиляция. Это надо честно написать
в `PORT-STATUS.md`, а не выдавать за проверенное.

Полезно при отладке: `Failed to initialize server` + `bind(..) failed with error(-98)` — это
предыдущий `runServer` держит порт 25565, убить его (`pkill -f "[d]evlaunch"`; `pgrep` только
печатает PID и ничего не убивает), а не «чинить мод».
`No key layers in MapLike[{}]` — `level-type=minecraft:flat` без generator settings в
`server.properties`, тоже не мод.

---

## 14. Рантайм-грабли, которые компилятор не видит

Каждая стоила отдельного цикла отладки:

1. **Результат рецепта должен быть `ItemStackTemplate`, а не `ItemStack`.** `ItemStack.CODEC`
   валидируется через `Item.CODEC_WITH_BOUND_COMPONENTS`, а на момент загрузки дата-пака у
   модовых предметов компоненты ещё не привязаны:
   `DataResult.Error['Item <ns>:<item> does not have components yet']`.
   Ванильный `ShapedRecipe` в 26.x хранит именно `ItemStackTemplate`. Свои сериализаторы рецептов —
   так же (`ItemStackTemplate.CODEC` / `.STREAM_CODEC`, `template.create()` где нужен стек).
   **Провал молчаливый:** рецепты просто не существуют, ошибок в консоли нет.
2. **`#minecraft:non_flammable_wood` — только item-тег.** Блочный тег, ссылающийся на него,
   валится целиком с `missing following references`. Инлайнить id блоков.
3. **Порядок инициализации при eager-резолве.** `SurfaceRules.isBiome` в 26.2 резолвит ключи
   биомов **немедленно** — регистрация в `onInitialize()` падает `Missing element …`, потому что
   динамических биомов мода ещё нет. Лечение: строить условие от **тега биомов**
   (`new SurfaceRules.BiomeConditionSource(biomes.getOrThrow(TAG))`) — `HolderSet.Named` ленив и
   связывается во время генерации. Обобщение: **всё, что резолвит реестр, должно регистрироваться
   там, где реестр уже существует** (`ServerLifecycleEvents.SERVER_STARTING` для доступа к
   `ResourceManager`; более ранние колбэки срабатывают слишком рано — проверено).
4. **Безопасность классов клиент/сервер.** Выделенный сервер ловит случайную ссылку на клиентский
   класс из общего кода — это и есть половина ценности смоук-теста.
5. **Датаген может создать дыру в ассетах.** В 26.2 таблички стали блочными моделями: датаген
   выпускает модели, ссылающиеся на текстуры `textures/block/…`, которых у мода нет (у него старые
   entity-атласы). Нарезать (Mojang Slicer) или записать в «Известные пробелы».

---

## 15. Готовые промпты

### 15.1. Промпт агенту (шаблон оркестратора)

```
Ты портируешь <МОД> на Fabric / Minecraft 26.2. Твоя роль: <A ядро | B логика | C клиент | D интегратор>.

Читай в этом порядке и ничего сверх:
1. <АБСОЛЮТНЫЙ_ПУТЬ>/PORT-ANY-MOD-26.2.md — §1 (факты), §8 (карта API), §9 (правила),
   §10 (правило отключения). Из §3 — только блок «Быстрая проверка типов», если тебе
   запрещён Gradle. Не перечитывай файл — грепай по этому пути.
2. <АБСОЛЮТНЫЙ_ПУТЬ>/PORT-STATUS.md — контракты, твой список файлов, уже сделанные срезы.
   Читать можно, ПИСАТЬ НЕЛЬЗЯ — его ведёт оркестратор; всё для него передаёшь в отчёте.

Твои файлы (редактировать ТОЛЬКО их):
<точный список>

Твой референс, в порядке приоритета:
1. <портированный 26.2-мод на диске> — там уже решена та же задача, копируй форму;
2. /opt/mc-src — декомпилированный 26.2, ТОЛЬКО grep, никогда не перегенерировать;
3. Fabric docs — для концепций, не для сигнатур.

Жёсткие правила:
- Gradle не запускать <или: Gradle можно, ты один в чекауте>. Не коммитить.
- Ни одной сигнатуры «по памяти»: подтверждай grep-ом по /opt/mc-src или строкой из референса.
- Никаких yarn-имён, никакого ResourceLocation, никакого Identifier.of.
  Класс — net.minecraft.resources.Identifier, фабрика — Identifier.fromNamespaceAndPath.
- Сопротивляется после двух честных попыток → §10 (отключить, оригинал сохранить, залогировать).
- Если /opt/mc-src противоречит инструкции — прав он; сделай по нему и скажи об этом в отчёте.
- Вопросов пользователю не задавать.

Done-критерий: <конкретно>.
Отчёт: что сделано; что подтверждено чем (пути/строки); что отключено и почему;
какие правки нужны в чужих файлах (сам не трогай).
```

### 15.2. Промпт «перепроверь по вебу» (если сеть доступна, а референса нет)

```
Ты портируешь Fabric-мод в диапазоне 1.21 → 26.2. Твои тренировочные данные для этого
диапазона УСТАРЕЛИ — не полагайся на память. Перед любой версионно-зависимой правкой:

Контекст, который надо держать:
- Версии теперь year.drop: после 1.21.11 идут 26.1 и 26.2. «1.26.2» не существует.
- Yarn/Intermediary мертвы после 1.21.11; 26.1+ необфусцирован, имена Mojang.
- Java 25 с 26.1.

Порядок проверки:
1. Найти пост/док Fabric под целевую версию (site:fabricmc.net, site:docs.fabricmc.net).
2. Сверить точную сигнатуру класса/метода на mcsrc.dev или в minecraft.wiki/w/Java_Edition_26.2.
3. Установить, что произошло с символом: переименован / переехал / сменил сигнатуру / удалён.
4. Только после этого писать код и указать URL, по которому проверил. Не нашёл живого
   источника — так и скажи и ОСТАНОВИСЬ, не угадывай.
```

---

## 16. Где лежат детали

| Файл | Что там |
|---|---|
| `PORTING-GUIDE-26.2.md` | Технический референс: почему наивный порт ломается, стадийный маршрут, пер-версионный hit-list ломок 1.21.2→26.2, матрица тулчейна, ссылки на источники |
| `PORT-MOD-26.2.md` | Проверенная таблица ренеймов Yarn→26.2 (core/world/blocks/entities/items/render/network), «сюрпризы», экономика токенов, план оркестратора |
| `PORT-CHEATSHEET.md` | Готовые исправления повторяющихся ошибок компиляции, переживших массовые ренеймы |
| `simple-planes/porting-26.2/NEOFORGE-TO-FABRIC-26.2.md` | Специфика NeoForge→Fabric: почему тут один хоп, находки сборки и рантайма, уроки параллельной работы агентов |
| `simple-planes/porting-26.2/NOTES-A/B/C.md` | Пофайловые рецепты, проверенные по `/opt/mc-src`: A — регистрация/меню/рецепты/данные, B — сущности/NBT/сеть, C — клиент/рендер/миксины |
| `LostCities/PORT-PLAN-26.2.md` | Образец плана «выделить часть мода в новый Fabric-мод»: замороженные контракты, роли A–D, автономный цикл |
| `desolation/MIGRATION.md` | Образец Yarn→Mojang миграции с выпиливанием мёртвых зависимостей + дельта 26.1.2 → 26.2 |
| `Fabric-LuckyTNTMod/port-rename*.sh` | Рабочие скрипты массовых ренеймов |
| `Fabric-LuckyTNTMod/gradle-dist/`, `simple-planes/gradle/` | Вендоренный Gradle 9.6.1 (`install.sh`) |
| `*/PORT-STATUS.md` | Четыре заполненных примера живого статуса порта |


---

# Часть II. NeoForge 1.21.1 → Fabric 26.2 — index and build/runtime findings


Entry point for the Simple Planes port. The detailed, per-area recipe sheets are:

| File | Area |
|---|---|
| `NOTES-A.md` | Entrypoint, registration, containers/menus, recipes, reload listeners, data JSON |
| `NOTES-B.md` | Entities, synched data, `ValueInput`/`ValueOutput`, upgrades, networking |
| `NOTES-C.md` | Client init, renderers + render states, entity models, screens, sounds, mixins |

Everything in those three files was verified against the decompiled 26.2 sources or a working
Fabric 26.2 mod. This file adds what only shows up once you actually build and boot — the
compiler and the dedicated server catch things no amount of source reading does.

## The four facts that shape this kind of port

1. **NeoForge already uses Mojang mappings**, so a NeoForge→Fabric port needs **no mappings
   migration** — unlike a Yarn-based Fabric port, where 26.1 forces one. The staged
   1.21.x → 26.1 → 26.2 path in `PORTING-GUIDE-26.2.md` exists to give a Yarn codebase a
   compiler at each hop; here a single hop straight to 26.2 works, because the compiler is
   usable from the first minute.
2. **`ResourceLocation` does not exist in 26.2 — the class is `net.minecraft.resources.Identifier`.**
   Mojang adopted the name post-unobfuscation. Do not "fix" `Identifier` back to `ResourceLocation`
   because a guide (including our own) calls it a Yarn name. Details in `NOTES-A.md` §0.
3. **The decompiled game is the only ground truth.** `genSources` + grep answered every
   signature question in this port. Training-data memory of 1.21.x APIs is wrong often enough
   to be worthless here.
4. **Compile-green is cheap; boot-green is where the real bugs are.** The port reached a green
   `compileJava` after one round of trivial fixes, then still had five distinct runtime faults
   that no compiler could see (below).

## Build-time findings (the compiler's list, after three agents each self-checked with javac)

56 errors survived the agents' own `javac` checks, all in one agent's files, all mechanical:

| Error | Fix | Ground truth |
|---|---|---|
| `isClientSide has private access in Level` | `level.isClientSide` → `level.isClientSide()` | `Level.java:129` field is private, `:165` accessor |
| `cannot find symbol: Items.WHITE_BANNER` (×16) | `Items.BANNER.pick(DyeColor.WHITE)` — per-colour banner constants are gone, `Items.BANNER` is a `ColorCollection<Item>` | `Items.java:1569` |
| `cannot find symbol: ClickType` | `ClickType` → `ContainerInput` (same constants: PICKUP, QUICK_MOVE, SWAP, CLONE, THROW, QUICK_CRAFT, PICKUP_ALL) | `ContainerInput.java`, `AbstractContainerMenu.java:318` |
| `no suitable method found for startRiding(X, boolean)` | `startRiding(entity, force, sendEventAndTriggers)` | `Entity.java:2418` |

## Runtime findings (the dedicated server's list — nothing here is visible at compile time)

**1. Recipe results must be `ItemStackTemplate`, not `ItemStack`.**
`ItemStack.CODEC` validates through `Item.CODEC_WITH_BOUND_COMPONENTS`, and during datapack load a
mod item's components are not bound yet, so every recipe whose result is your own item fails with:

```
Couldn't parse data file 'simpleplanes:plane' from 'simpleplanes:recipe/plane.json':
DataResult.Error['Item simpleplanes:plane does not have components yet']
```

Vanilla's own recipes stopped using `ItemStack` for results in 26.x — `ShapedRecipe` holds an
`ItemStackTemplate` (`ShapedRecipe.java:24,41`). Custom recipe serializers must do the same:
`ItemStackTemplate.CODEC` / `ItemStackTemplate.STREAM_CODEC`, and `template.create()` where an
`ItemStack` is needed. Note the failure is **silent at compile time and non-fatal at runtime** —
the recipes just quietly do not exist.

**2. `#minecraft:non_flammable_wood` is an item tag only.** A *block* tag referencing it fails the
whole tag with `missing following references`. `ItemTags.NON_FLAMMABLE_WOOD` exists
(`ItemTags.java:127`); `BlockTags` has no counterpart. Inline the block ids instead.

**3. Mixin tooling resolves without extra dependencies.** `sponge-mixin 0.17.3+mixin.0.8.7` comes
with the loader and initialises MixinExtras 0.5.4 automatically — no `include`/`implementation`
line needed, and `compatibilityLevel: JAVA_25` is accepted.

**4. Loom applies fabric-api's transitive access wideners.** Client code calling package-private
`MenuScreens.register(...)` compiled and validated with no entry of our own.

**5. Two failures that look like mod bugs but are not.** `No key layers in MapLike[{}]` is
`level-type=minecraft:flat` in `server.properties` without generator settings — a vanilla parse of
the flat-world config, nothing to do with the mod. `Failed to initialize server` with
`bind(..) failed with error(-98)` is a previous `runServer` still holding port 25565; kill it
(`pgrep -f "[d]evlaunch"`) rather than debugging the mod.

## Environment recipe (this container, reproducible)

```sh
sudo apt-get update && sudo apt-get install -y openjdk-25-jdk-headless unrar   # update first: a stale index 404s
./gradle/install.sh                                                            # vendored Gradle 9.6.1 → /opt/gradle-9.6.1
cd 26.2 && JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64 /opt/gradle-9.6.1/bin/gradle genSources --no-daemon
```

`genSources` does **not** leave a sources jar: Loom 1.17 writes a hash-addressed cache at
`~/.gradle/caches/fabric-loom/decompile/v1.zip`, where each entry is
`LOOM` + `NAME <internal/class/name>` + `SRC <source>` records with 4-byte big-endian lengths.
Unpack it into a real package tree before grepping (7055 files for 26.2) — that tree is what
every "verify the signature" instruction in these notes depends on.

## Parallel-agent lessons

- Splitting by **file**, not by package, is what kept three agents from colliding: all
  `*Model.java`/`*Renderer.java`/`*Screen.java` went to the client agent wherever they lived,
  including deep inside the gameplay packages.
- Agreeing the shared shapes **before** the agents start (here: registry fields stay
  `Supplier<T>`, so 229 `.get()` call sites never needed touching) removes the largest class of
  cross-agent conflict.
- Every remaining conflict was a *contract* question (does this class still expose that method),
  not an API question — and each was resolved in one message.
- The instructions given to agents will contain mistakes. Telling them "the decompiled source
  outranks this document, and say so when it does" is what surfaced the `Identifier` error
  instead of burying it.


---

# Часть III. NOTES-A — NeoForge 1.21.1 → Fabric 26.2: core / registration / containers / recipes / data


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


---

# Часть IV. NOTES-B — NeoForge 1.21.1 → Fabric 26.2: entities, upgrades, networking


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


---

# Часть V. NOTES-C — NeoForge 1.21.1 → Fabric 26.2, **client area** (renderers, models, screens, HUD, sounds, mixins)


Every entry below was checked against the decompiled 26.2 tree at `/opt/mc-src/` or against a
working ported mod on disk. Paths are given so you can re-read the source instead of trusting me.

Reference mods used: `/home/user/Fabric-LuckyTNTMod/` (26.2 renderers + HUD),
`/home/user/desolation/src/main/java/raltsmc/desolation/init/client/DesolationClient.java`
(26.2 `ClientModInitializer`).

---

## 0. The rename that touches every client file

| 1.21.1 | 26.2 | source |
|---|---|---|
| `net.minecraft.resources.ResourceLocation` | **`net.minecraft.resources.Identifier`** | `/opt/mc-src/net/minecraft/resources/Identifier.java` (there is **no** `ResourceLocation.java`) |

The factory methods survived: `Identifier.fromNamespaceAndPath(ns, path)`, `Identifier.parse`,
`Identifier.withDefaultNamespace`, `withPath(String|UnaryOperator)`, `withPrefix`, `withSuffix`,
`getNamespace()`, `getPath()`. So it is a pure type rename. `Identifier.STREAM_CODEC` exists.

This is **not** a yarn name — 26.x Mojang official mappings really call it `Identifier`.

---

## 1. Removed client classes and their replacements (the dead ends)

Everything in this table was searched for with `find /opt/mc-src -name 'X.java'` and does not exist.

| Gone in 26.2 | Use instead | Notes |
|---|---|---|
| `net.minecraft.client.renderer.MultiBufferSource` | `SubmitNodeCollector` (`/opt/mc-src/net/minecraft/client/renderer/SubmitNodeCollector.java`) | world rendering is submit-to-queue |
| `net.minecraft.client.gui.GuiGraphics` | `net.minecraft.client.gui.GuiGraphicsExtractor` | GUI is extract-then-render |
| `net.minecraft.client.renderer.RenderType` | `net.minecraft.client.renderer.rendertype.RenderType` + `…rendertype.RenderTypes` | package move + factory split |
| `RenderType.armorCutoutNoCull(rl)` | `RenderTypes.armorCutoutNoCull(Identifier)` | `RenderTypes.java:402` |
| `RenderType.itemEntityTranslucentCull(rl)` | `RenderTypes.entityTranslucentCullItemTarget(Identifier)` | `RenderTypes.java:454` |
| `net.minecraft.client.renderer.entity.ItemRenderer` (whole class) | — | `ItemRenderer.getArmorFoilBuffer(...)` has **no** replacement; enchant-glint on entity models is gone. Foil is now `ItemStackRenderState.FoilType`, item-only. |
| `net.minecraft.client.resources.model.ModelResourceLocation` | — | baked-model lookup by `blockid#inventory` is gone |
| `Tesselator`, `BufferUploader` | — | no immediate mode; `BufferBuilder`/`MeshData` still exist in `com.mojang.blaze3d.vertex` but there is no uploader |
| `RenderSystem.setShaderTexture/setShaderColor/runAsFancy` | — | `RenderSystem` still exists (`/opt/mc-src/com/mojang/blaze3d/systems/RenderSystem.java`) but not those |
| `Minecraft.getOverlay()` | — | not present in `Minecraft.java` |
| `Minecraft.screen` | `Minecraft.getInstance().gui.screen()` | `Gui.java:218` |
| `Minecraft.setScreen(...)` | `Minecraft.getInstance().gui.setScreen(...)` | `Gui.java:222` |
| `Gui.setNowPlaying(...)` | `Minecraft.getInstance().gui.hud.setNowPlaying(...)` | `Gui.java:72 (public final Hud hud)`, `Hud.java:1201` |
| `Gui.rightHeight` / `leftHeight` | — | the HUD stacking cursor is gone; place your own rows at fixed offsets |
| `EntityRenderDispatcher.setRenderShadow / overrideCameraOrientation` | `GuiGraphicsExtractor#entity(...)` | see §6 |
| `net.minecraft.client.model.ShulkerModel` | `net.minecraft.client.model.monster.shulker.ShulkerModel` | and it is now `EntityModel<ShulkerRenderState>` |
| `JukeboxSong.fromStack(RegistryAccess, ItemStack)` | `JukeboxSong.fromStack(ItemStack)` | `/opt/mc-src/net/minecraft/world/item/JukeboxSong.java:52` |
| `Registry.get(Identifier)` returning `T` | `getValue(Identifier)` → `@Nullable T`; `get(Identifier)` → `Optional<Holder.Reference<T>>` | `/opt/mc-src/net/minecraft/core/Registry.java:65,67,131,133` |

### NeoForge-only client APIs with **no** Fabric equivalent (cut them)

| NeoForge | Fabric 26.2 |
|---|---|
| `RenderLivingEvent.Pre/Post` | none — needs a bespoke `LivingEntityRenderer` mixin |
| `ViewportEvent.ComputeCameraAngles` | none — needs a `GameRenderer`/`Camera` mixin |
| `CalculateDetachedCameraDistanceEvent` | none |
| `RegisterColorHandlersEvent.Item` | **removed from vanilla too** (1.21.4). Item tints are item-model-JSON driven |
| `TextureAtlasStitchedEvent` | none needed if you dropped the colour cache |
| `IClientFluidTypeExtensions`, `FluidStack` | none in this port (contract C4 deleted the fluid capability) |
| `ModelData` / `BlockRenderDispatcher#renderSingleBlock(..., ModelData, ...)` | block models go through `BlockModelResolver` / `submitBlockModel(...)`, which needs level context an entity render state does not carry — practical answer: cut |
| `RegisterMenuScreensEvent` | `MenuScreens.register` (§5) |
| `RegisterKeyMappingsEvent` | `KeyMappingHelper.registerKeyMapping` (§4) |
| `RegisterGuiLayersEvent` | `HudElementRegistry` (§4) |
| `EntityRenderersEvent.RegisterRenderers / RegisterLayerDefinitions / AddLayers` | `EntityRendererRegistry` / `ModelLayerRegistry` (§4) |
| `PacketDistributor.sendToServer(payload)` | `ClientPlayNetworking.send(payload)` |

---

## 2. `EntityRenderer` — the exact 26.2 contract

`/opt/mc-src/net/minecraft/client/renderer/entity/EntityRenderer.java`

```java
public abstract class EntityRenderer<T extends Entity, S extends EntityRenderState> {
    protected EntityRenderer(EntityRendererProvider.Context context);

    public abstract S createRenderState();

    public void extractRenderState(T entity, S state, float partialTicks);   // copy entity -> state

    public void submit(S state, PoseStack poseStack,
                       SubmitNodeCollector submitNodeCollector,
                       CameraRenderState camera);                            // NO entity access

    protected float getShadowRadius(S state);
    public Vec3 getRenderOffset(S state);
}
```

* `getTextureLocation(T)` / `getTexture(...)` — **gone**. Textures are chosen at submit time.
* `render(entity, yaw, partialTick, PoseStack, MultiBufferSource, int)` — **gone**, replaced by `submit`.
* Always call `super.extractRenderState(...)` (fills `x/y/z`, `ageInTicks`, `lightCoords`, nametag, leash)
  and `super.submit(...)` at the end (leash + nametag).
* `CameraRenderState` lives in `net.minecraft.client.renderer.state.level.CameraRenderState`.

### `EntityRenderState` fields worth knowing
`/opt/mc-src/net/minecraft/client/renderer/entity/state/EntityRenderState.java`

```
EntityType<?> entityType;  double x,y,z;  float ageInTicks;          // = tickCount + partialTick
float boundingBoxWidth, boundingBoxHeight, eyeHeight;
boolean isInvisible, isDiscrete, displayFireAnimation;
int lightCoords = 15728880;   int outlineColor = 0;
List<ShadowPiece> shadowPieces;  @Nullable Component nameTag;
```
Subclass it and add whatever the models need (quaternion, animation angles, texture `Identifier`,
list of installed upgrades…). Everything a model's `setupAnim` reads must live on the state.

### Submitting a model
`/opt/mc-src/net/minecraft/client/renderer/OrderedSubmitNodeCollector.java`

```java
<S> void submitModel(Model<? super S> model, S state, PoseStack poseStack,
                     RenderType renderType, int lightCoords, int overlayCoords,
                     int tintedColor, @Nullable TextureAtlasSprite sprite,
                     int outlineColor, @Nullable ModelFeatureRenderer.CrumblingOverlay crumbling);

// convenience overloads (the two you actually use):
<S> void submitModel(Model<? super S>, S, PoseStack, RenderType,  int light, int overlay, int outlineColor, @Nullable CrumblingOverlay);
<S> void submitModel(Model<? super S>, S, PoseStack, Identifier,  int light, int overlay, int outlineColor, @Nullable CrumblingOverlay);
```

Typical call: `collector.submitModel(model, state, poseStack, model.renderType(texture),
state.lightCoords, OverlayTexture.NO_OVERLAY, state.outlineColor, null);`

Also available: `submitModelPart`, `submitBlockModel`, `submitItem`, `submitCustomGeometry`,
`submitFlame`, `submitLeash`, `submitNameTag`, `submitShadow`.

Vanilla template to copy: `/opt/mc-src/net/minecraft/client/renderer/entity/AbstractBoatRenderer.java`
(state extraction + `submitModel` + `submitTypeAdditions`). Mod template:
`Fabric-LuckyTNTMod/tntmod/src/main/java/luckytnt/client/renderer/BombRenderer.java`
(custom nested render-state class, exactly the shape you want).

---

## 3. `EntityModel` / `Model` — what changed

`/opt/mc-src/net/minecraft/client/model/Model.java`, `.../EntityModel.java`

```java
public abstract class Model<S> implements FabricModel<S> {
    public Model(ModelPart root, Function<Identifier, RenderType> renderType);
    public final RenderType renderType(Identifier texture);
    public final void renderToBuffer(PoseStack, VertexConsumer, int light, int overlay, int color); // FINAL
    public final ModelPart root();
    public void setupAnim(S state) { this.resetPose(); }
}
public abstract class EntityModel<T extends EntityRenderState> extends Model<T> {
    protected EntityModel(ModelPart root);                                       // RenderTypes::entityCutout
    protected EntityModel(ModelPart root, Function<Identifier, RenderType> rt);
}
```

Mechanical conversion of a Blockbench-exported 1.21.1 model:

| before | after |
|---|---|
| `extends EntityModel<MyEntity>` | `extends EntityModel<MyRenderState>` |
| ctor body starts with `this.part = root.getChild("x")` | prepend **`super(root);`** |
| `@Override public void renderToBuffer(PoseStack, VertexConsumer, int, int, int)` calling `part.render(...)` | **delete it** — it is `final` now; `root()` renders all children |
| `setupAnim(E entity, float limbSwing, float limbSwingAmount, float ageInTicks, float netHeadYaw, float headPitch)` | `setupAnim(S state)` (call `super.setupAnim(state)` first if you set rotations — the base does `resetPose()`) |

**Check before deleting `renderToBuffer`:** the old override may have rendered only *some* of the
root's children. Compare the `partdefinition.addOrReplaceChild("…")` names against the parts the
override rendered; if they are the same set, rendering the root is equivalent.

Unchanged: `MeshDefinition`, `PartDefinition`, `CubeListBuilder`, `CubeDeformation`, `PartPose`,
`LayerDefinition.create(mesh, xTex, yTex)` — all still in `net.minecraft.client.model.geom.builders`.
`ModelPart.render(PoseStack, VertexConsumer, int light, int overlay[, int color])` still exists
(`ModelPart.java:103,107`).

`ModelLayerLocation` is now `record ModelLayerLocation(Identifier model, String layer)`
(`/opt/mc-src/net/minecraft/client/model/geom/ModelLayerLocation.java`).

`EntityModelSet.bakeLayer(ModelLayerLocation) -> ModelPart` unchanged; reach it from
`EntityRendererProvider.Context#getModelSet()` or `#bakeLayer(...)`, or
`Minecraft.getInstance().getEntityModels()` (`Minecraft.java:2821`) — but **not** during client init,
the set is only populated after the first resource load. Bake shared models inside a renderer
constructor: renderers are rebuilt on every resource reload, which is exactly when you need to re-bake.

---

## 4. Fabric client registration (all verified by `javap` on `fabric-api-0.154.2+26.2`)

```java
// entrypoint, declared in fabric.mod.json "entrypoints": { "client": [...] }
public class FooClient implements ClientModInitializer { public void onInitializeClient() { … } }
```

| what | call | package |
|---|---|---|
| entity renderer | `EntityRendererRegistry.register(EntityType<? extends E>, EntityRendererProvider<E>)` | `net.fabricmc.fabric.api.client.rendering.v1` |
| model layer | `ModelLayerRegistry.registerModelLayer(ModelLayerLocation, TexturedLayerDefinitionProvider)` where the provider is `LayerDefinition createLayerDefinition()` | `net.fabricmc.fabric.api.client.rendering.v1` |
| armor layers | `ModelLayerRegistry.registerArmorModelLayers(ArmorModelSet<ModelLayerLocation>, TexturedArmorModelSetProvider)` | same |
| menu screen | `MenuScreens.register(MenuType<? extends M>, MenuScreens.ScreenConstructor<M,U>)` — **vanilla**, see §5 | `net.minecraft.client.gui.screens` |
| key binding | `KeyMappingHelper.registerKeyMapping(KeyMapping)` | `net.fabricmc.fabric.api.client.keymapping.v1` |
| HUD layer | `HudElementRegistry.addLast(Identifier, HudElement)` (also `addFirst`, `attachElementBefore/After`, `removeElement`, `replaceElement`) | `net.fabricmc.fabric.api.client.rendering.v1.hud` |
| client tick | `ClientTickEvents.END_CLIENT_TICK.register(mc -> …)` (`EndTick#onEndTick(Minecraft)`) | `net.fabricmc.fabric.api.client.event.lifecycle.v1` |
| C2S packet | `ClientPlayNetworking.send(CustomPacketPayload)` | `net.fabricmc.fabric.api.client.networking.v1` |
| living-entity feature layers | `LivingEntityRenderLayerRegistrationCallback` | `net.fabricmc.fabric.api.client.rendering.v1` |

`HudElement` is a single method — note it is **extract**, not render:

```java
public interface HudElement { void extractRenderState(GuiGraphicsExtractor graphics, DeltaTracker deltaTracker); }
```

Vanilla element ids to anchor against: `VanillaHudElements.HOTBAR / HEALTH_BAR / MOUNT_HEALTH / CHAT / …`.

### KeyMapping
`/opt/mc-src/net/minecraft/client/KeyMapping.java:90-98,206-221`

```java
new KeyMapping(String name, int keysym, KeyMapping.Category category);
new KeyMapping(String name, InputConstants.Type type, int value, KeyMapping.Category category);
KeyMapping.Category.register(Identifier);   // string categories are gone
```
`isDown()` / `consumeClick()` unchanged.

---

## 5. Screens — `GuiGraphics` is gone, everything is *extraction*

`/opt/mc-src/net/minecraft/client/gui/screens/inventory/AbstractContainerScreen.java`

| 1.21.1 | 26.2 |
|---|---|
| `public void render(GuiGraphics, int mouseX, int mouseY, float partialTick)` | `public void extractRenderState(GuiGraphicsExtractor graphics, int mouseX, int mouseY, float a)` |
| `protected void renderBg(GuiGraphics, float partialTick, int x, int y)` | `public void extractBackground(GuiGraphicsExtractor graphics, int mouseX, int mouseY, float a)` (declared on `Screen`, `Screen.java:377`) |
| `protected void renderLabels(GuiGraphics, int, int)` | `protected void extractLabels(GuiGraphicsExtractor graphics, int xm, int ym)` |
| `renderTooltip(GuiGraphics, x, y)` | `graphics.setTooltipForNextFrame(font, List<? extends FormattedCharSequence>, x, y)` (and ~10 sibling overloads) — the base class already does slot tooltips |
| `imageWidth`/`imageHeight` assignable in ctor | **`protected final`** — pass them to `super(menu, inv, title, imageWidth, imageHeight)` |
| `getGuiLeft()` / `getGuiTop()` | **gone** — use the `protected leftPos` / `topPos`, or add your own accessors |

`GuiGraphicsExtractor` (`/opt/mc-src/net/minecraft/client/gui/GuiGraphicsExtractor.java`) essentials:

```java
int guiWidth(); int guiHeight();
Matrix3x2fStack pose();                       // 2-D now, not PoseStack
void enableScissor(int,int,int,int); void disableScissor();
void fill(int x0,int y0,int x1,int y1,int argb);
void text(Font, Component|String|FormattedCharSequence, int x, int y, int color[, boolean shadow]);
void blit(RenderPipeline, Identifier texture, int x, int y, float u, float v,
          int width, int height, int textureWidth, int textureHeight[, int color]);
void blitSprite(RenderPipeline, Identifier sprite, int x, int y, int w, int h);
void item(ItemStack, int x, int y); void itemDecorations(Font, ItemStack, int x, int y[, String count]);
void setTooltipForNextFrame(...);
```

`RenderPipelines.GUI_TEXTURED` (`/opt/mc-src/net/minecraft/client/renderer/RenderPipelines.java:769`)
is the pipeline for plain textured blits. There is no zero-pipeline `blit(Identifier, …)` overload
except the raw-UV one.

`ImageButton` / `WidgetSprites` are unchanged in shape but take `Identifier`
(`/opt/mc-src/net/minecraft/client/gui/components/ImageButton.java`, `WidgetSprites.java`); widgets
now override `extractContents(GuiGraphicsExtractor, int, int, float)`.

### `MenuScreens.register` accessibility — gotcha
`MenuScreens.register` and `MenuScreens.ScreenConstructor` are **private** in raw vanilla. The
Javadoc in `/opt/mc-src/net/minecraft/client/gui/screens/MenuScreens.java:60,113` literally says
*"Access widened by fabric-transitive-access-wideners-v1 to accessible"* — i.e. they are public only
because Fabric API's transitive access widener is applied. If a build fails with
`register(...) has private access in MenuScreens`, the transitive AW is not being applied; add to
your own `*.accesswidener` (namespace `official`):

```
accessible	method	net/minecraft/client/gui/screens/MenuScreens	register	(Lnet/minecraft/world/inventory/MenuType;Lnet/minecraft/client/gui/screens/MenuScreens$ScreenConstructor;)V
accessible	class	net/minecraft/client/gui/screens/MenuScreens$ScreenConstructor
```

`ScreenConstructor` shape is unchanged: `U create(T menu, Inventory inventory, Component title)`.

---

## 6. Rendering an entity inside a GUI

`InventoryScreen.renderEntityInInventory(...)` is gone. 26.2 uses a picture-in-picture render state
(`/opt/mc-src/net/minecraft/client/gui/screens/inventory/InventoryScreen.java:103-148`):

```java
EntityRenderDispatcher d = Minecraft.getInstance().getEntityRenderDispatcher();
EntityRenderer<? super E, ?> r = d.getRenderer(entity);      // EntityRenderDispatcher.java:94
EntityRenderState st = r.createRenderState(entity, 1.0F);    // EntityRenderer.java, final 2-arg form
st.shadowPieces.clear();
st.outlineColor = 0;
graphics.entity(st, size, new Vector3f(0, st.boundingBoxHeight / 2f, 0),
                rotationQuaternion, /*overrideCameraAngle*/ null, x0, y0, x1, y1);
```

`GuiGraphicsExtractor#entity(EntityRenderState, float scale, Vector3fc translation,
Quaternionfc rotation, @Nullable Quaternionfc overrideCameraAngle, int x0,int y0,int x1,int y1)`
— `GuiGraphicsExtractor.java:1006`.

---

## 7. Sounds — almost unchanged

`/opt/mc-src/net/minecraft/client/resources/sounds/AbstractTickableSoundInstance.java`

```java
protected AbstractTickableSoundInstance(SoundEvent event, SoundSource source, RandomSource random);
protected final void stop();   public boolean isStopped();
```
`AbstractSoundInstance` still exposes `protected double x,y,z; protected float volume; protected boolean looping;`
and `public float getPitch()`. `SoundInstance.createUnseededRandom()` still exists
(`SoundInstance.java:49`). Only the *now playing* toast moved: `mc.gui.hud.setNowPlaying(Component)`.

---

## 8. Mixins

* **Re-verify every `target=` descriptor against `/opt/mc-src`.** Concrete example from this port:
  the `Camera#setPosition(DDD)V` call used to sit in `Camera#setup`; in 26.2 it is inside the private
  `Camera#alignWithEntity(float partialTicks)` (`/opt/mc-src/net/minecraft/client/Camera.java:249-262`),
  and `Camera.partialTickTime` **no longer exists** (the partial tick is a method parameter now).
  `eyeHeight` / `eyeHeightOld` are still private fields (`Camera.java:62-63`) so `@Shadow` works.
* `Camera.getEntity()` → **`Camera.entity()`** (`Camera.java:407`). `isDetached()` still exists (`:419`).
* **MixinExtras availability is not guaranteed at compile time.** It ships nested inside
  `fabric-loader-0.19.3.jar` as `META-INF/jars/mixinextras-fabric-0.5.4.jar`, but no
  `org/spongepowered/asm/**` and no un-nested MixinExtras jar were present in the local Gradle cache.
  If you can express the patch without it, do — a plain
  `@Inject(method=…, at=@At(value="INVOKE", target=…, shift=At.Shift.AFTER, ordinal=0))` that
  re-applies the value is often enough to replace a `@WrapOperation`, and `@Inject` handlers already
  receive the target method's parameters (which is how you get `partialTicks`).
* Access wideners in 26.x use the `official` namespace header (`accessWidener v1 official`).
  `accessible method …` makes the method **public**, so you can call it from the mixin via
  `((Camera)(Object)this).setPosition(x, y, z)` without a `@Shadow`.

---

## 9. Client/server class-loading safety (what the dedicated-server boot actually catches)

* Everything client-only gets `@Environment(EnvType.CLIENT)` (`net.fabricmc.api.Environment` /
  `EnvType`). Vanilla does this on every client class — see the header of any file under
  `/opt/mc-src/net/minecraft/client/`.
* A *reference* to a client class from common code is only resolved when the enclosing bytecode
  actually executes, so the classic `if (level().isClientSide) { PlaneSound.tryToPlay(this); }` guard
  does keep the server from loading it. It is fragile but it works — do not "fix" it by hoisting the
  call out of the branch.
* Never put a client type in a **field type, superclass, interface, or annotation** of a
  common class — those are resolved at class-load time and will crash the server.
* Method *parameter/return* types of a common class are resolved lazily too, but only if the method
  is never called and never verified against; treat this as a smell, not a pattern. The safe fix is
  to move the method to a client-only class.
* Client-only registration all funnels through `ClientModInitializer#onInitializeClient`, which the
  dedicated server never invokes — that is the real firewall.

---

## 10. Misc verified odds and ends

| thing | 26.2 |
|---|---|
| `Registry#getKey(T)` | `@Nullable Identifier getKey(T)` (`/opt/mc-src/net/minecraft/core/Registry.java:58`) |
| `Font#split(FormattedText, int)` | unchanged, returns `List<FormattedCharSequence>` (`Font.java:148`) |
| `Lighting` | still `com.mojang.blaze3d.platform.Lighting` |
| `OverlayTexture.NO_OVERLAY` | unchanged |
| `com.mojang.math.Axis` | unchanged |
| `PoseStack` | unchanged, `com.mojang.blaze3d.vertex.PoseStack` |
| `@Nullable` | vanilla uses `org.jspecify.annotations.Nullable`; `javax.annotation.Nullable` is **not** on the 26.2 classpath |
| block texture from a block | there is no model-quad path any more; deriving `<ns>:textures/block/<path>.png` from `BuiltInRegistries.BLOCK.getKey(block)` is the cheap approximation |

---

## 11. Quick offline type-check trick (no gradle)

The orchestrator owns gradle, but you can type-check your own files without it:

```sh
CP=$(find /root/.gradle/caches/modules-2/files-2.1 -name '*.jar' ! -name '*sources*' | tr '\n' ':')\
/root/.gradle/caches/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged-deobf/26.2/minecraft-merged-deobf-26.2.jar
javac -nowarn -proc:none -Xmaxerrs 3000 --release 25 -cp "$CP" -d /tmp/out \
      $(find src/main/java -name '*.java' ! -name '*Mixin.java')
```

Caveats: mixin annotations are not on that classpath (exclude mixin files), and the raw deobf jar has
**no access wideners applied**, so `MenuScreens.register` reports "has private access" — that one is a
false positive under Loom. Everything else is real.


---

# Приложение: находки порта Domum Ornamentum (NeoForge 26.1 → Fabric 26.2)

Всё ниже добавлено по итогам порта Domum Ornamentum и проверено на нём: сборка, датаген
и выделенный сервер зелёные, клиент проверен вручную. Каждая запись подтверждена ссылкой
на `/opt/mc-src` или на строку рабочего 26.2-мода. Материал не дублирует то, что было
в ките выше, — это только новое.



Всё, что пришлось выяснить самому: `NOTES-C.md` подробно описывает рендереры **сущностей** и экраны,
но про **блочные модели, кастомные модель-лоадеры и запекание** там нет ни строки. Ниже — карта
замен, каждая с ссылкой на файл:строку в `/opt/mc-src` или на jar в `/root/.gradle/caches`.

Проверялось на: `minecraft 26.2`, `fabric-api 0.154.2+26.2`
(`fabric-model-loading-api-v1 8.0.15`, `fabric-renderer-api-v1 14.1.2`, `fabric-rendering-v1 25.3.1`,
`fabric-block-getter-api-v2 2.0.7`).

> **Важно про `/opt/mc-src`.** Это дерево — уже **пропатченный Fabric'ом** Minecraft: ванильные
> интерфейсы в нём наследуют Fabric-интерфейсы (`BlockStateModel extends FabricBlockStateModel`,
> `BlockGetter extends … FabricBlockGetter`). То есть FRAPI не «сбоку», а вшит в игру, и его методы
> видны прямо на ванильных типах. **Но** сырой `minecraft-merged-deobf-26.2.jar` из
> `~/.gradle/caches/fabric-loom/minecraftMaven/` этих инъекций не содержит — офлайн-`javac` по §11
> `NOTES-C` даёт на них ложное `cannot find symbol`. Список известных ложных срабатываний в §9.

---

## 0. Сводная таблица «что чем заменяется» (модели и рендер блоков)

| NeoForge 26.1 / старый Fabric | 26.2 | Подтверждение |
|---|---|---|
| `net.minecraft.client.resources.model.BakedModel` | **не существует.** Блочная модель — `net.minecraft.client.renderer.block.dispatch.BlockStateModel` | `/opt/mc-src/net/minecraft/client/renderer/block/dispatch/BlockStateModel.java` |
| `BakedModel#getQuads(state, dir, rand)` | `BlockStateModel#collectParts(RandomSource, List<BlockStateModelPart>)`, затем `BlockStateModelPart#getQuads(@Nullable Direction)` | `BlockStateModel.java:24`, `BlockStateModelPart.java:16` |
| `BakedModel#getParticleIcon()` | `BlockStateModel#particleMaterial()` → `Material.Baked` | `BlockStateModel.java:26` |
| `SimpleBakedModel.Builder` | **нет.** Ближайшее — `record SimpleModelWrapper(QuadCollection, boolean, Material.Baked)`, создаётся только на этапе бейка | `/opt/mc-src/net/minecraft/client/resources/model/SimpleModelWrapper.java:23` |
| `ChunkRenderTypeSet`, `BakedModel#getRenderTypes(...)` | **нет.** Слой — свойство **каждого квадра**: `BakedQuad.MaterialInfo#layer()` → `ChunkSectionLayer{SOLID,CUTOUT,TRANSLUCENT}` | `/opt/mc-src/net/minecraft/client/resources/model/geometry/BakedQuad.java:62`, `/opt/mc-src/net/minecraft/client/renderer/chunk/ChunkSectionLayer.java:12` |
| `ModelData` / `ModelProperty` (канал BE → модель) | `RenderDataBlockEntity#getRenderData()` + `BlockGetter#getBlockEntityRenderData(BlockPos)` (fabric-block-getter-api-v2). Либо вообще не нужен — см. §3 | `/opt/mc-src/net/minecraft/world/level/BlockGetter.java:25` |
| `IQuadTransformer` / `QuadTransformers` | FRAPI `QuadEmitter` (мутируешь квадр между `fromBakedQuad` и `emit`) или `QuadTransform` (`boolean transform(MutableQuadView)`) через `pushTransform`/`popTransform` | `fabric-renderer-api-v1`: `…v1/mesh/QuadEmitter`, `…/mesh/QuadTransform` |
| `IGeometryLoader` + `ModelEvent.RegisterGeometryLoaders` | `UnbakedModelDeserializer.register(Identifier, …)` — **но диспетчер читает ключ `"fabric:type"`, а не `"loader"`** (§2) | `net.fabricmc.fabric.impl.client.model.loading.UnbakedModelJsonDeserializer` (декомпиляция байткода) |
| `IUnbakedGeometry#bake(IGeometryBakingContext, …)` | `UnbakedGeometry#bake(TextureSlots, ModelBaker, ModelState, ModelDebugName) -> QuadCollection` — возвращает **квадры**, а не модель | `/opt/mc-src/net/minecraft/client/resources/model/geometry/UnbakedGeometry.java:15` |
| `UnbakedModel#bake(baker, spriteGetter, modelState)` | `UnbakedModel` — чисто **данные** JSON-файла: `geometry()`, `parent()`, `textureSlots()`, `transforms()`, `ambientOcclusion()`, `guiLight()`. Метода `bake` на нём нет | `/opt/mc-src/net/minecraft/client/resources/model/UnbakedModel.java` |
| `net.minecraft.client.color.block.BlockColor` | **удалён.** `BlockTintSource` + per-block `List<BlockTintSource>` | `/opt/mc-src/net/minecraft/client/color/block/BlockTintSource.java` |
| `net.minecraft.client.color.item.ItemColor`, `Minecraft#getItemColors()` | **удалены.** Тинт предмета — `ItemTintSource` из item-model JSON | `/opt/mc-src/net/minecraft/client/color/item/ItemTintSources.java` |
| `ItemBlockRenderTypes.setRenderLayer`, fabric `BlockRenderLayerMap` | **удалены.** Слой = альфа спрайта либо `"force_translucent"` в материале модели | `/opt/mc-src/net/minecraft/client/resources/model/sprite/Material.java` |
| `net.minecraft.client.renderer.item.ItemProperties` | **удалён.** Оверрайды моделей предметов — декларативные `SelectItemModel`/`RangeSelectItemModel`/`ConditionalItemModel` в `assets/<ns>/items/<item>.json` | `/opt/mc-src/net/minecraft/client/renderer/item/` |
| `RenderStateShard`, `RenderType.create(name, fmt, mode, size, …, CompositeState)` | **удалены.** `RenderType.create(String, RenderSetup)` поверх Blaze3D `RenderPipeline` | `/opt/mc-src/net/minecraft/client/renderer/rendertype/RenderType.java:41` |

---

## 1. `BakedModel` → `BlockStateModel`: точная форма

- **Было (NeoForge 26.1):** одна `BakedModel` на всё — блок и предмет: `getQuads(state, side, rand,
  ModelData, RenderType)`, `getRenderTypes(...)`, `getRenderPasses(...)`, `getOverrides()`.
- **Стало (26.2):** конвейеры блока и предмета разведены полностью.
  ```java
  // /opt/mc-src/net/minecraft/client/renderer/block/dispatch/BlockStateModel.java
  public interface BlockStateModel extends FabricBlockStateModel {
      void collectParts(RandomSource random, List<BlockStateModelPart> output);
      Material.Baked particleMaterial();
      @BakedQuad.MaterialFlags int materialFlags();
      default boolean hasMaterialFlag(int flag);

      interface Unbaked extends ResolvableModel { BlockStateModel bake(ModelBaker); … }
      interface UnbakedRoot extends ResolvableModel {
          BlockStateModel bake(BlockState, ModelBaker);
          Object visualEqualityGroup(BlockState);
      }
      class SimpleCachedUnbakedRoot implements UnbakedRoot { … }
  }

  // .../block/dispatch/BlockStateModelPart.java
  public interface BlockStateModelPart extends FabricBlockStateModelPart {
      List<BakedQuad> getQuads(@Nullable Direction direction);
      boolean useAmbientOcclusion();
      Material.Baked particleMaterial();
      @BakedQuad.MaterialFlags int materialFlags();
  }
  ```
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/block/dispatch/BlockStateModel.java`,
  `BlockStateModelPart.java`, `SingleVariant.java`.
- **Комментарий:** готовые формы для копирования — `SingleVariant` (одна часть), `WeightedVariants`,
  `net.minecraft.client.renderer.block.model.{CompositeBlockModel, ConditionalBlockModel,
  BlockStateModelWrapper, SpecialBlockModelWrapper, EmptyBlockModel}`. Предметная сторона совсем
  другая: `net.minecraft.client.renderer.item.{ItemModel, ItemStackRenderState, ItemModelResolver}` —
  общий враппер «на блок и на предмет сразу» сделать нельзя.

### `BakedQuad` — теперь immutable record
```java
public record BakedQuad(Vector3fc position0..3, long packedUV0..3, Direction direction,
                        BakedQuad.MaterialInfo materialInfo) {
    public static final int FLAG_TRANSLUCENT = 1;
    public static final int FLAG_ANIMATED    = 2;
    public record MaterialInfo(TextureAtlasSprite sprite, ChunkSectionLayer layer,
                               RenderType itemRenderType, int tintIndex, boolean shade, int lightEmission) {
        public boolean isTinted();
        public @MaterialFlags int flags();
    }
}
```
**Подтверждено:** `/opt/mc-src/net/minecraft/client/resources/model/geometry/BakedQuad.java`.
**Комментарий:** `getVertices():int[]`, мутабельные `quad.sprite` / `quad.tintIndex` — всё исчезло.
Любой код, который «правил квадры на месте» (типичный приём NeoForge-ретекстуринга), переписывается
через `QuadEmitter` (§4). Спрайт квадра — `quad.materialInfo().sprite()`, имя спрайта —
`sprite.contents().name()`, атлас — `sprite.atlasLocation()`.

---

## 2. `IGeometryLoader` → Fabric: **ключ в JSON называется `fabric:type`, а не `loader`**

- **Было (NeoForge):** `{"loader": "<modid>:<name>", …}` в файле модели, лоадер регистрируется на
  `ModelEvent.RegisterGeometryLoaders`.
- **Стало (26.2 Fabric):** прямой аналог есть —
  ```java
  UnbakedModelDeserializer.register(Identifier id, UnbakedModelDeserializer deserializer);
  // interface: UnbakedModel deserialize(JsonObject, JsonDeserializationContext);
  ```
  но диспетчер `net.fabricmc.fabric.impl.client.model.loading.UnbakedModelJsonDeserializer` читает
  **`"fabric:type"`** и ничего больше. Поддерживаются две формы:
  `"fabric:type": "<ns>:<id>"` и `"fabric:type": {"id": "<ns>:<id>", "optional": true}`.
- **Подтверждено:** `javap -p -c` по
  `~/.gradle/caches/modules-2/files-2.1/net.fabricmc.fabric-api/fabric-model-loading-api-v1/8.0.15+c80601bb9e/…jar`,
  класс `UnbakedModelJsonDeserializer#deserialize`: в байткоде литерал `"fabric:type"`, затем
  `Identifier.parse` → `UnbakedModelDeserializer.get(id)`.
- **Комментарий (важно для портов Forge/NeoForge-модов):**
  1. Чужой ключ `"loader"` **не ломает загрузку**. Ванильный `CuboidModel.Deserializer` читает только
     `elements`, `parent`, `textures`, `ambientocclusion`, `display`, `gui_light` и молча игнорирует
     всё остальное (`/opt/mc-src/net/minecraft/client/resources/model/cuboid/CuboidModel.java`).
     Модель `{"parent": "…", "loader": "…"}` просто загрузится как обычный «наследую родителя» —
     то есть **сотни готовых JSON можно не трогать**.
  2. Отсюда общий рецепт: если поведение можно навесить **по блоку**, а не по файлу модели —
     навешивай по блоку через `ModelLoadingPlugin` (§3) и не трогай ресурсы вовсе. Это ещё и
     надёжнее: блок, у которого модель потеряла маркер, всё равно получит поведение.
  3. `UnbakedModelDeserializer` возвращает `UnbakedModel`, то есть **только данные файла модели**
     (§0). Полноценную кастомную блочную модель через него не сделать — для этого есть
     `CustomUnbakedBlockStateModel` (регистрируется `MapCodec`-ом и парсится из **blockstate**-JSON,
     не из model-JSON) либо `ModelLoadingPlugin`.

### Полный API `fabric-model-loading-api-v1` 8.0.15 (`javap`)
```java
interface ModelLoadingPlugin { static void register(ModelLoadingPlugin); void initialize(Context); }
interface ModelLoadingPlugin.Context {
    void registerBlockStateResolver(Block, BlockStateResolver);
    <T> void addModel(ExtraModelKey<T>, UnbakedExtraModel<T>);
    Event<ModelModifier.OnLoad>          modifyModelOnLoad();
    Event<ModelModifier.OnLoadBlock>     modifyBlockModelOnLoad();
    Event<ModelModifier.BeforeBakeBlock> modifyBlockModelBeforeBake();
    Event<ModelModifier.AfterBakeBlock>  modifyBlockModelAfterBake();
    Event<ModelModifier.BeforeBakeItem>  modifyItemModelBeforeBake();
    Event<ModelModifier.AfterBakeItem>   modifyItemModelAfterBake();
}
interface ModelModifier.AfterBakeBlock {
    BlockStateModel modifyModelAfterBake(BlockStateModel, Context);   // Context: state(), sourceModel(), baker()
}
interface ModelModifier.BeforeBakeBlock {
    BlockStateModel.UnbakedRoot modifyModelBeforeBake(BlockStateModel.UnbakedRoot, Context); // state(), baker()
}
interface BlockStateResolver { void resolveBlockStates(Context); }  // Context: block(), setModel(BlockState, UnbakedRoot)
interface CustomUnbakedBlockStateModel extends BlockStateModel.Unbaked {
    static void register(Identifier, MapCodec<? extends CustomUnbakedBlockStateModel>);
    MapCodec<? extends CustomUnbakedBlockStateModel> codec();
}
// фазы для Event#register(Identifier phase, listener):
ModelModifier.OVERRIDE_PHASE / DEFAULT_PHASE / WRAP_PHASE / WRAP_LAST_PHASE
// готовые абстрактные врапперы:
package …v1.wrapper: WrapperBlockStateModel, WrapperUnbakedRootBlockStateModel,
                     WrapperUnbakedModel, WrapperUnbakedItemModel, WrapperBakedItemModel
```

---

## 3. Данные блок-сущности → модель: **`ModelData` не нужен вовсе**

- **Было (NeoForge):** `BlockEntity#getModelData()` → `ModelData` (ключи `ModelProperty`), модель
  получала его параметром `getQuads(..., ModelData data, ...)`.
- **Стало (26.2):** два независимых механизма, оба рабочие.
  1. **Прямой (проще; использован в этом порте).** FRAPI добавляет каждому `BlockStateModel`:
     ```java
     // net/fabricmc/fabric/api/client/renderer/v1/model/FabricBlockStateModel
     default void emitQuads(QuadEmitter emitter, BlockAndTintGetter level, BlockPos pos,
                            BlockState state, RandomSource random, Predicate<Direction> cullTest);
     default Object          createGeometryKey(BlockAndTintGetter, BlockPos, BlockState, RandomSource);
     default Material.Baked  particleMaterial(BlockAndTintGetter, BlockPos, BlockState);
     default int             materialFlags(BlockAndTintGetter, BlockPos, BlockState, RandomSource);
     ```
     то есть **уровень и позиция уже на входе**, и блок-сущность читается напрямую. Отдельного
     канала передачи данных не требуется в принципе.
  2. **Снимок (правильнее для мутабельного состояния).** `fabric-block-getter-api-v2`:
     ```java
     interface RenderDataBlockEntity { default Object getRenderData(); }   // реализуй на BlockEntity
     interface FabricBlockGetter     { default Object getBlockEntityRenderData(BlockPos); }
     ```
     `BlockGetter` **уже** расширяет `FabricBlockGetter` в 26.2, так что вызывать можно прямо на
     `BlockAndTintGetter`. Регион чанка снимает значение на главном потоке — это точный эквивалент
     `ModelData` и единственный безопасный способ читать мутабельное состояние BE из воркера
     чанк-билдера.
- **Подтверждено:** `javap` по `fabric-renderer-api-v1-14.1.2` и `fabric-block-getter-api-v2-2.0.7`;
  `/opt/mc-src/net/minecraft/world/level/BlockGetter.java:25`
  (`public interface BlockGetter extends LevelHeightAccessor, FabricBlockGetter`).
- **Комментарий / грабли:**
  - `createGeometryKey(...)` по умолчанию возвращает `null`, и это **выключает кэш геометрии**.
    Если модель зависит от данных BE — верни объект с корректными `equals`/`hashCode`
    (у нас `record GeometryKey(BlockState, MaterialTextureData)`), иначе одинаковые соседние блоки
    будут пересчитываться каждый раз, а при неверном ключе — наоборот, покажут чужую текстуру.
  - `materialFlags(...)` надо переопределять вместе с `emitQuads`, если ретекстур может добавить
    полупрозрачность или анимацию: по флагам рендерер решает, ждать ли от блока translucent-геометрию.
    Забудешь — стекло-материал молча пропадёт из translucent-прохода.
  - `emitQuads` вызывается **безусловно** для каждого блока: `SectionCompilerMixin`
    (fabric-renderer-api) перенаправляет `ModelBlockRenderer#tesselateBlock` на
    `AltModelBlockRenderer#tesselateBlock(QuadEmitter, …, BlockStateModel, seed)`. Никакого
    «opt-in» и никаких `instanceof`-быстрых путей в этом миксине нет.
  - После изменения данных BE нужно попросить перебейк: `level.setBlocksDirty(pos, oldState, newState)`
    (замена NeoForge `requestModelDataUpdate()`).

---

## 4. `IQuadTransformer` → `QuadEmitter`: как перетекстурировать квадр

- **Было (NeoForge):** `quad.sprite = newSprite;` + правка `quad.getVertices()[i]` через
  `Float.intBitsToFloat`, плюс `QuadTransformers.applyingColor(argb)`.
- **Стало (26.2):**
  ```java
  emitter.cullFace(cullFace);          // ВАЖНО: до fromBakedQuad
  emitter.fromBakedQuad(quad);         // UV попадают в АТЛАСНЫХ координатах исходного спрайта
  emitter.ambientOcclusion(part.useAmbientOcclusion() ? TriState.DEFAULT : TriState.FALSE);
  emitter.shadeMode(ShadeMode.VANILLA);

  // 1) нормализовать UV обратно в 0..1 внутри СТАРОГО спрайта
  TextureAtlasSprite old = quad.materialInfo().sprite();
  for (int v = 0; v < 4; v++) {
      float u = (emitter.u(v) - old.getU0()) / (old.getU1() - old.getU0());
      float w = (emitter.v(v) - old.getV0()) / (old.getV1() - old.getV0());
      emitter.uv(v, u, w);
  }
  // 2) интерполировать их в НОВЫЙ спрайт + обновить атлас/слой/анимацию/itemRenderType
  emitter.materialBake(newMaterialBaked, MutableQuadView.BAKE_NORMALIZED);

  emitter.multiplyColor(argb);   // тинт
  emitter.tintIndex(-1);         // чтобы не тинтануло второй раз
  emitter.emit();
  ```
- **Подтверждено:** `javap -c` по `fabric-renderer-api-v1-14.1.2`:
  `MutableQuadView#materialBake` → `QuadSpriteBaker.bakeSprite(quad, sprite, flags)` → `interpolate`;
  `postMaterialBake(Material.Baked)` ставит `atlas`, `animated`, `chunkLayer`, `itemRenderType`,
  но **UV не трогает**.
- **Комментарий / грабли:**
  - **`BAKE_NORMALIZED` (бит `32`) обязателен.** Без него `bakeSprite` считает, что UV в ванильном
    пространстве элементов 0..16, и делит их на 16 — текстура «съедется» в угол спрайта.
    Проверено по байткоду `QuadSpriteBaker#bakeSprite` (`bipush 32; iand`).
  - Порядок вызовов — не косметика: канонический ванильный энкодер
    `net.fabricmc.fabric.impl.client.renderer.VanillaBlockModelPartEncoder#emitQuads` делает ровно
    `cullFace → fromBakedQuad → ambientOcclusion → shadeMode → emit`. `fromBakedQuad` перетирает
    часть состояния эмиттера, поэтому `cullFace` ставится до него.
  - **Семантика `Predicate<Direction> cullTest`: `true` = грань надо ПРОПУСТИТЬ.** В том же энкодере
    `if (cullTest.test(face)) continue;`. Легко перепутать и получить пустую модель.
  - Цикл по граням: `for (int i = 0; i <= ModelHelper.NULL_FACE_ID; i++)`, где `NULL_FACE_ID == 6`
    и `ModelHelper.faceFromIndex(6) == null` (бакет «без cull-грани»). Предикат вызывается и с `null`.
  - `QuadView` **не отдаёт спрайт**. Если ты внутри `QuadTransform`, а не итерируешь `BakedQuad`
    сам, спрайт ищется через `SpriteFinder.find(QuadView)` (`…v1/sprite/SpriteFinder`, добывается
    из `FabricTextureAtlas#spriteFinder()`). Проще итерировать части модели самому — там
    `quad.materialInfo().sprite()` под рукой.
  - `Material.Baked` — это `record Baked(TextureAtlasSprite sprite, boolean forceTranslucent)`;
    собирается вручную, конструктор публичный.

---

## 5. Тинты: `BlockColor`/`ItemColor` → `BlockTintSource` / `ItemTintSource`

- **Было:** `BlockColors#getColor(state, level, pos, tintIndex)` и `ItemColors#getColor(stack, tintIndex)`;
  `tintIndex` — произвольное int-значение, в которое моды любили паковать данные.
- **Стало:**
  ```java
  // /opt/mc-src/net/minecraft/client/color/block/BlockTintSource.java
  public interface BlockTintSource {
      int color(BlockState state);
      default int colorInWorld(BlockState, BlockAndTintGetter, BlockPos);
      default int colorAsTerrainParticle(BlockState, BlockAndTintGetter, BlockPos);
      default Set<Property<?>> relevantProperties();
  }
  // /opt/mc-src/net/minecraft/client/color/block/BlockColors.java
  public List<BlockTintSource> getTintSources(BlockState);
  public @Nullable BlockTintSource getTintSource(BlockState, int layer);
  public void register(List<BlockTintSource> layers, Block... blocks);
  ```
  Регистрация на Fabric: `BlockColorRegistry.register(List<BlockTintSource>, Block...)`
  (`fabric-rendering-v1`, пакет `net.fabricmc.fabric.api.client.rendering.v1`). `ColorProviderRegistry`
  **не существует** — это имя из старого Fabric API, в 26.2 его нет ни в одном jar.
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/color/block/`, `…/color/item/`;
  `javap` по `fabric-rendering-v1-25.3.1` (там ровно `BlockColorRegistry` + `ColorResolverRegistry`,
  ничего для предметов).
- **Комментарий / главные грабли:**
  - **`tintIndex` квадра теперь — индекс слоя** в `List<BlockTintSource>` блока, с проверкой границ.
    Любая схема «упакуем данные в tintIndex» мертва.
  - **Для предметов кодового API тинта нет вообще.** `Minecraft#getItemColors()` удалён; тинт
    описывается в item-model-JSON (`ItemTintSources`: `Constant`, `Dye`, `GrassColorSource`,
    `MapColor`, `Potion`, `Firework`, `TeamColor`, `CustomModelDataSource`).
  - Практичный обход для блоков: если ты и так эмитишь квадры сам (§4) — посчитай цвет на месте и
    вмешай его в вершины (`multiplyColor`), а `tintIndex` выстави `-1`. Регистрация тинт-сорса
    тогда не нужна вовсе.

---

## 6. Слои рендера: кода больше нет

- **Было:** `ItemBlockRenderTypes.setRenderLayer(block, RenderType.cutout())`, на Fabric —
  `BlockRenderLayerMap.INSTANCE.putBlock(...)`.
- **Стало:** обоих API нет. Слой вычисляется на квадр: `BakedQuad.MaterialInfo.of(material,
  transparency, …)` вызывает `ChunkSectionLayer.byTransparency(transparency)`, где `transparency`
  берётся из альфы спрайта (`TextureAtlasSprite#transparency()`) либо форсируется флагом материала
  `Material(Identifier sprite, boolean forceTranslucent)` — в JSON это
  `{"sprite": "...", "force_translucent": true}`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/resources/model/geometry/BakedQuad.java:65-76`,
  `/opt/mc-src/net/minecraft/client/resources/model/sprite/Material.java`.
- **Комментарий:** при порте мода, который принудительно ставил `translucent` блокам с непрозрачной
  текстурой, поведение изменится (станет `SOLID`). Лечится только датагеном
  (`"force_translucent": true`), кодом — никак.

---

## 7. `RenderType` и `RenderStateShard`

- **Было:** `RenderType.create(name, VertexFormat, Mode, bufSize, crumbling, sorting, CompositeState)`
  с `CompositeState.builder().setShaderState(...).setDepthTestState(...)…`.
- **Стало:** `RenderStateShard` удалён целиком, остался один конструктор
  `RenderType.create(String name, RenderSetup state)`; `RenderSetup` собирается вокруг Blaze3D
  `RenderPipeline` (`state.pipeline`, `state.outputTarget`, `state.layeringTransform`,
  `state.textureTransform`, `state.textures`).
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/rendertype/RenderType.java:29-41`,
  каталог `/opt/mc-src/net/minecraft/client/renderer/rendertype/`
  (`LayeringTransform`, `OutputTarget`, `PreparedRenderType`, `RenderSetup`, `TextureTransform`).
- **Комментарий:** кастомные пайплайны на Fabric строятся через
  `net.fabricmc.fabric.api.client.rendering.v1.FabricRenderPipeline.Builder`. `RenderSystem.depthFunc`
  и прочая GL-мелочь исчезли — в 26.2 есть Vulkan-бэкенд и обратный depth-буфер, per-draw depth-func
  больше не выражается. Immediate mode тоже мёртв: `RenderType#draw(MeshData)`, `Tesselator`,
  `BufferUploader` — ничего этого нет, рендер уровня идёт через `SubmitNodeCollector`.
  Уровневые события Fabric для своей отрисовки:
  `net.fabricmc.fabric.api.client.rendering.v1.level.{LevelRenderEvents, LevelExtractionEvents}`
  (`AfterOpaqueTerrain`, `BeforeTranslucentTerrain`, `AfterTranslucentTerrain`, `CollectSubmits`, …).

---

## 8. Экраны: два уточнения сверх `NOTES-C` §5

- **`mouseClicked` / `mouseDragged` сменили сигнатуру** (в `NOTES-C` этого нет):
  ```java
  public boolean mouseClicked(MouseButtonEvent event, boolean doubleClick);
  public boolean mouseDragged(MouseButtonEvent event, double dx, double dy);
  public boolean mouseScrolled(double x, double y, double scrollX, double scrollY);  // без изменений
  ```
  `record MouseButtonEvent(double x, double y, MouseButtonInfo buttonInfo)`, кнопка — `event.button()`.
  **Подтверждено:** `/opt/mc-src/net/minecraft/client/gui/screens/inventory/AbstractContainerScreen.java:280,361,143`,
  `/opt/mc-src/net/minecraft/client/input/MouseButtonEvent.java`.
- **`extractBackground` переставил аргументы:** было `renderBg(GuiGraphics, float partialTick, int x, int y)`,
  стало `extractBackground(GuiGraphicsExtractor, int mouseX, int mouseY, float a)`. Старые `x, y` были
  **координатами мыши** и остались ими — при ручном переносе тела легко перепутать смысл.
- Переопределяемого `renderTooltip` больше нет — свои тултипы ставятся из `extractRenderState`
  через `graphics.setTooltipForNextFrame(...)` (есть перегрузка с `ItemStack`:
  `setTooltipForNextFrame(Font, ItemStack, int, int)`, `GuiGraphicsExtractor.java:1073`).
- `graphics.blit` без `RenderPipeline` не существует: `blit(RenderPipeline, Identifier, int x, int y,
  float u, float v, int w, int h, int texW, int texH)`. Размеры текстуры теперь обязательны.

---

## 9. Ложные срабатывания офлайн-`javac` (§11 `NOTES-C`) — расширенный список

Сырой `minecraft-merged-deobf-26.2.jar` не содержит ни access wideners, ни **инъекций интерфейсов**
из classtweaker'ов fabric-api. Поэтому офлайн-проверка типов даёт ошибки, которых под Loom нет:

| Ошибка `javac` | Реальность | Обход, если мешает |
|---|---|---|
| `MenuScreens.register has private access`, `ScreenConstructor has private access` | расширено `fabric-transitive-access-wideners-v1` (javadoc прямо в `/opt/mc-src/.../MenuScreens.java:60,113`) | ничего не делать — ложное |
| `cannot find symbol: getBlockEntityRenderData(BlockPos)` на `BlockAndTintGetter` | `BlockGetter extends … FabricBlockGetter` после classtweaker'а `fabric-block-getter-api-v2` | привести явно: `((FabricBlockGetter) level).getBlockEntityRenderData(pos)` — в рантайме это no-op |

Обратно: методы `FabricBlockStateModel` (`emitQuads`, `createGeometryKey`, …) **видны** офлайн,
потому что `BlockStateModel extends FabricBlockStateModel` записано прямо в исходнике игры,
а не инъектировано.

---

## 10. Мелочи, найденные попутно

| Символ | 26.2 | Подтверждение |
|---|---|---|
| `CompoundTag#getAllKeys()` | `keySet()` | `/opt/mc-src/net/minecraft/nbt/CompoundTag.java:193` |
| `CompoundTag#getString(String)` | возвращает `Optional<String>`; безусловный вариант — `getStringOr(name, def)` | `CompoundTag.java:331,335` |
| `Registry#get(Identifier)`, возвращавший `T` | `getValue(Identifier)` → `@Nullable T`; `get(Identifier)` → `Optional<Holder.Reference<T>>` | `/opt/mc-src/net/minecraft/core/Registry.java:65,133` |
| `Direction.from3DDataValue(int)` / `get3DDataValue()` | без изменений | `/opt/mc-src/net/minecraft/core/Direction.java:45,155` |
| `@Nullable` на вложенном типе | jspecify — это TYPE_USE: писать `Material.@Nullable Baked`, а не `@Nullable Material.Baked` (иначе `type annotation … is not expected here`) | ошибка `javac` |
| `Sheets.translucentCullBlockSheet()`, `cutoutBlockItemSheet()`, `translucentBlockItemSheet()`, `cutoutItemSheet()`, `translucentItemSheet()` | живы, в `net.minecraft.client.renderer.Sheets` | `/opt/mc-src/net/minecraft/client/renderer/Sheets.java` |
| `BlockRenderDispatcher#getBlockModel(state)` | `Minecraft#getModelManager().getBlockStateModelSet().get(BlockState) -> BlockStateModel` | `/opt/mc-src/net/minecraft/client/resources/model/ModelManager.java:90`, `/opt/mc-src/net/minecraft/client/renderer/block/BlockStateModelSet.java` |
| кэш, привязанный к запечённым моделям | инвалидировать по смене инстанса `BlockStateModelSet` (он пересоздаётся на каждой перезагрузке ресурсов) — иначе кэш отдаст спрайты со старого, уже освобождённого атласа | практика |

---

## 11. Рецепт целиком: «модель, перетекстурирующаяся из блок-сущности» на 26.2

Мини-шаблон, который переносится на любой мод с материально-текстурируемыми блоками.

```java
// 1. Плагин загрузки моделей: оборачиваем запечённую модель каждого нужного блок-стейта.
public class MyPlugin implements ModelLoadingPlugin {
    public static void register() { ModelLoadingPlugin.register(new MyPlugin()); }

    @Override public void initialize(Context ctx) {
        ctx.modifyBlockModelAfterBake().register(ModelModifier.WRAP_PHASE, (model, c) ->
            c.state().getBlock() instanceof MyBlock && !(model instanceof MyModel)
                ? new MyModel(model) : model);
    }
}

// 2. Враппер поверх готового абстрактного класса FRAPI.
public class MyModel extends WrapperBlockStateModel {
    public MyModel(BlockStateModel inner) { super(inner); }

    @Override public void emitQuads(QuadEmitter e, BlockAndTintGetter level, BlockPos pos,
                                    BlockState state, RandomSource rnd, Predicate<Direction> cullTest) {
        MyData data = readData(level, pos);                 // §3
        if (data.isEmpty()) { super.emitQuads(e, level, pos, state, rnd, cullTest); return; }

        List<BlockStateModelPart> parts = new ArrayList<>();
        this.wrapped.collectParts(rnd, parts);
        for (BlockStateModelPart part : parts) {
            TriState ao = part.useAmbientOcclusion() ? TriState.DEFAULT : TriState.FALSE;
            for (int i = 0; i <= ModelHelper.NULL_FACE_ID; i++) {
                Direction cull = ModelHelper.faceFromIndex(i);
                if (cullTest.test(cull)) continue;          // true == пропустить!
                for (BakedQuad q : part.getQuads(cull)) {
                    e.cullFace(cull); e.fromBakedQuad(q);
                    e.ambientOcclusion(ao); e.shadeMode(ShadeMode.VANILLA);
                    retextureIfNeeded(e, q, data, state, level, pos);   // §4
                    e.emit();
                }
            }
        }
    }

    @Override public Object createGeometryKey(BlockAndTintGetter l, BlockPos p, BlockState s, RandomSource r) {
        return new Key(s, readData(l, p));                  // иначе кэш геометрии выключен
    }
    @Override public int materialFlags(BlockAndTintGetter l, BlockPos p, BlockState s, RandomSource r) {
        return this.wrapped.materialFlags() | extraFlags(readData(l, p));  // FLAG_TRANSLUCENT / FLAG_ANIMATED
    }
    @Override public Material.Baked particleMaterial(BlockAndTintGetter l, BlockPos p, BlockState s) { … }
}

// 3. Блок-сущность: снимок для воркеров чанк-билдера + запрос перебейка.
public class MyBlockEntity extends BlockEntity /* implements RenderDataBlockEntity */ {
    @Override public Object getRenderData() { return this.data; }          // immutable!
    private void afterDataChanged() {
        if (level != null && level.isClientSide())
            level.setBlocksDirty(worldPosition, Blocks.AIR.defaultBlockState(), getBlockState());
    }
}

// 4. Регистрация — только из ClientModInitializer#onInitializeClient (плагины собираются на init).
```


---

# Часть VI. Porting guide — **LuckyTNTMod** (`tntmod/`) → Minecraft 26.2


> **Audience:** coding agents porting the *mod* (`tntmod/`, 303 Java files).
> **Status of the library:** ✅ **DONE.** `TntLib/` (LuckyTNTLib) is already fully
> ported to 26.2, builds green, and boots on a dedicated server. You are porting
> the **mod against the already-ported library** — do not re-port the library.
> Read section 0 before touching a file, then use the verified rename map in §4.

---

## 0. STOP — the facts that matter

1. **Target is `26.2`** (year.drop scheme; "1.26.2" is not a thing — it means 26.2).
   Write `26.2` everywhere, never `1.26.2`.
2. **Yarn/Intermediary are dead.** 26.1+ is unobfuscated; use **Mojang official
   mappings**. Never emit yarn names (`Identifier`→stays `Identifier` but the *package*
   changes, `MinecraftClient`, `World`, `Item.Settings`, `class_XXXX`, …).
3. **Java 21 → Java 25.** Mixin `compatibilityLevel` must be `JAVA_25`.
4. **The library is ported and is your single best reference.** Every API pattern
   the mod needs (registration, entities, renderers, mixins, networking, explosions,
   config GUI) already exists, correct and compiling, under `TntLib/src/main/java/luckytntlib/`.
   When unsure how to do something in the mod, **find the equivalent in the ported lib first.**
5. **Verify against live source, not memory.** Your training data predates the 26.x
   rewrites. Grep the decompiled MC source and the ported lib before writing a signature.

---

## 1. Toolchain (identical to the ported library)

| | value |
|---|---|
| Minecraft | `26.2` |
| Fabric Loader | `0.19.3` |
| Fabric API | `0.154.2+26.2` |
| Loom | `1.17.13` (`id 'net.fabricmc.fabric-loom'`) |
| Gradle | **9.6.1** (Java 25 needs Gradle 9.x) |
| Java | **25** (`options.release = 25`, `sourceCompatibility/targetCompatibility = VERSION_25`) |
| Mappings | **Mojang official** — NO `mappings "net.fabricmc:yarn:…"` line |

**Gradle in this environment:** the wrapper cannot download its distribution (egress
policy blocks GitHub release assets → HTTP 403). Use the vendored distribution:
```sh
./gradle-dist/install.sh                 # unpacks to /opt/gradle-9.6.1
export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64
/opt/gradle-9.6.1/bin/gradle build --no-daemon      # NOT ./gradlew
```
(Java 25: `sudo apt-get install -y openjdk-25-jdk-headless`, then
`sudo update-java-alternatives -s java-1.25.0-openjdk-amd64`.)

### `tntmod/build.gradle` — the structural rewrite (mirror `TntLib/build.gradle`)
1. Plugin id `id "fabric-loom"` → `id "net.fabricmc.fabric-loom" version "${loom_version}"`.
2. **Delete** the `mappings "net.fabricmc:yarn:…"` line.
3. Drop `mod` config prefixes: `modImplementation`→`implementation`, `modApi`→`api`, `modCompileOnly`→`compileOnly`.
4. `it.options.release = 21` → `25`; Java compat → `VERSION_25`; add `it.options.encoding = "UTF-8"`.
5. **Consume the local library, not JitPack.** The current dep is
   `modImplementation "com.github.SlimingHD:Fabric-LuckyTNTLib:1.21-0.100.6.1"` — that
   1.21 artifact will NOT resolve on 26.2. Replace it with the ported lib. Two options:
   - **`includeBuild` (recommended):** in `tntmod/settings.gradle` add
     `includeBuild("../TntLib")`, and depend on `implementation "luckytntlib:fabric-luckytntlib-26.2:0.100.6.1"`
     (group/name from `TntLib/gradle.properties`). Loom will build+include the lib.
   - **flatDir jar:** point at the prebuilt jar in the repo-root `dist/`
     (`fabric-luckytntlib-26.2-0.100.6.1.jar`). Fine for a quick compile; `includeBuild`
     is better for iterating on both at once.
6. `gradle.properties`: bump `minecraft_version=26.2`, `loader_version=0.19.3`,
   `fabric_version=0.154.2+26.2`, add `loom_version=1.17.13`; rename
   `archives_base_name=fabric-luckytntmod-26.2`. Keep `mod_version`.
7. `fabric.mod.json`: `depends` → `fabricloader >=0.19.3`, `minecraft ">=26.2 <26.3"`,
   `java ">=25"`, and add a hard dep on `luckytntlib`. Bump `luckytntlib.mixins.json`-style
   mixin config `compatibilityLevel` to `JAVA_25`.

---

## 2. References, in priority order

1. **`TntLib/src/main/java/luckytntlib/`** — the ported library. Same idioms, same
   mappings, same problems already solved. **Start here.**
2. **Decompiled MC 26.2 source** — regenerate once with
   `/opt/gradle-9.6.1/bin/gradle genSources` (in `TntLib/` or `tntmod/`); it lands under
   `<project>/.gradle/loom-cache/minecraftMaven/.../minecraft-merged-*-26.2-sources.jar`.
   Unzip it and grep for exact signatures. This is ground truth.
3. **`desolation/`** (sibling repo) — an independent, working 26.2 Fabric mod. Good for
   GeckoLib/registration/networking usage patterns.
4. Fabric docs/blog (`fabricmc.net`, `docs.fabricmc.net`) for API-level guidance only.

**Rule:** never invent a signature. If you can't confirm it in (1)–(2), stop and say so.

---

## 3. The library API the mod consumes (already 26.2 — match these exactly)

The mod is built on the lib's abstractions. Their **signatures changed** in the port —
update every call site in the mod accordingly:

| `luckytntlib` symbol | 26.2 signature (as ported) |
|---|---|
| `IExplosiveEntity#getLevel()` | returns `net.minecraft.world.level.Level` (was `World`) |
| `IExplosiveEntity#getPos()` | returns `net.minecraft.world.phys.Vec3` (was `Vec3d`) |
| `IExplosiveEntity#getPersistentData()` / `setPersistentData(..)` | `net.minecraft.nbt.CompoundTag` (was `NbtCompound`) |
| `IExplosiveEntity#owner()` / `getEffect()` / `getTNTFuse()` / `x()/y()/z()` / `destroy()` | unchanged names |
| `PrimedTNTEffect` | `getBlock():Block`, `getBlockState(IExplosiveEntity):BlockState`, `getItem():Item`, `getItemStack():ItemStack`, `getSize/getDefaultFuse(IExplosiveEntity)`, `serverExplosion/explosionTick/spawnParticles/baseTick(IExplosiveEntity)`, `toBlockPos(Vec3)` — all present; block/item/nbt types are now the Mojang ones |
| `ImprovedExplosion` | now **`implements Explosion`** (interface); constructors take `Level`, `Vec3`, `Entity`; `doBlockExplosion(...)`, `doEntityExplosion(...)`, `doOldBlockExplosion(...)` unchanged in shape |
| `ExplosionHelper` | static helpers take `Level`, `Vec3` now |
| `TNTXStrengthEffect.Builder` | unchanged fluent API (`fuse/strength/xzStrength/...build()/buildTNT/buildDynamite`) |
| `RegistryHelper` | same method names (`registerTNTBlock`, `registerTNTEntity`, `registerDynamiteItem`, `registerTNTMinecart(Item)`, `registerExplosiveProjectile`, `registerLivingTNT*`, `sendS2CPacket(ServerPlayer,CustomPacketPayload)`, `sendC2SPacket(CustomPacketPayload)`, `registerConfigScreenFactory(Component,..)`); `configScreens` is now `List<Pair<Component,ConfigScreenFactory>>` |
| `LTNTBlock` / `LivingLTNTBlock` / `LuckyTNTBlock` | constructors take `BlockBehaviour.Properties`; `explode(Level, boolean, int,int,int, LivingEntity)` |
| `LDynamiteItem` / `LTNTMinecartItem` / `LuckyDynamiteItem` | constructors take `Item.Properties`; `LTNTMinecartItem#createMinecart(Level, double,double,double, LivingEntity)` |
| `PrimedLTNT` / `LivingPrimedLTNT` / `LExplosiveProjectile` / `LTNTMinecart` | ctors take `(EntityType<…>, Level, …)`; `LExplosiveProjectile implements ItemSupplier` (`getItem():ItemStack`); `LTNTMinecart#getDisplayBlockState()` |
| `LuckyTNTEntityExtension` / `EntityMixin` | additional persistent data is `CompoundTag`, stored in a plain save-backed field |
| `LTNTDataSerializers` | new: custom synced `CompoundTag` serializer, registered via `FabricEntityDataRegistry`; **only relevant if the mod adds its own synced `CompoundTag` tracked data** |

The **217 `tnteffects/*`** files are mostly pure logic on top of these abstractions — once
the types above are updated, most recompile with only type-name/import changes.

---

## 4. Verified Yarn → 26.2 rename map (same as the library used)

**Surprises (do not assume the classic Mojang name):**
- `Identifier` keeps its name, **moves package**: `net.minecraft.resources.Identifier`
  (NOT `ResourceLocation`). Build ids with `Identifier.fromNamespaceAndPath(ns, path)`
  (`Identifier.of` does **not** exist in 26.2).
- Registry-key holders are swapped: yarn `RegistryKeys` → `net.minecraft.core.registries.Registries`;
  yarn `Registries` (frozen) → `net.minecraft.core.registries.BuiltInRegistries`.
- Vanilla entity type constants live in **`EntityTypes`** (plural).

**Core / util**

| Yarn | 26.2 |
|---|---|
| `util.Identifier` | `resources.Identifier` |
| `util.math.BlockPos` | `core.BlockPos` |
| `util.math.Vec3d` | `world.phys.Vec3` |
| `util.math.Box` | `world.phys.AABB` |
| `util.math.Direction` | `core.Direction` |
| `util.math.MathHelper` | `util.Mth` |
| `util.math.random.Random` | `util.RandomSource` |
| `util.math.RotationAxis` | `com.mojang.math.Axis` (`POSITIVE_Y`→`YP`) |
| `util.hit.BlockHitResult` / `EntityHitResult` | `world.phys.*` |
| `util.Hand` | `world.InteractionHand` |
| `util.ActionResult` / `TypedActionResult` / `ItemActionResult` | `world.InteractionResult` (`use()` now returns `InteractionResult`) |
| `text.Text` / `MutableText` | `network.chat.Component` / `MutableComponent` (`Text.literal`→`Component.literal`) |
| `screen.ScreenTexts` | `network.chat.CommonComponents` |

**World / level**

| Yarn | 26.2 |
|---|---|
| `world.World` | `world.level.Level` |
| `world.WorldAccess` / `BlockView` | `world.level.LevelAccessor` / `BlockGetter` |
| `server.world.ServerWorld` | `server.level.ServerLevel` |
| `world.explosion.Explosion` | `world.level.Explosion` (**now an interface**) |
| `world.explosion.ExplosionBehavior` / `EntityExplosionBehavior` | `world.level.ExplosionDamageCalculator` / `EntityBasedExplosionDamageCalculator` |
| `fluid.FluidState` | `world.level.material.FluidState` |
| `world.event.GameEvent` | `world.level.gameevent.GameEvent` (constants are `Holder<GameEvent>`) |

**Blocks**

| Yarn | 26.2 |
|---|---|
| `block.Block/Blocks/BlockState` | `world.level.block.*` / `…block.state.BlockState` |
| `block.AbstractBlock` / `AbstractBlock.Settings` | `world.level.block.state.BlockBehaviour` / `BlockBehaviour.Properties` (`.create()`→`.of()`, needs `.setId(ResourceKey<Block>)`) |
| `block.AbstractFireBlock` / `AbstractRailBlock` | `BaseFireBlock` / `BaseRailBlock` |
| `block.MapColor` | `world.level.material.MapColor` (`RED`→`FIRE`) |
| `block.entity.BlockEntity(Type)` | `world.level.block.entity.*` |
| `block.enums.RailShape` | `world.level.block.state.properties.RailShape` (`isAscending`→`isSlope`) |
| `state.property.Properties` | `world.level.block.state.properties.BlockStateProperties` |
| `sound.BlockSoundGroup` | `world.level.block.SoundType` |
| `block.dispenser.DispenserBehavior` / `FallibleItemDispenserBehavior` / `ItemDispenserBehavior` | `core.dispenser.DispenseItemBehavior` / `OptionalDispenseItemBehavior` / `DefaultDispenseItemBehavior` (impl `execute(BlockSource,ItemStack)`) |
| `util.math.BlockPointer` | `core.dispenser.BlockSource` (record: `level()/pos()/state()/center()`) |
| `DispenserBlock.getOutputLocation` | `getDispensePosition` |

**Entities**

| Yarn | 26.2 |
|---|---|
| `entity.Entity/LivingEntity/EntityType` | `world.entity.*` |
| `entity.TntEntity` | `world.entity.item.PrimedTnt` |
| `entity.MovementType` | `world.entity.MoverType` |
| `entity.SpawnGroup` | `world.entity.MobCategory` |
| `entity.mob.PathAwareEntity` | `world.entity.PathfinderMob` |
| `entity.player.PlayerEntity` / `server.network.ServerPlayerEntity` | `world.entity.player.Player` / `server.level.ServerPlayer` |
| `entity.projectile.PersistentProjectileEntity` / `ProjectileEntity` | `world.entity.projectile.arrow.AbstractArrow` / `projectile.Projectile` |
| `entity.vehicle.AbstractMinecartEntity` / `MinecartEntity` | `world.entity.vehicle.minecart.AbstractMinecart` / `Minecart` |
| `entity.FlyingItemEntity` | `world.entity.projectile.ItemSupplier` (`getStack()`→`getItem():ItemStack`) |
| `entity.damage.DamageSource/DamageTypes` | `world.damagesource.*` (`DamageTypes.OUT_OF_WORLD`→`FELL_OUT_OF_WORLD`; `source.isOf`→`source.is`) |
| `entity.data.DataTracker` / `TrackedData` / `TrackedDataHandlerRegistry` | `network.syncher.SynchedEntityData` / `EntityDataAccessor` / `EntityDataSerializers` |
| **data-tracker define** | `SynchedEntityData.defineId(Class, EntityDataSerializers.X)`; override `defineSynchedData(SynchedEntityData.Builder b)` with `b.define(ACCESSOR, default)` |
| **entity NBT** | codec-based `addAdditionalSaveData(ValueOutput)` / `readAdditionalSaveData(ValueInput)`; `output.store(name, CODEC, v)`, `input.read(name, CODEC)`, `input.getIntOr/getShortOr(...)`, `output.putInt/putShort(...)` |
| common method renames | `getWorld()`→`level()`, `setVelocity`→`setDeltaMovement`, `getVelocity`→`getDeltaMovement`, `isOnGround`→`onGround`, `hasNoGravity`→`isNoGravity`, `getSoundCategory`→`getSoundSource`, `damage(src,amt)`→`hurtServer(ServerLevel,src,amt)`, `getYaw/setYaw`→`getYRot/setYRot`, `spawnEntity`→`addFreshEntity`, `getEntityById`→`level().getEntity(int)`, `getName()`→`getHoverName()` |

**Items**

| Yarn | 26.2 |
|---|---|
| `item.Item/Items/ItemStack/BlockItem/MinecartItem` | `world.item.*` |
| `Item.Settings` | `Item.Properties` (`.maxCount`→`.stacksTo`, needs `.setId(ResourceKey<Item>)`) |
| `item.ItemUsageContext` / `AutomaticItemPlacementContext` | `world.item.context.UseOnContext` / `DirectionalPlaceContext` |
| `item.ItemGroups` | `world.item.CreativeModeTabs` |
| `component.DataComponentTypes` | `core.component.DataComponents` |
| `use()` | returns `InteractionResult`; `useOnBlock`→`useOn(UseOnContext)`; `usageTick`→`onUseTick`; `getStackInHand`→`getItemInHand` |
| tooltip | `appendTooltip(...)` → `appendHoverText(ItemStack, Item.TooltipContext, TooltipDisplay, java.util.function.Consumer<Component>, TooltipFlag)` |
| durability | `stack.damage(...)`→`stack.hurtAndBreak(int, ServerLevel, ServerPlayer, Consumer<Item>)`; `decrement`→`shrink` |

**Rendering (client)**

| Yarn | 26.2 |
|---|---|
| `client.MinecraftClient` | `client.Minecraft` (`setScreen(x)` → `minecraft.gui.setScreen(x)`) |
| `client.util.math.MatrixStack` | `com.mojang.blaze3d.vertex.PoseStack` |
| `render.VertexConsumerProvider` | `client.renderer.MultiBufferSource` |
| `render.entity.EntityRenderer` / `EntityRendererFactory` | `client.renderer.entity.EntityRenderer` / `EntityRendererProvider` |
| `render.entity.TntMinecartEntityRenderer` / `MinecartEntityRenderer` / `FlyingItemEntityRenderer` | `client.renderer.entity.TntMinecartRenderer` / `MinecartRenderer` / `ThrownItemRenderer` |
| `render.model.json.ModelTransformationMode` | `world.item.ItemDisplayContext` |
| `client.font.TextRenderer` | `client.gui.Font` |
| `client.gui.DrawContext` | `client.gui.GuiGraphics` |
| `client.gui.screen.Screen` | `client.gui.screens.Screen` |
| GUI widgets `ButtonWidget`/`SliderWidget`/`TextWidget` | `client.gui.components.Button`/`AbstractSliderButton`/`StringWidget` |
| layout widgets `GridWidget`/`DirectionalLayoutWidget`/`ThreePartsLayoutWidget`/`Positioner` | `client.gui.layouts.GridLayout`/`LinearLayout`/`HeaderAndFooterLayout`/`LayoutSettings` |
| **Entity renderers** | rewritten to the **render-state** model: `EntityRenderer<T, S extends EntityRenderState>` with `createRenderState()`, `extractRenderState(T,S,float)`, and (this 26.2 snapshot) a **`submit(S, PoseStack, SubmitNodeCollector, CameraRenderState)`** method — NOT `render(...)`/`MultiBufferSource`. `getTexture(entity)` is gone. **Copy the shape from the ported lib renderers** `LTNTRenderer`, `LTNTMinecartRenderer`, `LDynamiteRenderer`, and from vanilla `TntRenderer`/`TntMinecartRenderer`/`ThrownItemRenderer`. |

**Networking / registry / Fabric**

| Yarn | 26.2 |
|---|---|
| `network.PacketByteBuf` / `RegistryByteBuf` | `network.FriendlyByteBuf` / `RegistryFriendlyByteBuf` |
| `network.codec.PacketCodec` | `network.codec.StreamCodec` (`StreamCodec.ofMember(...)`) |
| `network.packet.CustomPayload` / `CustomPayload.Id` | `network.protocol.common.custom.CustomPacketPayload` / `CustomPacketPayload.Type`, method `type()` |
| Fabric `PayloadTypeRegistry.playC2S()/playS2C()` | `serverboundPlay()` / `clientboundPlay()` |
| `registry.Registry` | `core.Registry` |
| `EntityType.Builder.create(f, grp)` | `EntityType.Builder.of(f, MobCategory)`; `.maxTrackingRange`→`.clientTrackingRange`, `.makeFireImmune`→`.fireImmune`, `.dimensions`→`.sized`, `.build(String)`→`.build(ResourceKey<EntityType<?>>)` |
| `EntityType#create(world)` | `create(Level, EntitySpawnReason)` |
| `FabricModelPredicate*` / `ItemColors` / `((FireBlock)Blocks.FIRE).registerFlammableBlock` | model-def JSON / `BlockColorRegistry` / `FlammableBlockRegistry.getDefaultInstance().add(block,burn,spread)` (`FireBlock.setFlammable` is private) |
| `ItemGroupEvents` | `net.fabricmc.fabric.api.creativetab.v1.CreativeModeTabEvents.modifyOutputEvent(ResourceKey<CreativeModeTab>).register(out -> out.accept(item))` |
| `HudRenderCallback` (removed 26.1) | `net.fabricmc.fabric.api.client.rendering.v1.HudElementRegistry` |
| `sound.SoundCategory` | `sounds.SoundSource` |
| `EnchantmentHelper`/`Enchantments` | `world.item.enchantment.*` |
| `particle.ParticleEffect` | `core.particles.ParticleOptions` |

---

## 5. Mod-specific danger zones (sorted by risk)

Layout: `luckytnt` package. 303 files; **217 are `tnteffects/*`** (mostly recompile once
the lib types above are updated — touch only where they hit `getWorld`, block/entity/damage
APIs, or particles).

| Area | Files | Risk | Notes |
|---|---|---|---|
| **Mixins** | `mixin/`: `LivingEntityMixin`, `AbstractMinecartEntityMixin`, `HungerManagerMixin`, `FireBlockMixin` (common) + `GameRendererMixin`, `CameraMixin`, `InGameHudMixin` (client) | 🔴🔴 | `@Inject`/`@Redirect`/`@ModifyVariable` targets reference **exact method names + descriptors** that changed and are NOT auto-migrated. **Re-verify every target against the decompiled 26.2 source.** Two traps proven during the lib port: (a) you **cannot `@Inject` at HEAD of an abstract method** — `Entity.readAdditionalSaveData`/`addAdditionalSaveData` are abstract, so target the concrete callers `load(ValueInput)` / `saveWithoutId(ValueOutput)` instead; (b) `FireBlock` fire-spread is now `checkBurnOut(Level,BlockPos,int,RandomSource,int)` with helpers `getBurnOdds`/`getStateWithAge(LevelReader,…)`. `initDataTracker`→`defineSynchedData`. Set `compatibilityLevel: JAVA_25`. |
| **Entity renderers** | `client/renderer/*` (`BombRenderer`, `AngryMinerRenderer`, `BouncingTNTRenderer`, …), `client/model/*` | 🔴 | Full rewrite to the render-state / `submit(...)` model (see §4). Copy the ported lib renderers. |
| **Registration** | `registry/*` (~17 classes), `block/*`, `item/*`, `entity/*` | 🔴 | `.setId(ResourceKey)` on every `Item.Properties`/`BlockBehaviour.Properties`; `EntityType.Builder.of/build(ResourceKey)`; `EntityType#create(Level, EntitySpawnReason)`; `Registry.register(BuiltInRegistries.*, Identifier.fromNamespaceAndPath(..), obj)`; `FlammableBlockRegistry`; `CreativeModeTabEvents`. Mirror `luckytntlib.registry.RegistryHelper` exactly. |
| **HUD overlay** | `client/overlay/*`, `mixin/InGameHudMixin` | 🟠 | `HudRenderCallback` removed → `HudElementRegistry`; `DrawContext`→`GuiGraphics`. |
| **Items** | `item/*` | 🟠 | `use()`→`InteractionResult`, `appendHoverText`, `Item.Properties`, `hurtAndBreak`. |
| **Config GUI** | `config/*`, `client/gui/*` | 🟠 | Screen/widget/layout signature shifts (see §4); `minecraft.gui.setScreen`. Mirror the lib's `ConfigScreen`. |
| **Worldgen / features** | `feature/*`, `src/generated/data/**` (or `src/main/generated`) | 🟠 | Datapack dir layout (`data/<ns>/<registry>/…`), codec-based feature configs. **Recipe/data JSON:** crafting ingredients are now plain id strings (`"minecraft:iron_ingot"`), not `{"item": …}`. |
| **Commands / events / network** | `commands/*`, `event/*`, `network/*` | 🟢 | Networking already modern; re-map to `CustomPacketPayload`+`StreamCodec` and `serverboundPlay/clientboundPlay`. Commands: Brigadier is stable; check `ServerCommandSource`→`CommandSourceStack`. |
| **`tnteffects/*`** | 217 files | 🟢 | Recompile against the updated lib types; touch only the ones that call vanilla `getWorld`/block/entity/damage/particle APIs directly. |

---

## 6. Workflow & definition of done

1. Port `tntmod/build.gradle` + `gradle.properties` + `settings.gradle` + `fabric.mod.json`
   (§1). Point the lib dependency at the local `TntLib` (`includeBuild`) or the `dist/` jar.
2. `compileJava` first — fix by compiler error, leaning on the ported lib for every pattern.
   Expect the bulk to be mechanical renames from §4; the hard files are the 7 mixins and
   the renderers.
3. Then `build` (applies mixins at package time, processes data/resources).
4. **Smoke-test on a dedicated server** — this catches runtime-only failures the compiler
   can't (mixin targets that don't resolve, `FabricEntityDataRegistry` vs vanilla serializer
   registration, bad data JSON). It worked for the library:
   ```sh
   cd tntmod && mkdir -p run && echo "eula=true" > run/eula.txt
   JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64 /opt/gradle-9.6.1/bin/gradle runServer --no-daemon
   # success = log reaches: Done (N.NNNs)! For help, type "help"   with no /ERROR] lines
   ```
   Client-only content (renderers, GUI, HUD) won't exercise on a server; validate those in
   a real client if a display is available.

**Done when:** `tntmod` compiles & the server boots to `Done (…)!` with zero errors, all TNT
types register, mixins apply, and (client) TNT/dynamite render, throw, and explode.

---

## 7. Rules for agents

- **DO** find the equivalent in the ported `TntLib/` before writing any mod code.
- **DO** verify every version-specific signature against the decompiled 26.2 source.
- **DO** re-verify every mixin `@Inject`/`@Redirect` target by hand against 26.2.
- **DON'T** emit yarn names or `class_XXXX` for 26.x.
- **DON'T** trust pre-2026 tutorials or training memory for signatures — they predate the rewrites.
- **DON'T** re-port the library — it is finished; only adapt the mod's call sites to it.
- **DON'T** invent a method name. If unsure, grep the reference or stop and ask.
- **DON'T** `@Inject` at HEAD of an abstract method — target its concrete caller.

---

## 8. Token economy — MANDATORY for every agent

1. **Environment first, no downloads.** GitHub release assets are blocked by egress
   policy (HTTP 403). NEVER run `./gradlew`, never try to download Gradle/Loom
   distributions — it will fail and waste a whole attempt. Install the vendored
   distribution once: `./gradle-dist/install.sh` → use `/opt/gradle-9.6.1/bin/gradle`
   (see §1 for Java 25 install). Verify with `gradle --version` before anything else.
2. **Mechanical renames are done by a script, not by hand.** Before any hand edits,
   run the ready-made `port-rename.sh` (repo root) ONCE. If it needs extending, how to
   write it: take every row of the §4 tables and turn it into a `perl -pi -e 's/…/…/g'`
   (or `sed -E`) rule over all `tntmod/src/**/*.java` **excluding `*/mixin/*`**
   (mixin targets must be reworked by hand). Rules in three groups, applied in order:
   (a) fully-qualified import paths (`net.minecraft.util.math.Vec3d` →
   `net.minecraft.world.phys.Vec3`), (b) bare class names with `\b` word boundaries
   (`Vec3d`→`Vec3`, `World`→`Level`, `PlayerEntity`→`Player`, …) — replace the longer
   names before their substrings, and swap the `Registries`/`RegistryKeys` pair through
   a temp placeholder so they don't overwrite each other, (c) common method renames
   (`.getWorld()`→`.level()`, `.setVelocity(`→`.setDeltaMovement(`, …).
   It is a FIRST PASS: it doesn't need to be perfect — the compiler catches leftovers.
   Sanity-check with `git diff --stat` and commit it separately before hand fixes.
3. **Work error-driven, never file-driven.** Do not read files "for context".
   Loop: `/opt/gradle-9.6.1/bin/gradle compileJava --no-daemon 2>&1 | tee /tmp/errors.txt`
   → take the first ~30 errors → open ONLY the failing lines (Read with offset/limit)
   → fix → recompile. Never re-read this guide's tables — grep this file instead.
4. **Decompiled sources: unpack once.** The setup agent runs `genSources` once and
   unzips the sources jar to a fixed path (e.g. `/opt/mc-src/`), records the path in
   `PORT-STATUS.md`. All other agents only `grep -rn` that dir — never re-generate.
5. **One smoke test.** Only the final agent runs `runServer` (§6); nobody else boots
   the server.

## 9. Rule: too hard? Disable it, keep the code

If a specific entity/item/effect has complex logic that resists porting (roughly two
honest attempts failed, or it needs an API with no equivalent found in the lib or
decompiled source): **do not block the build and do not delete the code.**

- Preferred: comment out its **registration line(s)** so the content simply doesn't
  exist in game, and stub/comment the broken method bodies so the class still compiles.
- Or comment out the whole broken block, keeping the original source in place:
  ```java
  // TODO(port-26.2): DISABLED — needs manual port (reason: <one line>)
  /* … original code untouched … */
  ```
- Every cut MUST be logged in `PORT-STATUS.md` under "Disabled content" (file, what,
  why). The goal: build green, server boots, original code preserved for a human.

## 10. Orchestrator plan — fully autonomous loop

The orchestrator NEVER asks the user anything and does not stop until done. It does
minimal work itself; agents do the porting.

**Step 0 (orchestrator itself):** install toolchain per §8.1/§1; create
`PORT-STATUS.md` (checklist of §5 areas + "Disabled content" section); run
`port-rename.sh` per §8.2; commit + push.

**Phases** (each agent gets: its role below, its exact file list, and the order to
read §0–§5 + §8–§9 of this file and `PORT-STATUS.md` first):

- **Agent A — setup/core:** `tntmod` build files per §1; `genSources` + unpack to
  `/opt/mc-src/`; fix `registry/*`, `block/*`, `item/*`, `entity/*` until they compile.
  Everything else depends on this — A runs alone, first.
- **Agent B — mixins:** the 7 mixins only (§5, top row). Verifies every target against
  `/opt/mc-src/`. Highest-risk work.
- **Agent C — client:** renderers (render-state/`submit` model — copy the ported lib
  renderers), HUD overlay, config GUI.
- **Agent D — sweeper/finisher:** remaining compile errors (`tnteffects/*`, `feature/*`,
  data JSON), full `build`, then the single `runServer` smoke test (§6).

B and C run in parallel after A (disjoint files), but must NOT run Gradle
concurrently in the same checkout — B/C fix by reading errors A/D produced, or
compile strictly one at a time.

**The loop:** after D, if `build` or `runServer` still fails → collect the error list
→ spawn a fresh sweeper agent with that list (apply §9 to anything that keeps
resisting) → repeat until the server logs `Done (…)!` with no errors. After every
phase: update `PORT-STATUS.md`, commit, push. Done = server boots green, everything
pushed, `PORT-STATUS.md` lists all disabled content.


---

# Часть VII. PORT-CHEATSHEET — verified 26.2 fixes for the remaining compile errors


All mechanical yarn→Mojang renames (imports, class names, ~90 vanilla renames, method
renames) are ALREADY applied by scripts. What remains is per-file semantic work. This
sheet lists the VERIFIED fix for every recurring remaining error. Ground truth:
`/opt/mc-src/` (grep it) and `TntLib/src/main/java/luckytntlib/` (mirror it). Never invent.

## Environment
- Do NOT run gradle (the orchestrator compiles centrally). Just edit files.
- Do NOT `git commit` (orchestrator commits). Just save edits.
- Reference: `grep -rn <symbol> /opt/mc-src/` and the ported lib under `TntLib/`.

## Recurring errors → fix

1. **`Level cannot be converted to ServerLevel`** — `IExplosiveEntity#getLevel()` returns
   `Level`. Methods needing server (`sendParticles`, `EntityType.create`, structure
   `place`, `wasExploded`, `hurtServer`, worldgen) need a `ServerLevel`. Cast when you
   know it's server-side: `(ServerLevel) entity.getLevel()`; or guard:
   `if (entity.getLevel() instanceof ServerLevel level) { ... }`. TNT effects' `serverExplosion`
   runs server-side, so a cast is safe there.

2. **`no suitable method found for create(Level)`** — `EntityType#create` is now
   `create(Level, EntitySpawnReason)`. Use `type.create(level, EntitySpawnReason.MOB_SUMMONED)`.
   Add `import net.minecraft.world.entity.EntitySpawnReason;`. (Values incl. MOB_SUMMONED,
   TRIGGERED, COMMAND.)

3. **`no suitable method found for setBlock(BlockPos,BlockState)`** (2-arg) — the rename
   turned `setBlockState`→`setBlock`. The 2-arg form is now `setBlockAndUpdate(pos, state)`.
   The 3-arg `setBlock(pos, state, flags)` is correct as-is.

4. **`addParticle(..., boolean, ...)` no suitable method** — yarn's 1-boolean overload is
   gone. Mojang: `addParticle(ParticleOptions, double x,y,z, double dx,dy,dz)` (drop the
   boolean), or the two-boolean `addParticle(options, overrideLimiter, alwaysShow, x,y,z, dx,dy,dz)`.
   Simplest: delete the single boolean arg. Server-side particles → `((ServerLevel)level).sendParticles(...)`.

5. **`Optional<Integer/Double/String> cannot be converted to …`** — codec/NBT reads return
   Optional. Use the `*Or` variants on `ValueInput`: `input.getIntOr(name, def)`,
   `input.getShortOr(name, def)`, `input.getDoubleOr`, `input.getStringOr`; or `.orElse(def)`.
   Entity NBT is codec-based: `readAdditionalSaveData(ValueInput)` /
   `addAdditionalSaveData(ValueOutput)` with `output.putInt(name,v)` / `output.putShort` etc.
   Mirror `luckytntlib` entities (e.g. `PrimedLTNT`) for the exact shape.

6. **`method does not override or implement a method from a supertype`** — a vanilla/lib
   signature changed. Check the real one:
   - Items: `use()` → `InteractionResult use(Level, Player, InteractionHand)`;
     `useOnBlock`→`useOn(UseOnContext)`; tooltip →
     `appendHoverText(ItemStack, Item.TooltipContext, TooltipDisplay, Consumer<Component>, TooltipFlag)`.
   - Entity data: `initDataTracker`→`defineSynchedData(SynchedEntityData.Builder)`.
   - Blocks: `onDestroyedByExplosion`→`wasExploded(ServerLevel, BlockPos, Explosion)` (now
     needs ServerLevel). Confirm each against `/opt/mc-src`.
   - PrimedTNTEffect overrides (getBlock/getBlockState/getItem/serverExplosion/explosionTick/
     spawnParticles/…): match `TntLib/.../PrimedTNTEffect.java` exactly.

7. **`bad operand types for binary operator`** — usually a method that used to return a
   primitive now returns Optional/boxed, or a `getX()` type changed. Unbox / `.orElse()` /
   fix the type. Look at the specific line.

8. **residual `cannot find symbol`** — a rename the scripts didn't cover. `grep -rn` the
   symbol in `/opt/mc-src/` for the new name and fix the call. Common leftovers:
   `.getStepX/Y/Z` on Direction, `Blocks.` constants, `SoundEvents.` renamed constants
   (many lost the `ENTITY_`/`BLOCK_` prefix — verify), `Mth.` for math helpers.

## §9 — when a file resists (worldgen/structure especially)
Worldgen (`ConfiguredFeature`, `StructureStart`, `StructureTemplate`,
`*ConfiguredFeatures`, `ChunkGenerator`, `world.gen.*`) changed massively. If a
structure/feature spawn resists ~2 honest attempts: comment out the registration and stub
the broken body (keep original in a `/* ... */` block with
`// TODO(port-26.2): DISABLED — <reason>`), so the class compiles. Log EVERY cut in
`PORT-STATUS.md` under "Disabled content" (file, what, why). Build-green beats feature-complete.


---

# Часть VIII. Porting Guide — LuckyTNTLib + LuckyTNTMod → Minecraft 26.2 (Fabric)


> **Audience:** coding agents doing the 1.21 → 26.2 port.
> **Read section 0 before touching a single file.** Then always run the web-recheck prompt in §8 before implementing anything version-specific.
> Last verified against live Fabric docs & Minecraft Wiki: **July 2026**.

---

## 0. STOP — read this first (the facts that break naive porting)

1. **The target is `26.2`, NOT "1.26.2".** Minecraft Java changed its version scheme in 2026 to `year.drop.hotfix`. The real sequence is:
   `1.21 → 1.21.1 → 1.21.2/1.21.3 → 1.21.4 → 1.21.5 → 1.21.6/1.21.7/1.21.8 → 1.21.9/1.21.10 → 1.21.11` (last "1.x")
   `→ 26.1 (24 Mar 2026) → 26.1.1 → 26.1.2 → 26.2 (16 Jun 2026)`.
   Whenever a task says "1.26.2", it means **26.2**.

2. **Yarn and Intermediary mappings are DISCONTINUED after 1.21.11.**
   `26.1` is the **first unobfuscated** Minecraft release — the game ships with Mojang's own names at runtime. From 26.1 onward you **must** use **Mojang official mappings**.
   - ❌ DO NOT write yarn-mapped code for 26.x (`Identifier`, `MinecraftClient`, `World`, `Item.Settings`, `class_1234`, `EntityRendererFactory`, …).
   - ❌ DO NOT follow pre-2026 yarn tutorials, old MCP/Yarn wikis, or cached blog posts as if they were current.
   - ✅ Use Mojang names (`ResourceLocation`, `Minecraft`, `Level`, `Item.Properties`, `Creeper`, …).
   Yarn stays available only for **historical** (≤1.21.11) versions.

3. **Java 21 → Java 25.** Java 21 holds through 1.21.11; **Java 25 is required from 26.1**. Bump `sourceCompatibility`/`targetCompatibility` and Gradle JVM to 25, and set mixin `compatibilityLevel` accordingly.

4. **Do NOT jump straight from 1.21 to 26.2.** The correct path is staged (see §1). Each 1.21.x step carries its own hard breaks (render-state, NBT, HUD, networking). Skipping steps means debugging ~8 versions of breakage at once with no compiler to guide you.

5. **Always re-verify against the live web.** These APIs moved fast in 2025–2026 and your training data is stale. Before implementing any version-specific change, run the recheck prompt in §8. Trust official Fabric blog posts (`fabricmc.net`), Fabric docs (`docs.fabricmc.net`), and the Minecraft Wiki over anything else.

---

## 1. The mandatory staged porting path

Do these **in order**. Get a green build at each stage before advancing.

| Stage | From → To | Mappings | Java | Headline work |
|---|---|---|---|---|
| A | 1.21 → **1.21.11** | Yarn (still alive) | 21 | Absorb all 1.21.x API breaks step-by-step (render-state, model/pick, NBT-Optional, HUD/RenderPipeline/ReadView, `getEntityWorld`, networking). |
| B | 1.21.11 (Yarn) → 1.21.11 (**Mojang mappings**) | **Yarn → Mojang** | 21 | Run the mappings migration. Mixins must be reviewed by hand. |
| C | 1.21.11 → **26.1** | Mojang | **25** | Build-script overhaul (unobfuscated Loom), Fabric API renames. |
| D | 26.1 → **26.2** | Mojang | 25 | Blaze3D/OpenGL→Vulkan-safe rendering, ID-holder split, GUI relocation. |

> **Why not skip A and migrate mappings on 1.21?** Because the mappings migration tool maps *names*, not *API shapes*. All the semantic breaks (method signatures, removed methods, render-state) must be fixed while you still have Yarn's parameter names and Javadocs to read. Migrate mappings only once the code already compiles on 1.21.11.

**Library first, mod second.** `LuckyTNTMod` depends on `LuckyTNTLib`. Port and publish `LuckyTNTLib` for each target before porting the mod against it. The mod's `build.gradle` pulls the lib from JitPack (`com.github.SlimingHD:Fabric-LuckyTNTLib`).

---

## 2. Toolchain matrix (verified)

| MC | Java | Fabric Loom | Fabric Loader | Mappings |
|---|---|---|---|---|
| 1.21 / 1.21.1 | 21 | 1.7 | ~0.15.x | Yarn 1.21+build.x |
| 1.21.2 / 1.21.3 | 21 | 1.8 | 0.16.x | Yarn |
| 1.21.4 | 21 | 1.9 | 0.16.9 | Yarn |
| 1.21.5 | 21 | 1.10 | 0.16.10 | Yarn |
| 1.21.6–1.21.8 | 21 | 1.10 | 0.16.14 | Yarn |
| 1.21.9 / 1.21.10 | 21 | 1.11+ | 0.17.2+ | Yarn |
| 1.21.11 | 21 | 1.14+ | 0.18.1 | **Yarn (last)** |
| **26.1** | **25** | **1.15**, Gradle 9.4.0 | 0.18.4 | **Mojang** |
| **26.2** | **25** | **1.17**, Gradle 9.5.1 | 0.19.3 | **Mojang** |

IntelliJ **2025.3+** is required for mixins on 26.1+. Enum Extensions on 26.2 needs Loader ≥ 0.19.0.

### The 26.1 build-script overhaul (unobfuscated Loom)
When you reach stage C, `build.gradle` / `gradle.properties` change structurally:
1. `./gradlew wrapper --gradle-version latest`
2. Bump `minecraft_version`, `loader_version`, Loom, `fabric_version` in `gradle.properties`.
3. Loom plugin id: `id "fabric-loom"` → `id "net.fabricmc.fabric-loom"`.
4. **Delete the `mappings "net.fabricmc:yarn:…"` line entirely.**
5. Drop the `mod` prefix on configs: `modImplementation`→`implementation`, `modCompileOnly`→`compileOnly`, `modApi`→`api`.
6. `remapJar` → `jar` in build tasks (there is no remap step anymore).
7. Access wideners / class tweakers: change the header namespace from `named` to `official`.
8. Java compatibility → 25.
9. Nothing built for ≤1.21.11 works on 26.1, **even as compile-only** — every dependency must be 26.1+ (including LuckyTNTLib itself).

Tool: **mcsrc.dev** — Fabric's online decompiled-source viewer with mixin/AccessWidener generators. Use it to confirm exact 26.x method signatures.

---

## 3. Per-version breaking-change hit-list (grep targets)

### 1.21.2 / 1.21.3 — registry, entity render-state, results
- **`Item.Settings` / `Block.Settings` now need `.registryKey(RegistryKey<…>)`** or you get `NullPointerException: Item id not set` / `Block id not set`. Highest-frequency break in this codebase.
- Registry lookup renames: `getEntry`→`getOptional`, `entryOf`→`getOrThrow`, `getOrThrow`→`getValueOrThrow`, `getOrEmpty`→`getOptionalValue`.
- **`EntityType.Builder#build()` now requires a `RegistryKey<EntityType<?>>`.**
- **`EntityType#create(...)` now requires a `SpawnReason`** — e.g. `create(world, SpawnReason.SPAWN_ITEM_USE)`.
- Attributes lose their prefixes: `GENERIC_ATTACK_KNOCKBACK` → `ATTACK_KNOCKBACK`, etc.
- Action results unified into a single `ActionResult` (no more `TypedActionResult`; use `ActionResult.SUCCESS`, `withNewHandStack()`).
- **Entity render-state refactor (the flagship break):** `EntityRenderer<S extends EntityRenderState>`. Rewrite every renderer to:
  - `S createRenderState()`
  - `void updateRenderState(Entity, S, float tickDelta)` — copy entity fields into the state
  - `void render(S, MatrixStack, VertexConsumerProvider, int light)` — render **only** from the state (no entity access, no `getTexture()`).

### 1.21.4 — models, pick, colors
- Block entities render their block model automatically; `getRenderType()==ENTITYBLOCK_ANIMATED` override is gone.
- `fabric-rendering-v0` module removed.
- `BlockPickInteractionAware` → `PlayerPickItemEvents#BLOCK`/`#ENTITY`.
- `ItemColors` removed → item model definition JSON in `assets/<ns>/items/`.
- `FabricModelPredicateProviderRegistry`, `BuiltinItemRenderer(Registry)` removed.

### 1.21.5 — NBT Optionals, blocks, spawns
- `NbtCompound` getters return `Optional`; switch to `get*(key, default)` / `*OrEmpty`.
- `AbstractBlock#onStateReplaced` signature changed (now receives the *old* state); `DataPool`→`Pool`.
- `BiomeModificationContext#addSpawn` gained a `weight` parameter.
- Dynamic-registry datapack files need namespaced dirs: `data/<ns>/<registry>/…`.
- `SpecialBlockRendererRegistry` added.

### 1.21.6 / 1.21.7 / 1.21.8 — RenderPipeline, ReadView/WriteView
- **RenderSystem/RenderPipeline migration:** rendering split into extract + render phases; many `RenderSystem` methods removed → combine `RenderPipeline` + `RenderLayer`.
- Fabric Rendering: Material API removed; `BlockRenderLayerMap` moved to `net.fabricmc.fabric.api.client.rendering.v1.BlockRenderLayerMap` (`fabric-blockrenderlayer-v1` merged into `fabric-rendering-v1`).
- **BlockEntity/world serialization → codec-based `ReadView`/`WriteView`** instead of raw `NbtCompound`. Rewrites every `readNbt`/`writeNbt`.
- `FabricTrackedDataRegistry` for conflict-free tracked-data handlers.

### 1.21.9 / 1.21.10 — the "touches everything" renames
- **`Entity#getWorld` → `Entity#getEntityWorld`.** Grep the whole codebase.
- `OrderedRenderCommandQueue`: world rendering reworked to a submit-to-queue model.
- `MinecraftClient.IS_SYSTEM_MAC` → `SystemKeycodes.IS_MAC_OS`.
- `KeyBinding.Category.create(Identifier)` replaces string categories.
- `ResourceManagerHelper` → `ResourceLoader.get()`.

### 1.21.11 — networking, last Yarn build
- Large-packet splitter: `PayloadTypeRegistry.playS2C().registerLarge(ID, CODEC, DATA_SIZE)`.
- Recipe Synchronization API for server→client recipe sync.
- World Render Events reintroduced (extraction separated from rendering).
- **This is the last version with Yarn.** Freeze here, get green, then migrate mappings.

### HUD API evolution (spans versions — the mod uses a HUD overlay)
- `HudRenderCallback` → `HudLayerRegistrationCallback` (1.21.5, deprecated) → **`HudElementRegistry`** (1.21.6). On **26.1 `HudRenderCallback` is removed** — use `HudElementRegistry`.

### 26.1 — Fabric API renames & removals
- Removed modules: `fabric-convention-tags-v1`, `fabric-loot-api-v2`.
- `ItemGroupEvents` → `CreativeModeTabEvents` (Fabric ships an IntelliJ migration map).
- `ColorProviderRegistry` → `BlockColorRegistry`; `FluidRenderHandler` → `FluidModel`.
- Render layers auto-assigned from sprite properties — **manual render-layer registration no longer needed**.
- Recipe serializers use `MapCodec` + `StreamCodec` (no inner serializer classes).
- New `ItemStackTemplate` immutable class; new precise interaction events (`BlockEvents#USE_ITEM_ON`, `ItemEvents#USE_ON`, …).
- Villager `TradeOfferHelper` replaced by a data-driven system.
- `DimensionEvents.MODIFY_ATTRIBUTES`.

### 26.2 — graphics backend + IDs + GUI
- **Vulkan backend added; raw OpenGL calls must move to the Blaze3D API** or they break (OpenGL slated for removal).
- Reversed depth buffer; Order-Independent Transparency (new shader uniforms/defines).
- ID storage split: `BlockIds` / `BlockItemIds` / `ItemIds`; `valueLookupBuilder` removed.
- GUI/HUD relocation, e.g. `Minecraft.getInstance().setScreen(...)` → `Minecraft.getInstance().gui.setScreen(...)`.
- New entity attributes (`air_drag_modifier`, `bounciness`, `friction_modifier`, `below_name_distance`, `name_tag_distance`); entity predicates restructured.
- Beds/signs/hanging-signs use block models not entity models.
- Protocol 776, data version 4903, datapack format 107.1, resource pack format 88.0.

---

## 4. THIS codebase's specific danger zones

Layout: **LuckyTNTLib** (51 Java files) is the dependency; **LuckyTNTMod** (303 Java files, ~250 of them `tnteffects/*` = mostly pure explosion logic that rarely breaks). Sort effort by the table below.

| Area | Files | Break risk | What changes |
|---|---|---|---|
| **Entity renderers** | lib `LTNTRenderer`, `LDynamiteRenderer`, `LTNTMinecartRenderer`; mod `BombRenderer`, `AngryMinerRenderer`, `BouncingTNTRenderer` | 🔴🔴 | Full rewrite to `EntityRenderer<S extends EntityRenderState>` (1.21.2). Remove `getTexture()`. Then RenderPipeline (1.21.6) and Blaze3D/Vulkan-safety (26.2). These renderers currently use `render(entity, yaw, delta, MatrixStack, VertexConsumerProvider, light)` + `getTexture()` — both gone. |
| **Registration** | lib `RegistryHelper` (618 lines), `ItemRegistry`, `NetworkRegistry`; mod's 17 `registry/*` classes | 🔴 | `new Identifier()`→`Identifier.of()` (already needed at 1.21), then Mojang `ResourceLocation.fromNamespaceAndPath()`. Add `.registryKey(...)` to every `Item.Settings`/`Block.Settings`. `EntityType.Builder#build()` + `RegistryKey`. `EntityType#create` + `SpawnReason`. `Registries`/`Registry` lookup renames. |
| **Mixins** | lib `EntityMixin`, `FireBlockMixin`; mod `AbstractMinecartEntityMixin`, `CameraMixin`, `GameRendererMixin`, `InGameHudMixin`, `LivingEntityMixin`, `HungerManagerMixin`, `FireBlockMixin` | 🔴 | INVOKE `target=` descriptors reference exact method signatures that change and are **not** auto-migrated. Re-verify every `@Inject`/`@Redirect` target against 26.2 source (mcsrc.dev). Known fragile targets: `moveOnRail`, `renderWorld`/`loadProjectionMatrix`, `getShapeProperty`. `initDataTracker()` → `initDataTracker(DataTracker.Builder)` (1.20.5); `dataTracker.startTracking`→`builder.add`. `readNbt`/`writeNbt` → ReadView/WriteView. |
| **Entities** | lib `PrimedLTNT`, `LExplosiveProjectile`, `LTNTMinecart`, `LivingPrimedLTNT`, `LuckyTNTMinecart` | 🟠 | `initDataTracker(DataTracker.Builder)`; `getWorld`→`getEntityWorld`; NBT read/write → ReadView/WriteView; `EntityType.create` + SpawnReason. |
| **Items** | lib `LDynamiteItem`, `LTNTMinecartItem`, `LuckyDynamiteItem`, `TNTConfigItem` | 🟠 | `use()` returns `ActionResult` not `TypedActionResult` (1.21.2); `appendTooltip(stack, TooltipContext, TooltipType, list, …)` signature changed and `TooltipContext` moved package; `Item.Settings`→`Item.Properties` (26.1). |
| **Explosion engine** | lib `ImprovedExplosion` (607 lines), `ExplosionHelper` | 🟠 | Reaches into vanilla `Explosion` internals and world block/entity access; audit against 26.2 `Explosion`/`Level` APIs and `getEntityWorld`. |
| **Config GUI** | lib `ConfigScreen`, `ConfigScreenListScreen`, widgets; mod `ConfigScreen`, `ConfigScreen2` | 🟠 | Screen/widget constructor and `render()` signatures shift with the rendering rework; `setScreen` relocation (26.2). |
| **HUD overlay** | mod `client/overlay/OverlayTick`, `InGameHudMixin` | 🟠 | `HudRenderCallback` removed (26.1) → `HudElementRegistry`. |
| **Worldgen data** | `src/generated/data/luckytntmod/worldgen/*` | 🟢 | Datapack dir-layout tweak (1.21.5 namespaced dirs); regenerate via datagen. |
| **Networking** | lib `network/*`, `ClientNetworkRegistry`; mod `NetworkRegistry` | 🟢 | Already on modern `CustomPayload` + `PacketCodec` in the 1.21 build. Low risk; just re-namespace to Mojang and re-verify `CustomPayload.Id`. |
| **`tnteffects/*`** | ~250 mod files | 🟢 | Pure explosion logic on top of lib abstractions. Recompiles once the lib API is stable; touch only where they hit `getWorld`, block/entity APIs, or `DamageSource`. |

**License note:** LuckyTNTLib is **CC0-1.0** (public domain) — free to copy/fork/modify with no attribution constraints. LuckyTNTMod's own `fabric.mod.json` says "All Rights Reserved", so keep mod changes within this repo/branch.

---

## 5. Mapping name cheat-sheet (Yarn → Mojang, for stage B onward)

| Yarn | Mojang |
|---|---|
| `Identifier` | `ResourceLocation` |
| `MinecraftClient` | `Minecraft` |
| `World` / `ServerWorld` | `Level` / `ServerLevel` |
| `WorldAccess` / `BlockView` | `LevelAccessor` / `BlockGetter` |
| `Item.Settings` | `Item.Properties` |
| `Block.Settings` / `AbstractBlock.Settings` | `BlockBehaviour.Properties` |
| `CreeperEntity`, `TntEntity`, `LivingEntity` | `Creeper`, `PrimedTnt`, `LivingEntity` |
| `Text` | `Component` |
| `NbtCompound` | `CompoundTag` |
| `PlayerEntity` / `ServerPlayerEntity` | `Player` / `ServerPlayer` |
| `Hand` / `ItemStack` | `InteractionHand` / `ItemStack` |
| `Vec3d` / `BlockPos` | `Vec3` / `BlockPos` |
| `EntityRendererFactory.Context` | `EntityRendererProvider.Context` |
| `MatrixStack` | `PoseStack` |
| `VertexConsumerProvider` | `MultiBufferSource` |

Mojang mappings **lack parameter names and Javadocs**. Read the Yarn source for intent *before* stage B, keep notes, then migrate. Migration tools: Loom `migrateMappings` task (no Kotlin support) or the **Ravel** IntelliJ plugin (Kotlin + Mixin friendly — what Fabric API itself used). **Neither handles Mixins reliably — review those by hand.**

---

## 6. Rules for agents working on this port

- **DO** verify every version-specific API against the live web (§8) before writing it. Prefer `fabricmc.net`, `docs.fabricmc.net`, `minecraft.wiki`, `mcsrc.dev`.
- **DO** work one stage at a time (§1) and get a green build (`./gradlew build`) before advancing.
- **DO** port `LuckyTNTLib` before `LuckyTNTMod`.
- **DON'T** use Yarn names or Intermediary (`class_XXXX`) for any 26.x work.
- **DON'T** trust pre-2026 tutorials, StackOverflow, or your own training memory for signatures — they predate the 26.x rewrites.
- **DON'T** skip intermediate 1.21.x versions to "save time" — the breaks compound.
- **DON'T** hand-migrate mappings before the code compiles on 1.21.11.
- **DON'T** invent method names. If unsure of a 26.2 signature, look it up on mcsrc.dev or grep the decompiled source; state the source in your change.
- **DON'T** make raw OpenGL/`GL11` calls for 26.2 — use Blaze3D.
- When a change is ambiguous or architectural (rendering rewrite, mapping strategy), **stop and ask** rather than guess.

---

## 7. Definition of done (per stage)

- Stage A: compiles & runs on 1.21.11 with Yarn; all TNT/dynamite render, throw, and explode in-game.
- Stage B: compiles on 1.21.11 with Mojang mappings; mixins verified by hand; parity with A.
- Stage C: compiles & runs on 26.1 with Java 25 and the new Loom build; Fabric API renames resolved.
- Stage D: compiles & runs on 26.2; no raw-GL warnings; renderers correct under Vulkan and OpenGL; ID-holder split applied.

---

## 8. Web-recheck prompt (paste into any agent before it implements a version-specific change)

```
You are porting a Fabric mod across Minecraft versions in the 1.21 → 26.2 range.
Your training data is STALE for this range — do not rely on memory. Before you
write or change any version-specific code you MUST verify it against LIVE 2025–2026
sources.

Context you must hold:
- Minecraft uses year.drop versioning now: after 1.21.11 comes 26.1 then 26.2.
  "1.26.2" is not real — it means 26.2.
- Yarn/Intermediary mappings are DEAD after 1.21.11. 26.1+ is unobfuscated and uses
  Mojang official mappings. Never emit yarn names (Identifier, MinecraftClient,
  World, Item.Settings, class_XXXX) for 26.x code — use Mojang names
  (ResourceLocation, Minecraft, Level, Item.Properties, ...).
- Java 25 is required from 26.1 (was 21).

For the specific API you are about to touch, do this:
1. WebSearch for the exact Fabric blog post / Fabric doc for the target version
   (site:fabricmc.net or site:docs.fabricmc.net) and read the relevant section.
2. Cross-check the exact class/method SIGNATURE on mcsrc.dev (decompiled 26.x source)
   or the Minecraft Wiki version page (minecraft.wiki/w/Java_Edition_26.2).
3. Confirm whether the symbol was renamed, moved package, changed signature, or
   removed between your source version and the target version.
4. Only then write the code, and cite the source URL you verified against in your
   summary. If you cannot find a live source, say so and STOP — do not guess a
   signature.

Authoritative sources, in priority order:
- https://fabricmc.net/  (per-version "Fabric for Minecraft X" blog posts)
- https://docs.fabricmc.net/develop/porting/  and  /develop/porting/mappings/
- https://mcsrc.dev/  (decompiled source + mixin/AccessWidener generator)
- https://minecraft.wiki/w/Java_Edition_26.2  (and 26.1)
```

---

## 9. Sources (verified July 2026)

- Version numbering: https://www.minecraft.net/en-us/article/minecraft-new-version-numbering-system
- Fabric per-version blogs: https://fabricmc.net/2024/05/31/121.html · /2024/10/14/1212.html · /2024/12/02/1214.html · /2025/03/24/1215.html · /2025/06/15/1216.html · /2025/09/23/1219.html · /2025/12/05/12111.html · /2026/03/14/261.html · /2026/06/15/262.html
- Unobfuscation announcement: https://fabricmc.net/2025/10/31/obfuscation.html
- Porting to 26.1: https://docs.fabricmc.net/develop/porting/
- Yarn → Mojang mappings migration: https://docs.fabricmc.net/develop/porting/mappings/
- Block Entity Renderers: https://docs.fabricmc.net/develop/blocks/block-entity-renderer
- Damage Types: https://docs.fabricmc.net/develop/entities/damage-types
- MC Wiki 26.1 / 26.2: https://minecraft.wiki/w/Java_Edition_26.1 · https://minecraft.wiki/w/Java_Edition_26.2
- Java version table: https://modready.gg/guides/minecraft-java-version-requirements

### Known gaps to re-verify during the port
- Exact 26.1.1 / 26.1.2 hotfix dev-diffs (assume they inherit 26.1's toolchain).
- Damage-source changes 1.21.2→26.2 (data-driven model is stable since 1.19.4; no 26.x note found — verify if explosion damage code misbehaves).
- Low-level `BufferBuilder`/`VertexConsumer`/`RenderType` signature diffs for Blaze3D — pull from mcsrc.dev if doing custom immediate-mode rendering.
- The full Fabric 26.1 rename catalog / IntelliJ migration map — consult before any mass find/replace.
<!-- BUNDLE-APPENDIX-START -->

---

# Часть IX. Промпты для агентов

Отдельными файлами — в `prompts/`. Порядок: оркестратор нанимает A, затем параллельно
B/C/D, затем интегратора, затем свипера по списку ошибок.

---

## Промпт оркестратора

Верхнеуровневый агент. Ставит окружение, замораживает контракты, нанимает агентов, коммитит.
Пользователя в цикле нет — вопросов не задаёт, решения принимает по плану и логирует.

Плейсхолдеры: `<МОД>` · `<КИТ>` (путь к этому репозиторию) · `<ПРОЕКТ>` (папка порта, например
`<РЕПО>/26.2`) · `<ИСХОДНИК>` (снапшот исходной версии, только чтение) · `<ВЕТКА>`.

---

```
Ты оркестратор порта <МОД> на Fabric / Minecraft 26.2. Работаешь автономно: вопросов
пользователю не задаёшь, решения принимаешь сам и записываешь в PORT-STATUS.md.

Закон порта — <КИТ>/guides/PORT-ANY-MOD-26.2.md. Выше него по авторитету только
декомпилированные исходники игры в /opt/mc-src и уже портированные 26.2-моды на диске.
Читай закон целиком один раз, дальше грепай, не перечитывай.

ИСХОДНЫЕ ДАННЫЕ
- Исходник (ТОЛЬКО ЧТЕНИЕ, не редактировать): <ИСХОДНИК>
- Проект порта (сюда пишем): <ПРОЕКТ>
- Ветка: <ВЕТКА>. Работать только на ней, `git push -u origin <ВЕТКА>`.
  При сетевой ошибке до 4 ретраев с бэкоффом 2/4/8/16 с. PR не открывать.

ШАГ 0 — делаешь сам, никого не нанимая
1. Окружение (§3 закона): <КИТ>/gradle-dist/install.sh → /opt/gradle-9.6.1 и OpenJDK 25.
   `./gradlew` не работает: прокси отдаёт 403 на ассеты GitHub-релизов. Любая сборка:
     cd <ПРОЕКТ> && JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64 \
       /opt/gradle-9.6.1/bin/gradle <task> --no-daemon 2>&1 | tee /tmp/errors.txt
   ОДНА инвокация Gradle на чекаут одновременно: две параллельные портят кэш Loom.
2. `genSources` → /opt/mc-src. Делается ОДИН раз, дальше только grep. Это твоя зона:
   агенты её не трогают и не перегенерируют.
3. Разведка (§4): сколько java-файлов, какие внешние импорты и сколько их, есть ли миксины,
   есть ли датаген, есть ли объявленные зависимости от других модов. Это дёшево и решает всё
   остальное.
4. Маршрут (§2): сколько осей надо пройти — версия игры, лоадер, мэппинги. Если у апстрима
   есть своя ветка на 26.x, брать её базой: чужими руками пройденная ванильная ось стоит
   больше, чем свежесть мод-фиксов.
5. Контракты (§5) — заморозить ДО найма агентов, поимённо, в PORT-STATUS.md. Минимум:
   форма регистрации, entrypoint'ы, сеть, владение общими файлами, формат кастомных JSON.
   Контракт нужен там, где два агента иначе договорятся по-разному.
6. PORT-STATUS.md по шаблону <КИТ>/templates/PORT-STATUS-TEMPLATE.md. Ведёшь его ТОЛЬКО ты.
7. Механические ренеймы (§7) — скриптом из <КИТ>/scripts/, отдельным коммитом, до ручных правок.
8. Скелет <ПРОЕКТ>/: build.gradle, settings.gradle, gradle.properties, src/. Пины версий —
   §3 закона, строки `mappings` нет: 26.1+ необфусцирован.
9. Commit + push.

ФАЗЫ
- Фаза 1: агент A один (<КИТ>/prompts/01-AGENT-A-core.md). Done: build-файлы на 26.2,
  скелет и регистрация компилятся. Между фазами: compileJava сам, коммит, пуш.
- Фаза 2: агенты B, C, D параллельно, файлы не пересекаются, Gradle им запрещён.
  Ты между их отчётами гоняешь compileJava и раздаёшь ошибки по зонам.
- Фаза 3: интегратор (05) — compileJava → build → runDatagen → ОДИН runServer.
- Цикл: пока красное — свежий sweeper (06) с конкретным списком ошибок и правом на §10.
  Каждый цикл обязан либо уменьшить число ошибок, либо применить срез. МАКСИМУМ 4 цикла;
  после четвёртого — остановиться и записать «не доведено» с остатком в Verification.
- Фаза 4: клиент проверяет человек на живом клиенте. Порядок проверки написать в PORT-GAPS.md.

ЧТО ДЕЛАЕШЬ САМ, А НЕ ОТДАЁШЬ АГЕНТУ
- Gradle между фазами и раздачу ошибок по зонам.
- Все коммиты и пуши.
- Ведение PORT-STATUS.md и PORT-GAPS.md из отчётов агентов.
- Allowlist для строк /ERROR] заведомо не из мода (ваниль, сторонние библиотеки),
  с обоснованием в Verification — иначе критерий «ноль ERROR» невыполним и цикл не кончится.

НАЙМ
Промпт агенту собираешь из <КИТ>/prompts/0N-*.md: подставляешь точный список файлов,
пути к референсным модам на диске и done-критерий. Не выдавай агенту больше, чем ему нужно:
sweeper'у — только список ошибок, §10 и правило про grep по /opt/mc-src.

ПРИЁМКА (§13)
  compileJava → build → runDatagen (если есть датаген) → runServer
DONE = сервер доходит до `Done (N.NNNs)! For help, type "help"` и ноль строк /ERROR]
вне allowlist. Клиент этим НЕ проверяется — в контейнере нет дисплея; так и записать,
не выдавая компиляцию за проверку.

ПОСЛЕ ЗЕЛЁНОГО
Финальный коммит и пуш. PORT-STATUS.md со всеми чекбоксами, всеми отклонениями от контрактов
и всеми срезами. PORT-GAPS.md с полной таблицей: что видно в игре, как чинить, приоритет.
Сверка: `grep -rn "TODO(port-26.2)" src | wc -l` == числу строк в PORT-GAPS.md.
Всё, чего не было в порт-ките и что пришлось выяснять самому, — в FINDINGS-*.md по шаблону
<КИТ>/templates/FINDINGS-TEMPLATE.md. Это следующий кит для следующего порта.
```

---

## Что чаще всего ломает именно оркестратора

- **Две параллельные инвокации Gradle** на одном чекауте портят кэш Loom. Один Gradle — твой.
- **Перегенерация `/opt/mc-src`** стоит десятки минут и не даёт ничего нового.
- **Агент, которому разрешили и Gradle, и параллельную работу.** Gradle есть только у A (пока он
  один) и у интегратора.
- **Нежёсткие контракты.** Если форма регистрации не зафиксирована до старта, B и C напишут разные
  и встретятся в фазе 3 — это самый дорогой из возможных конфликтов.
- **Бесконечный найм.** Четыре свипа — потолок. Дальше честная запись «не доведено».

---

## Промпт агента A — ядро, сборка, регистрация

Первая фаза, работает один. От него зависят все остальные, поэтому ему единственному из рабочих
агентов разрешён Gradle: в чекауте больше никого нет.

---

```
Ты портируешь <МОД> на Fabric / Minecraft 26.2. Твоя роль: A — ядро, сборка, регистрация.
Ты в чекауте один, Gradle тебе РАЗРЕШЁН. Коммитить и пушить — нельзя, это делает оркестратор.

ЧИТАТЬ В ЭТОМ ПОРЯДКЕ И НИЧЕГО СВЕРХ
1. <КИТ>/guides/PORT-ANY-MOD-26.2.md — §1 (факты), §8 (карта API), §9 (правила),
   §10 (правило отключения). Не перечитывай файл — грепай.
2. <КИТ>/guides/NOTES-A.md — пофайловые рецепты твоей зоны.
3. <ПРОЕКТ>/PORT-STATUS.md — контракты и твой список файлов. Читать можно, ПИСАТЬ НЕЛЬЗЯ.

ТВОИ ФАЙЛЫ (редактировать ТОЛЬКО их)
<точный список: build.gradle, settings.gradle, gradle.properties, fabric.mod.json,
 <Мод>.java, <Мод>Client.java, ModBlocks, ModItems, ModBlockEntityTypes, ModContainerTypes,
 ModRecipeTypes/Serializers, ModDataComponents, ModTags, accesswidener, раскладка ресурсов>

РЕФЕРЕНС, В ПОРЯДКЕ ПРИОРИТЕТА
1. <портированный 26.2-мод на диске> — там та же задача уже решена, копируй форму;
2. /opt/mc-src — декомпилированный 26.2, ТОЛЬКО grep, никогда не перегенерировать;
3. Fabric docs — для концепций, не для сигнатур.

ЖЁСТКИЕ ПРАВИЛА
- Ни одной сигнатуры «по памяти»: подтверждай grep-ом по /opt/mc-src или строкой из референса.
- Никаких yarn-имён (MinecraftClient, World, NbtCompound, Text, Vec3d, DrawContext, Item.Settings,
  class_XXXX), никакого ResourceLocation, никакого Identifier.of.
  Класс — net.minecraft.resources.Identifier, фабрика — Identifier.fromNamespaceAndPath(...).
- Сопротивляется после двух честных попыток → §10: отключить, оригинал сохранить рядом
  в комментарии, залогировать. Не удалять код.
- Если /opt/mc-src противоречит инструкции — прав он; сделай по нему и скажи в отчёте.
- Правку в чужом файле не делаешь — пишешь о ней в отчёте.
- Вопросов пользователю не задавать.

ЧТО ИЗВЕСТНО ЗАРАНЕЕ ПРО ТВОЮ ЗОНУ (проверено на портах, не изобретай заново)

Сборка
- Строки `mappings` в build.gradle НЕТ: 26.1+ необфусцирован, Yarn мёртв.
- Java 25, Gradle 9.x, Loom 1.17.x. `./gradlew` не работает (403), только /opt/gradle-9.6.1.
- `modImplementation` в Loom 1.17 на 26.2 не существует — ремапить нечего. Чужой мод
  подключается как `implementation files("libs/<мод>.jar")`; Fabric Loader находит его
  по fabric.mod.json на classpath.
- AccessTransformer → AccessWidener: заголовок `official` (имена Mojang), разделитель — табуляция,
  wildcard'ов нет — раскрывать построчно. Loom ВАЛИТ сборку на несуществующем члене, поэтому
  мёртвые строки удалять, а не комментировать внутри списка.

Регистрация
- `DeferredRegister`/`DeferredHolder` заменяются вызовом `Registry.register` за статическим
  хелпером, возвращающим `Supplier<T>` — тогда все существующие `.get()` по коду не трогаются.
- `Item.Properties` обязан получить `.setId(ResourceKey<Item>)`, а `BlockBehaviour.Properties` —
  `ResourceKey<Block>` ДО конструктора `BlockBehaviour`. Если блоки строят Properties внутри
  собственных безаргументных конструкторов — дешевле миксин на `BlockBehaviour$Properties`,
  чем правка каждого блока (это правка в чужих файлах, которую тебе делать нельзя).
- Ванильные `ItemStack#get/set` не имеют `Supplier`-перегрузок, которые давал NeoForge. Если по
  коду есть и `TYPE.get()`, и `stack.set(TYPE, …)` — сделай тип реестра реализующим и
  `DataComponentType<D>`, и `Supplier<DataComponentType<D>>`: это оставляет оба вида вызовов
  компилируемыми без правок в чужих файлах.

Entrypoint'ы и события
- `ModInitializer` + `ClientModInitializer` (+ `fabric-datagen`, если есть датаген) в
  fabric.mod.json. Аннотированной шины нет: `@EventBusSubscriber`/`@SubscribeEvent` удаляются,
  логика переезжает в Fabric-колбэки, регистрируемые из соответствующего entrypoint.
- `@OnlyIn(Dist.CLIENT)` → `@Environment(EnvType.CLIENT)`, НЕ удаление: Fabric Loader физически
  вырезает помеченные члены, без этого dedicated server падает NoClassDefFoundError.
- Всё, что резолвит реестр, регистрируется там, где реестр уже существует. Колбэки раньше
  `SERVER_STARTING` срабатывают слишком рано.

Данные
- Результат рецепта — `ItemStackTemplate`, а не `ItemStack`: иначе рецепты молча не существуют
  (`Item … does not have components yet`), и в консоли не будет ни одной ошибки.
- Ингредиент в JSON 26.2 — плоская строка: `"minecraft:iron_ingot"` или `"#minecraft:logs"`.
  Рукописные рецепты датаген не поймает — проверить руками все.
- `CreativeModeTab.Builder#withTabsBefore` не существует; порядок модовых вкладок задаёт
  fabric-creative-tab-api-v1 по порядку регистрации.

DONE-КРИТЕРИЙ
<конкретно: например «<ПРОЕКТ> собирается как Fabric-проект, compileJava доходит до зоны B/C/D,
оставшиеся ошибки — только `cannot find symbol` на чужие классы; fabric.mod.json валиден»>

ОТЧЁТ (формат — <КИТ>/templates/AGENT-REPORT-TEMPLATE.md)
Что сделано; что чем подтверждено (пути и строки); что отключено и почему; какие правки нужны
в чужих файлах; какие сигнатуры пришлось изменить против контракта и почему; всё новое,
чего не было в ките, — отдельным блоком для FINDINGS.
```

---

## Промпт агента B — блоки, предметы, логика мира, сеть

Вторая фаза, параллельно с C и D. Gradle запрещён: проверка типов — скриптом.
Если зона большая, делится на B1 (сеть, события, команды) и B2 (логика мира) — списки файлов
не пересекаются, промпт один и тот же.

---

```
Ты портируешь <МОД> на Fabric / Minecraft 26.2. Твоя роль: B — блоки, предметы, блок-сущности,
логика мира, сеть, команды. Gradle тебе ЗАПРЕЩЁН: его гоняет оркестратор, две параллельные
инвокации портят кэш Loom. Коммитить и пушить нельзя.

ЧИТАТЬ В ЭТОМ ПОРЯДКЕ И НИЧЕГО СВЕРХ
1. <КИТ>/guides/PORT-ANY-MOD-26.2.md — §1, §8, §9, §10. Грепай, не перечитывай.
2. <КИТ>/guides/NOTES-B.md — пофайловые рецепты твоей зоны, включая таблицу мёртвых
   NeoForge-хуков блоков и предметов.
3. <ПРОЕКТ>/PORT-STATUS.md — контракты (особенно контракт сети) и твой список файлов.
   Читать можно, ПИСАТЬ НЕЛЬЗЯ.

ТВОИ ФАЙЛЫ (редактировать ТОЛЬКО их)
<точный список. Границы проводятся ПО ФАЙЛАМ, а не по пакетам: всё *Model*/*Renderer*/*Screen*/
 Color* принадлежит агенту C, где бы оно ни лежало, даже внутри твоих пакетов>

ПРОВЕРКА ТИПОВ БЕЗ GRADLE
  <КИТ>/scripts/typecheck.sh <твои,пакеты>
Берёт jar из loom-кэша проекта. Если кэша ещё нет — скрипт предупредит, и тогда
«has private access» на расширенных AccessWidener'ом членах будет ложным срабатыванием.

РЕФЕРЕНС, В ПОРЯДКЕ ПРИОРИТЕТА
1. <портированный 26.2-мод на диске>; 2. /opt/mc-src (только grep); 3. Fabric docs — для
концепций, не для сигнатур.

ЖЁСТКИЕ ПРАВИЛА
- Ни одной сигнатуры «по памяти»: grep по /opt/mc-src или строка из референса.
- Никаких yarn-имён, никакого ResourceLocation, никакого Identifier.of.
- Два честных подхода — и §10: отключить, оригинал сохранить рядом в комментарии,
  залогировать `// TODO(port-26.2): DISABLED — <причина одной строкой>`. Код не удалять.
- Правку в чужом файле не делаешь — пишешь о ней в отчёте.
- Вопросов пользователю не задавать.

ЧТО ИЗВЕСТНО ЗАРАНЕЕ ПРО ТВОЮ ЗОНУ

Сеть
- Payload — `CustomPacketPayload` + `StreamCodec`, регистрация через
  `PayloadTypeRegistry.playS2C()/playC2S()`, приём — `ServerPlayNetworking`/`ClientPlayNetworking`.
- `PacketDistributor` → `PlayerLookup` (`tracking`, `around`, `world`).
- Точка входа сети ровно одна и объявлена контрактом: `register()` из общего entrypoint,
  `registerClient()` из клиентского. Сам entrypoint — файл агента A, ты его не трогаешь.

Мёртвые NeoForge-хуки — их нет ни в ванили, ни во Fabric, лечатся только §10 или миксином
на вызывающую сторону; проверь каждый grep-ом, прежде чем городить обход:
- `getExplosionResistance(state, level, pos, explosion)` и `getSoundType(state, level, pos, entity)`
  — позиционных перегрузок нет, значит блок-сущность не прочитать;
- `shouldDisplayFluidOverlay`, `rotate(state, level, pos, rotation)`;
- `IItemExtension#verifyComponentsAfterLoad` (свой DFU предметов), `getHighlightTip`,
  `getCraftingRemainingItem`/`hasCraftingRemainingItem`;
- capability-API целиком: `IItemHandler`, `ItemStackHandler`, `RegisterCapabilities`.
  `fabric-transfer-api-v1` несовместим по семантике — ванильный `Container` честнее.

Прочее
- `ValueInput`/`ValueOutput` вместо прямой работы с `CompoundTag` в блок-сущностях и сущностях.
- `RenderDataBlockEntity#getRenderData()` — замена `ModelData` как канала данных к рендеру.
- `@OnlyIn(Dist.CLIENT)` → `@Environment(EnvType.CLIENT)`, не удаление.
- `level.markAndNotifyBlock(...)` был NeoForge — `sendBlockUpdated(...)`; проверь, что рядом уже
  нет полноценного `setBlock(pos, state, UPDATE_FLAG)`, который и так всё рассылает.
- Свой `ArgumentType` в командах требует регистрации `ArgumentTypeInfo`, иначе дерево команд
  не сериализуется клиенту. Дешевле `StringArgumentType.word()` + `suggests(...)`.

DONE-КРИТЕРИЙ
<конкретно: например «ноль ошибок в зоне B при typecheck.sh; ноль вхождений net.neoforged
в твоих файлах; сеть подключается двумя методами по контракту»>

ОТЧЁТ (формат — <КИТ>/templates/AGENT-REPORT-TEMPLATE.md)
Что сделано; что чем подтверждено (пути и строки); что отключено по §10 и почему; какие правки
нужны в чужих файлах; отклонения от контрактов; всё новое — отдельным блоком для FINDINGS.
```

---

## Промпт агента C — клиент, модели, рендер, GUI

Вторая фаза, параллельно с B и D. Gradle запрещён. Самая дорогая зона диапазона 1.21 → 26.2:
модельный конвейер и immediate-mode рендер переписаны целиком, а миксины не мигрирует ни один
инструмент.

---

```
Ты портируешь <МОД> на Fabric / Minecraft 26.2. Твоя роль: C — клиент: рендереры, модели,
экраны, HUD, цвета, кейбинды, миксины. Gradle тебе ЗАПРЕЩЁН. Коммитить и пушить нельзя.

ЧИТАТЬ В ЭТОМ ПОРЯДКЕ И НИЧЕГО СВЕРХ
1. <КИТ>/guides/PORT-ANY-MOD-26.2.md — §1, §8, §9, §10. Грепай, не перечитывай.
2. <КИТ>/guides/NOTES-C.md — рецепты твоей зоны целиком, включая «модель, перетекстурирующаяся
   из блок-сущности».
3. <ПРОЕКТ>/PORT-STATUS.md — контракты (особенно формат кастомных модельных JSON) и твой
   список файлов. Читать можно, ПИСАТЬ НЕЛЬЗЯ.

ТВОИ ФАЙЛЫ (редактировать ТОЛЬКО их)
<точный список. Твоё — всё *Model*/*Renderer*/*Screen*/Color*/*Hud*, ГДЕ БЫ ОНО НИ ЛЕЖАЛО,
 включая файлы внутри геймплейных пакетов>

ПРОВЕРКА ТИПОВ БЕЗ GRADLE
  <КИТ>/scripts/typecheck.sh <твои,пакеты>
Известное ложное срабатывание без loom-кэша: «has private access» на членах, открытых
AccessWidener'ом. Сверяйся с <ПРОЕКТ>/src/main/resources/<мод>.accesswidener.

РЕФЕРЕНС, В ПОРЯДКЕ ПРИОРИТЕТА
1. <портированный 26.2-мод на диске> — клиентская часть; 2. /opt/mc-src (только grep);
3. javap по джарникам fabric-api в /root/.gradle/caches/modules-2/files-2.1/net.fabricmc.fabric-api/
   — единственный способ узнать форму Fabric API, которой нет ни в ванили, ни в референсе.

ЖЁСТКИЕ ПРАВИЛА
- Ни одной сигнатуры «по памяти». Тренировочные данные по диапазону 1.21.2 → 26.2 устарели.
- Никаких yarn-имён (DrawContext, TextRenderer, MatrixStack), никакого ResourceLocation.
- Два честных подхода — и §10: отключить, оригинал сохранить рядом, залогировать.
  Клиентская визуалка ниже серверного геймплея по приоритету: отключить рендер — законно.
- Правку в чужом файле не делаешь — пишешь в отчёте.
- Вопросов пользователю не задавать.

ЧТО ИЗВЕСТНО ЗАРАНЕЕ ПРО ТВОЮ ЗОНУ

Модели
- `BakedModel` → `BlockStateModel`; `BakedModelWrapper`, `IUnbakedGeometry`, `ItemOverrides`
  удалены.
- `IGeometryLoader` → Fabric `ModelLoadingPlugin` (`modifyBlockModelAfterBake`). Ключ в JSON —
  `fabric:type`, а НЕ `loader`; ванильный загрузчик ключ `loader` просто игнорирует.
- `ModelData` → `RenderDataBlockEntity#getRenderData()`. Перетекстурирование переезжает
  с bake-time на render-time: свой `BlockStateModel`-враппер поверх FRAPI `emitQuads`.
- `IQuadTransformer` → `QuadEmitter`. `ChunkRenderTypeSet` → слой задаётся на каждом квадре.
- Item-модели с 1.21.4 — data-driven: `ItemProperties.register(...)` и
  `ItemBlockRenderTypes.setRenderLayer(...)` не существуют, это теперь задача датагена
  (item model definitions, `minecraft:model` / `minecraft:select`, `"render_type"` в модели блока).

Рендер
- Immediate-mode буферов нет: `Tesselator`, `BufferUploader`, `RenderType#draw(MeshData)`,
  `VertexBuffer`, `ShaderInstance`, `RenderSystem.applyModelViewMatrix`, `GlStateManager.BLEND`,
  `RenderSystem.blendFunc/enableBlend` удалены. Blend — свойство иммутабельного `RenderPipeline`.
- `RenderStateShard` и `CompositeState.builder()` удалены; единственная фабрика —
  `RenderType.create(String, RenderSetup)` поверх `RenderPipeline`.
- `RenderLevelStageEvent` — NeoForge; во Fabric стадий нет, порядок задаёт `RenderType`,
  точки входа — `LevelRenderEvents` / `SubmitNodeCollection`.
- `BlockEntityWithoutLevelRenderer` и `IClientItemExtensions#getCustomRenderer` мертвы:
  предметный рендер — `SpecialModelRenderer` через `"minecraft:special"` в item-модели.
- `BlockColor`/`ItemColor` удалены из ванили; tintIndex — индекс в `List<BlockTintSource>`.

GUI и ввод
- `DrawContext` → `GuiGraphics`, `TextRenderer` → `Font`, виджеты → `client.gui.components.*`,
  лэйауты → `client.gui.layouts.*`.
- Модификаторов и контекстов конфликта у кейбиндов нет: `KeyModifier.SHIFT` и
  `IKeyConflictContext` — NeoForge. Комбинацию перевешивать на отдельную клавишу,
  контекст восстанавливать проверкой в обработчике.

Миксины
- Зона наивысшего риска: `@Inject`/`@Redirect`/`@ModifyVariable` ссылаются на точные имена и
  дескрипторы, которые не мигрирует ни один инструмент. Каждый target подтверждай grep-ом
  по /opt/mc-src. Миксин не исполняется на компиляции — что он применился, видно только в рантайме.
- Прежде чем писать миксин, проверь, нет ли настоящего Fabric API: `AtlasRegistry`,
  `PictureInPictureRendererRegistry`, `HudElementRegistry`, `ClientHotbarScrollEvents`,
  `ResourceLoader`, `KeyMappingHelper`, `BuiltInBlockModelsCallback`. Один из портов закрыл
  всю клиентскую зону вообще без миксинов.

DONE-КРИТЕРИЙ
<конкретно: например «client/** компилится начисто; вердикт по модельному конвейеру вынесен
и записан; все отключения залогированы»>

ОТЧЁТ (формат — <КИТ>/templates/AGENT-REPORT-TEMPLATE.md)
Что сделано; что чем подтверждено (пути и строки); что отключено и что при этом видно в игре;
какие правки нужны в чужих файлах; отклонения от контрактов; всё новое — блоком для FINDINGS.
Отдельно: что из твоей зоны НЕВОЗМОЖНО проверить без дисплея — это идёт в чек-лист человеку.
```

---

## Промпт агента D — датаген

Вторая фаза, параллельно с B и C. Отдельная роль появляется, когда у мода есть свои генераторы
данных. Главный рычаг: уже закоммиченный в исходнике сгенерированный JSON — это **оракул**,
против которого диффится выход, поэтому у этой роли есть объективный критерий готовности.

---

```
Ты портируешь <МОД> на Fabric / Minecraft 26.2. Твоя роль: D — датаген. Gradle тебе ЗАПРЕЩЁН
(его гоняет оркестратор), коммитить и пушить нельзя.

ЧИТАТЬ В ЭТОМ ПОРЯДКЕ И НИЧЕГО СВЕРХ
1. <КИТ>/guides/PORT-ANY-MOD-26.2.md — §1, §9, §10. Грепай, не перечитывай.
2. <КИТ>/guides/NOTES-A.md — раздел про замену NeoForge-датагена на Fabric и item-модели 1.21.4+.
3. <ПРОЕКТ>/PORT-STATUS.md — контракты (особенно формат кастомных модельных JSON) и твой
   список файлов. Читать можно, ПИСАТЬ НЕЛЬЗЯ.

ТВОИ ФАЙЛЫ
<datagen/** целиком + собственный entrypoint datagen/<Мод>DataGenerator.java>

ОРАКУЛ
<ПУТЬ>/generated/** — сгенерированный JSON исходной версии, уже закоммиченный. Твой выход
диффится против него: расхождение — это либо твоя ошибка, либо осознанное изменение формата
26.2, и тогда оно идёт в отчёт со ссылкой на кодек из /opt/mc-src.
Если этот JSON уже скопирован в ресурсы, мод укомплектован контентом БЕЗ запуска датагена —
красный runDatagen не блокирует зелёную сборку, но и не освобождает тебя от работы.

ЖЁСТКИЕ ПРАВИЛА
- Формат JSON подтверждается кодеком из /opt/mc-src, а не памятью и не туториалом.
- Никаких yarn-имён, никакого ResourceLocation.
- Два честных подхода — и §10, с логированием.
- Уже скопированные 1:1 JSON-данные не редактировать без явной причины; причина — в отчёт.
- Вопросов пользователю не задавать.

ЧТО ИЗВЕСТНО ЗАРАНЕЕ ПРО ТВОЮ ЗОНУ
- Точка входа — `fabric-datagen` в fabric.mod.json + `fabricApi.configureDataGeneration` в
  build.gradle (файлы агента A, ты их не трогаешь; нужна правка — в отчёт).
- Провайдеры: `FabricBlockLootTableProvider`, `FabricTagProvider`, `FabricModelProvider`,
  `FabricRecipeProvider`, `FabricLanguageProvider` — сигнатуры сверять по javap/референсу.
- `ExistingFileHelper` не существует: проверки «текстура на месте» нет вообще. Следствие —
  датаген может молча выпустить модель, ссылающуюся на отсутствующую текстуру.
- Валидация тегов строже: тег, ссылающийся на отсутствующий элемент, валит весь файл целиком
  (`missing following references`). `#minecraft:non_flammable_wood` — только item-тег;
  блочный тег, ссылающийся на него, умирает. Инлайнить id блоков.
- Item model definitions обязательны на каждый предмет: `minecraft:model` для простого,
  `minecraft:select` для вариантов. Формат сверять по `ClientItem.CODEC` / `ItemModels.CODEC` /
  `SelectItemModel.Unbaked.MAP_CODEC`.
- Слой рендера блока задаётся в модели (`"render_type": "translucent"`), а не кодом:
  `ItemBlockRenderTypes.setRenderLayer` больше нет.
- Ингредиент рецепта — плоская строка (`"minecraft:iron_ingot"`, `"#minecraft:logs"`),
  результат — `ItemStackTemplate`. Рукописные рецепты датаген не трогает: их проверяет
  интегратор, но найти их — твоя работа, ты знаешь формат.

DONE-КРИТЕРИЙ
<конкретно: например «все N генераторов переписаны на Fabric; runDatagen проходит; выход
продиффен против оракула: X из X файлов воспроизведены, расхождения объяснены построчно»>

ОТЧЁТ (формат — <КИТ>/templates/AGENT-REPORT-TEMPLATE.md)
Что сделано; таблица расхождений с оракулом (файл — что изменилось — почему — ссылка на кодек);
что отключено; правки, нужные в чужих файлах; всё новое — блоком для FINDINGS.
```

---

## Промпт интегратора

Третья фаза. Собирает всё вместе, гоняет Gradle и единственный смоук-тест. Работает **от ошибок,
а не от файлов**: его вход — вывод компилятора, а не дерево исходников.

---

```
Ты интегратор порта <МОД> на Fabric / Minecraft 26.2. Агенты A, B, C, D свои зоны закрыли.
Твоя задача — довести дерево до зелёного `build` и до сервера, который поднимается без ошибок.
Gradle тебе РАЗРЕШЁН, ты в чекауте один. Коммитить и пушить нельзя — это делает оркестратор.

ЧИТАТЬ
1. <ПРОЕКТ>/PORT-STATUS.md — раздел «Contract deviations» ПЕРВЫМ: там сигнатуры, которые
   агенты были вынуждены изменить против контракта. Половина твоих ошибок объясняется им.
2. <КИТ>/guides/PORT-ANY-MOD-26.2.md — §10 (деградация), §13 (приёмка), §14 (рантайм-грабли,
   которых компилятор не видит).
3. <КИТ>/guides/PORT-CHEATSHEET.md — готовые исправления повторяющихся ошибок компиляции.

ПОРЯДОК РАБОТЫ
  cd <ПРОЕКТ>; export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64; G=/opt/gradle-9.6.1/bin/gradle
  $G compileJava --no-daemon 2>&1 | tee /tmp/errors.txt
  $G build       --no-daemon      # здесь применяются миксины и обрабатываются ресурсы
  $G runDatagen  --no-daemon      # если у мода есть датаген
  mkdir -p run && echo "eula=true" > run/eula.txt
  $G runServer   --no-daemon      # смоук-тест; ОДИН запуск за цикл

Цикл: compileJava → первые ~30 ошибок → открыть ТОЛЬКО падающие строки (Read с offset/limit) →
починить → пересобрать. Не читать файлы «для контекста». В логе Gradle каждая ошибка дублируется —
считать уникальные:
  grep -oE '[^ ]+\.java:[0-9]+: error' /tmp/errors.txt | sort -u | wc -l

ЖЁСТКИЕ ПРАВИЛА
- Каждый проход обязан либо уменьшить число ошибок, либо применить срез по §10.
- Сопротивляется после двух честных попыток → §10, лестница деградации:
  (1) отключить строку регистрации → (2) заглушить тело метода, оригинал рядом в комментарии →
  (3) функциональная деградация → (4) выкинуть объект данных.
  Маркер обязателен: `// TODO(port-26.2): DISABLED — <причина одной строкой>`. Код не удалять.
- Приоритет: зелёная сборка важнее полноты фич; серверный геймплей > клиентская визуалка >
  совместимость.
- Ни одной сигнатуры «по памяти»: grep по /opt/mc-src.
- Вопросов пользователю не задавать.

ЧТО ЛОМАЕТСЯ УЖЕ ПОСЛЕ КОМПИЛЯЦИИ (§14, каждый пункт стоил отдельного цикла)
- Рецептов нет в игре, ошибок в консоли нет → результат рецепта должен быть `ItemStackTemplate`,
  а ингредиенты в JSON — плоскими строками.
- Сервер отказывается стартовать «old mod on much newer vanilla» → в моде свой enum версий
  данных, который кончается на старой версии. Номер 26.2 — в /opt/mc-src/.../DetectedVersion.java.
- `NoClassDefFoundError` на dedicated server → клиентский класс просочился в общий код,
  либо `@Environment(EnvType.CLIENT)` снят там, где Fabric физически вырезает член.
- `Missing element …` при инициализации → что-то резолвит реестр раньше, чем реестр существует.
- `Failed to initialize server` + `bind(..) failed with error(-98)` → предыдущий runServer держит
  порт 25565. Убить (`pkill -f "[d]evlaunch"`), а не «чинить мод».
- `No key layers in MapLike[{}]` → `level-type=minecraft:flat` без generator settings в
  server.properties. Тоже не мод.

ПРИЁМКА
DONE = сервер доходит до `Done (N.NNNs)! For help, type "help"` и в логе НОЛЬ строк `/ERROR]`.
Строку `/ERROR]`, гарантированно порождённую ванилью или сторонней библиотекой и не лечащуюся
срезом в своём коде, выноси в отчёт как кандидата в allowlist — решение принимает оркестратор.
Клиент этой приёмкой НЕ проверяется: в контейнере нет дисплея. Так и напиши, не выдавая
компиляцию за проверку.

ОТЧЁТ (формат — <КИТ>/templates/AGENT-REPORT-TEMPLATE.md)
Результаты всех четырёх команд дословно (время сборки, число ошибок, строка `Done`);
полный список применённых срезов §10 с маркерами; кандидаты в allowlist с обоснованием;
что осталось непроверенным и почему; всё новое — блоком для FINDINGS.
```

---

## Промпт свипера

Свежий агент, нанимаемый на **один конкретный список ошибок**. Смысл роли — чистый контекст:
он не тащит историю неудачных попыток и не спорит с собственными прошлыми решениями.

Свипер получает **меньше**, чем обычный агент: список ошибок, правило деградации, правило
подтверждения сигнатур и путь к референсу. Полная карта API ему не нужна — его ошибки уже
конкретны. Максимум четыре свипа на порт.

---

```
Ты чинишь конкретный список ошибок компиляции в порте <МОД> на Fabric / Minecraft 26.2.
Ничего, кроме этого списка, тебе делать не нужно. Gradle тебе РАЗРЕШЁН, ты в чекауте один.
Коммитить и пушить нельзя.

ОШИБКИ (полный список, других задач нет)
<вставить вывод: файл:строка: текст ошибки, уникальные>

КАК ЧИНИТЬ
1. Открывай ТОЛЬКО падающие строки (Read с offset/limit). Не читай файлы «для контекста»,
   не изучай дерево, не рефактори соседний код.
2. Любую версионно-зависимую сигнатуру подтверждай `grep -rn '<symbol>' /opt/mc-src/`
   или строкой из портированного референса <путь к референсному 26.2-моду>.
   Не подтвердил после двух grep-ов — переходи к правилу деградации.
3. Правило деградации: не блокировать сборку и НЕ УДАЛЯТЬ код. Спускаться по лестнице:
   (1) отключить строку регистрации → (2) заглушить тело метода, оригинал оставить рядом
   в комментарии → (3) функциональная деградация → (4) выкинуть объект данных.
   Каждый срез помечать в коде:
     // TODO(port-26.2): DISABLED — <причина одной строкой>
   Приоритет: зелёная сборка важнее полноты фич; серверный геймплей > клиентская визуалка.
4. Диффы маленькие и механические. Ошибка, которую ты не понял, — кандидат на срез, а не на
   изобретение нового API.

ЗАПРЕТЫ
- Никаких yarn-имён, никакого ResourceLocation, никакого Identifier.of.
  Класс — net.minecraft.resources.Identifier, фабрика — Identifier.fromNamespaceAndPath(...).
- Никаких имён методов «по памяти»: тренировочные данные по диапазону 1.21.2 → 26.2 устарели.
- Не трогать исходный (старый) модуль, из которого портируем.
- Вопросов пользователю не задавать.

DONE-КРИТЕРИЙ
Список ошибок закрыт: каждая либо починена, либо срезана по правилу деградации с маркером.
Число ошибок обязано уменьшиться — проход, который не уменьшил и не срезал, считается провалом.

ОТЧЁТ
Построчно: ошибка → что сделано (починено / срезано) → чем подтверждено (путь и строка).
Отдельно: ошибки, которые остались, и почему именно они не поддались.
```

---

## Когда свипер не поможет

- **Ошибка не в коде, а в контракте** — два агента написали разные формы одного API. Это чинит
  оркестратор решением, а не свежий агент правкой.
- **Ошибка одна и та же в 200 файлах** — это работа для скрипта из `../scripts/`, а не для агента.
- **Четвёртый свип подряд** — дальше не нанимать. Записать «не доведено» с полным остатком
  в `PORT-STATUS.md → Verification`: это честный результат, а бесконечный найм — главный сценарий
  полного сжигания бюджета.

---

## Промпт «перепроверь по вебу»

Нужен только тогда, когда сеть доступна, а портированного референса на диске нет. Референс на
диске всегда сильнее веба: там та же задача уже решена и собрана.

---

```
Ты портируешь Fabric-мод в диапазоне 1.21 → 26.2. Твои тренировочные данные для этого
диапазона УСТАРЕЛИ — не полагайся на память. Перед любой версионно-зависимой правкой:

Контекст, который надо держать:
- Версии теперь year.drop: после 1.21.11 идут 26.1 и 26.2. «1.26.2» не существует.
- Yarn/Intermediary мертвы после 1.21.11; 26.1+ необфусцирован, имена Mojang.
- Java 25 с 26.1, Gradle 9.x, Loom 1.17.x, строки `mappings` в build.gradle нет.
- ResourceLocation не существует: класс — net.minecraft.resources.Identifier,
  фабрика — Identifier.fromNamespaceAndPath(...). Identifier.of(...) — yarn-имя, его тоже нет.

Порядок проверки:
1. Найти пост или документ Fabric под целевую версию (site:fabricmc.net, site:docs.fabricmc.net).
2. Сверить точную сигнатуру класса или метода на mcsrc.dev либо в
   minecraft.wiki/w/Java_Edition_26.2.
3. Установить, ЧТО именно произошло с символом: переименован / переехал в другой пакет /
   сменил сигнатуру / удалён совсем. Это четыре разных лечения.
4. Только после этого писать код — и указать URL, по которому проверил.
   Не нашёл живого источника — так и скажи и ОСТАНОВИСЬ, не угадывай.

Чего не делать:
- Не доверять туториалам и постам до 2026 года: они описывают обфусцированную игру с Yarn.
- Не принимать ответ форума за сигнатуру. Сигнатура — только из исходника или официального дока.
- Не «чинить» по аналогии с 1.20/1.21: половина ломок диапазона — не переименования,
  а исчезновение целых подсистем (immediate-mode буфера, BakedModel, capability-API).
```

---

## Приоритет источников, если доступно несколько

1. **Портированный 26.2-мод на диске** — форму копировать, а не сочинять.
2. **`/opt/mc-src`** — декомпилированная ваниль, `grep -rn`. Выше любого документа.
3. **`javap`** по джарникам fabric-api в кэше Gradle — единственный способ узнать форму Fabric API,
   которой нет ни в ванили, ни в референсе.
4. **Официальные доки Fabric** — для концепций.
5. **Веб** — последнее средство, и только с URL в отчёте.

---

# Часть X. Шаблоны документов порта

Отдельными файлами — в `templates/`.

---

## PORT-STATUS — <МОД> → Fabric / Minecraft 26.2

Живой документ порта. **Пишет только оркестратор.** Агенты читают его, но не правят: материал —
срезы, отклонения, результаты — передают в финальных отчётах. Это убирает гонку на запись, когда
агенты работают параллельно.

Закон порта — `<КИТ>/guides/PORT-ANY-MOD-26.2.md`. Выше него по авторитету только
декомпилированные исходники игры в `/opt/mc-src`.

---

## Toolchain — ГОТОВО, НЕ ПЕРЕУСТАНАВЛИВАТЬ

| | |
|---|---|
| Java | `/usr/lib/jvm/java-25-openjdk-amd64` (Java 25) |
| Gradle | `/opt/gradle-9.6.1/bin/gradle` — **только он**, `./gradlew` не работает (403 на ассеты GitHub) |
| `/opt/mc-src` | декомпилированный Minecraft 26.2 — **только grep, никогда не перегенерировать**. Готов: **<да/нет>** |
| Проект | `<ПРОЕКТ>` |
| Исходник (только чтение) | `<ИСХОДНИК>` — **не редактировать** |
| Ветка | `<ВЕТКА>` |

Любая сборка:
```sh
cd <ПРОЕКТ> && JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64 \
  /opt/gradle-9.6.1/bin/gradle <task> --no-daemon 2>&1 | tee /tmp/errors.txt
```
**Одна инвокация Gradle одновременно на весь чекаут.** Две параллельные портят кэш Loom.

### Пины версий

`minecraft <версия>` · `fabric-loader <версия>` · `fabric-api <версия>` · `loom <версия>`
· `gradle 9.6.1` · `java 25` · **строки `mappings` нет**

### Референсные порты на диске (приоритет выше собственной памяти)

| Путь | Чем полезен |
|---|---|
| `<путь>` | `<что там уже решено>` |

---

## Rules — выжимка §9 + §10 закона, агент читает это первым

**DO**
1. Прежде чем писать — найти тот же паттерн в портированном референсном моде на диске.
2. Любую версионно-зависимую сигнатуру подтвердить `grep -rn '<symbol>' /opt/mc-src/`.
3. Работать **от ошибок, а не от файлов**: список ошибок → открыть только падающие строки → починить.
4. Держаться своего списка файлов. Нужна правка в чужом — написать в отчёте, самому не трогать.
5. Диффы маленькие и механические.
6. Если `/opt/mc-src` противоречит инструкции — **прав он**; сделать по нему и сказать в отчёте.

**DON'T**
1. Не запускать `./gradlew`, ничего не качать (403). Gradle не запускать, если роль не разрешает.
2. Не коммитить и не пушить — это делает оркестратор.
3. Не изобретать имена методов. Не подтвердил после двух grep-ов — §10.
4. Никаких yarn-имён, никакого `ResourceLocation`, никакого `Identifier.of`.
5. Не доверять туториалам до 2026 года и собственной памяти по сигнатурам.
6. Не редактировать исходник, из которого портируем.
7. Вопросов пользователю не задавать.

**§10 — правило деградации.** Сопротивляется после ~двух честных попыток → **не блокировать сборку
и не удалять код**, а спускаться по лестнице: (1) отключить строку регистрации → (2) заглушить тело
метода, оригинал рядом в комментарии → (3) функциональная деградация → (4) выкинуть объект данных.
Приоритет: **зелёная сборка важнее полноты фич**; серверный геймплей > клиентская визуалка >
совместимость.

**Каждый срез логируется тремя способами:**
1. В коде: `// TODO(port-26.2): DISABLED — <причина одной строкой>`, оригинал рядом, не удалять.
2. Строкой в этом файле → «Disabled content».
3. Строкой в `PORT-GAPS.md` — с тем, что видно в игре, и как чинить.

Финальная сверка: `grep -rn "TODO(port-26.2)" src | wc -l` == числу строк в `PORT-GAPS.md`.

---

## Маршрут

`<от чего к чему, сколько осей: версия игры / лоадер / мэппинги. Почему выбрана именно эта база.>`

---

## Замороженные контракты

Контракт нужен там, где два агента иначе договорятся по-разному. Заморожены **до** старта агентов.

- **C1 — форма регистрации.** `<...>`
- **C2 — entrypoint'ы.** `<кто их единственный редактор>`
- **C3 — сеть.** `<точка входа, форма payload'ов>`
- **C4 — capabilities.** `<есть / нет>`
- **C5 — события.** `<во что переезжают>`
- **C6 — владение общими файлами.** `<список и единственный редактор>`
- **C7 — формат кастомных JSON.** `<заморожен как есть, дословно>`
- **C8 — сгенерированный контент.** `<оракул, где лежит>`

---

## Ownership — списки файлов, пересечений нет

Границы проводятся **по файлам, а не по пакетам**: всё `*Model*`/`*Renderer*`/`*Screen*`/`Color*`
принадлежит клиентскому агенту, где бы оно ни лежало.

### Агент A — ядро, сборка, регистрация. **Gradle: можно (он один).**
`<список>`

### Агент B — блоки, предметы, логика, сеть. **Gradle: НЕТ.**
`<список>`

### Агент C — клиент и модели. **Gradle: НЕТ.**
`<список>`

### Агент D — датаген. **Gradle: НЕТ.**
`<список>`

---

## Checklist

- [ ] **Шаг 0 (оркестратор)** — окружение, `/opt/mc-src`, скелет, механический проход, эти документы
- [ ] **A** — `<done-критерий>`
- [ ] **B** — `<done-критерий>`
- [ ] **C** — `<done-критерий>`
- [ ] **D** — `<done-критерий>`
- [ ] **Интеграция** — `compileJava` и `build` зелёные
- [ ] **Приёмка** — `runServer` доходит до `Done (N.NNNs)!`, ноль `/ERROR]` вне allowlist
- [ ] **Проверка человеком на живом клиенте** — порядок проверки в `PORT-GAPS.md`

---

## Contract deviations

_Любая сигнатура, которую агент был вынужден изменить против контракта. Интегратор читает первым._

| # | Кто | Что изменено | Почему |
|---|---|---|---|

---

## Disabled content

_Журнал §10, по строке на срез. Полная таблица с последствиями — в `PORT-GAPS.md`._

| Файл | Что отключено | Почему |
|---|---|---|

---

## Verification

| Команда | Результат |
|---|---|
| `compileJava` | |
| `build` | |
| `runDatagen` | |
| `runServer` | |

**Allowlist строк `/ERROR]`** — только заведомо не из мода, с обоснованием:

| Строка | Почему не считается против приёмки |
|---|---|

**Не проверено (и почему).** `<обычно весь клиент: в контейнере нет дисплея; компиляция — не
проверка. Писать честно.>`

---

## PORT-GAPS — что отключено, деградировано или не проверено

Рабочий список на «потом». Правило: **зелёная сборка важнее полноты фич, но всё вырезанное должно
быть записано так, чтобы это можно было починить, не занимаясь археологией.**

Каждой строке здесь обязан соответствовать маркер в коде:
```java
// TODO(port-26.2): DISABLED — <причина одной строкой>
/* … оригинальный код нетронутым … */
```
Сверка перед сдачей: `grep -rn "TODO(port-26.2)" src | wc -l` == числу строк в таблицах ниже.

Колонки:
- **Что видно в игре** — наблюдаемое следствие. Если следствия нет, так и писать («невидимо»).
- **Как чинить** — конкретная зацепка: какой класс, какой API 26.2, что проверить.
- **Приоритет** — 🔴 серверный геймплей · 🟡 клиентская визуалка · 🟢 совместимость/косметика.

---

## Отключённый контент

| # | Файл:строка | Что отключено | Почему | Что видно в игре | Как чинить | Приоритет |
|---|---|---|---|---|---|---|
| 1 | | | | | | |

---

## Функциональная деградация

_Работает, но иначе, чем на исходном лоадере._

| # | Файл:строка | Что деградировало | Почему | Что видно в игре | Как чинить | Приоритет |
|---|---|---|---|---|---|---|
| 1 | | | | | | |

---

## Поведенческие решения (маркеров нет, но знать надо)

_Замены, эквивалентные по смыслу, но принятые агентом, а не продиктованные API. Тут ловятся
несогласованности, которые иначе всплывут через полгода._

| Файл | Решение | Почему |
|---|---|---|

---

## Починено по дороге (не гэпы — исправленные баги)

_Баги, которые порт вскрыл: они были и в оригинале, либо появились из-за разницы версий._

| Что | Симптом | Причина | Лечение |
|---|---|---|---|

---

## Не проверено (и почему)

| Область | Что именно не проверено | Причина |
|---|---|---|
| `client/**` | | В контейнере нет дисплея; `runServer` клиентский код не исполняет. Установлена только чистая компиляция |

---

## Порядок проверки на живом клиенте

_Чек-лист человеку: что открыть, что нажать, что должно быть видно. Пишется так, чтобы проверку
можно было провести, не читая исходники._

1. `<действие>` → ожидаемо: `<что видно>`; если не так — `<на какую строку таблицы это указывает>`

---

## FINDINGS-<A|B|C|D|INTEGRATION> — копилка знаний агента

Сюда пишется **только то, чего не было в порт-ките** и что пришлось выяснять самому: новый класс,
переехавший пакет, изменившаяся сигнатура, мёртвый API, рабочий обходной путь. Дублировать то, что
в ките уже есть, не надо.

Файлы пер-агентные, чтобы параллельные агенты не дрались за один документ. Оркестратор в конце
сливает их в `guides/NOTES-A/B/C.md` — из этого и собирается кит для следующего порта.

Формат каждой записи:

```
### <Символ или тема>
- **Было (<исходный лоадер и версия>):** ...
- **Стало (26.2):** ...
- **Подтверждено:** /opt/mc-src/<путь>:<строка>  ИЛИ  <референсный мод>/<файл>:<строка>
- **Комментарий:** грабли, порядок инициализации, что ломается молча
```

Запись без строки «Подтверждено» бесполезна: следующий агент не сможет отличить её от догадки.

---

## Пример заполнения

### `BlockBehaviour.Properties` требует `ResourceKey<Block>` до конструктора

- **Было (NeoForge 26.1):** блок строил `Properties` внутри собственного безаргументного
  конструктора, id проставлялся реестром позже.
- **Стало (26.2):** `BlockBehaviour` читает `ResourceKey<Block>` из `Properties` **в конструкторе**;
  без него — `NullPointerException: Block id not set` на первом же блоке при инициализации мода.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/level/block/state/BlockBehaviour.java:1155,1289`
- **Комментарий:** если блоков много и каждый строит `Properties` сам, дешевле миксин на
  `BlockBehaviour$Properties`, чем правка каждого класса — особенно когда классы принадлежат
  другому агенту. Провал виден только в рантайме: на компиляции миксин не исполняется.

---

## Записи

### <Символ или тема>
- **Было:**
- **Стало (26.2):**
- **Подтверждено:**
- **Комментарий:**

---

## Финальный отчёт агента

Отчёт — единственный канал агента наружу: `PORT-STATUS.md` он не пишет, коммитов не делает.
Всё, что не попало в отчёт, для порта не существует.

Пять разделов, все обязательны. Пустой раздел так и помечается: «нет».

---

```
## 1. Сделано
<по пунктам, коротко. Не пересказ диффа, а результат: что теперь работает и в каком виде.>

## 2. Чем подтверждено
<для каждой версионно-зависимой правки — путь и строка: /opt/mc-src/... или <референс>/...
 Правка без подтверждения — это догадка, и она должна быть названа догадкой.>

## 3. Срезы по §10
| Файл:строка | Что отключено | Почему | Что видно в игре |
|---|---|---|---|
<каждой строке соответствует маркер TODO(port-26.2) в коде. Если срезов нет — «нет».>

## 4. Нужны правки в чужих файлах
| Файл | Что нужно | Почему |
|---|---|---|
<сам не трогал. Если ничего не нужно — «нет».>

## 5. Отклонения от контрактов
| Контракт | Что изменено | Почему было нельзя иначе |
|---|---|---|
<интегратор читает этот раздел первым. Если отклонений нет — «нет».>

## 6. Для FINDINGS
<всё, чего не было в порт-ките и что пришлось выяснять самому, в формате
 <КИТ>/templates/FINDINGS-TEMPLATE.md: было → стало → подтверждено → комментарий.
 Это следующий кит для следующего порта; пустым этот раздел почти никогда не бывает.>

## 7. Что осталось непроверенным
<и почему именно: нет дисплея, нет Gradle, нет второго мода. Компиляция — не проверка.>
```

---

## Что делает отчёт бесполезным

- **Пересказ диффа.** Оркестратор видит дифф; ему нужно то, чего в диффе нет: почему так, чем
  подтверждено, что сломается.
- **«Готово».** Без done-критерия дословно и без результата команды это ничего не значит.
- **Молчание про срезы.** Незалогированный срез превращается в «баг неизвестного происхождения»
  через два дня и стоит отдельного цикла отладки.
- **Правка в чужом файле вместо строки в разделе 4.** Два агента, правящие один файл, — самая
  дорогая ошибка в схеме: конфликт обнаруживается только на интеграции.
