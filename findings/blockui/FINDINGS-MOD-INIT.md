# FINDINGS — BlockUI, момент инициализации мода и headless-тесты

Порт: NeoForge / MC 26.1.2 → Fabric / MC 26.2, библиотека с тремя зависимыми модами.

Собрано при починке двух крашей в `com.ldtteam.common.language`, из-за которых **не стартовал ни один
зависимый мод**, и при заведении общего `com.ldtteam.common.inventory`.

Особенность этой копилки: всё найденное относится не к переезду API, а к **моменту времени** — что
уже существует, когда вызывают точку входа мода, и что ещё нет. Компилятор про такое не знает ничего.

---

## Записи

### Точки входа Fabric вызываются изнутри `Minecraft.<init>`, до присвоения `options`

- **Было (NeoForge 1.21.1 / 26.1.2):** конструктор мода видел уже собранный клиент; проверки
  `Minecraft.getInstance() == null` хватало, чтобы отличить датаген от игры.
- **Стало (26.2):** `FabricLoaderImpl.invokeEntrypoints` вызывается из `Hooks.startClient`,
  вкрученного в `Minecraft.<init>`, и попадает в окно между `instance = this` и
  `this.options = new Options(...)`. То есть `Minecraft.getInstance() != null`, а
  `getInstance().options == null` — 43 строки конструктора, в которых любое чтение клиентского
  состояния из mod init даёт NPE.
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/Minecraft.java:384,427`; стек падения —
  `Hooks.startClient(Hooks.java:52)` ← `Minecraft.<init>(Minecraft.java:456)`
- **Комментарий:** правило «`getInstance()` не null, значит клиент готов» в 26.2 неверно для
  **любого** поля `Minecraft`, а не только для `options`: на mod init не готово ничего, что
  присваивается после 384-й строки. Практическое следствие: из точки входа читать только
  `FabricLoader` и реестры, всё клиентское — с отложенного события.

### `ExceptionInInitializerError` в общей библиотеке называет в краш-репорте не тот мод

- **Было (NeoForge):** конструкторы модов вызывались по одному, и падение статического инициализатора
  общей библиотеки приходило с именем того мода, который её позвал.
- **Стало (26.2):** `invokeEntrypoints` собирает исключения через `ExceptionUtil.gatherExceptions`,
  поэтому в отчёт попадают оба потребителя сразу: тот, кто дошёл до класса первым, получает
  `ExceptionInInitializerError`, второй — `NoClassDefFoundError: Could not initialize class ...` и
  уезжает в `Suppressed`. **Заголовок краша называет только первого.**
- **Подтверждено:** краш-репорт первого живого запуска MineColonies — заголовок `minecolonies`, в
  `Suppressed` `Structurize.onInitialize(Structurize.java:44)`, обе ветки ведут в
  `LanguageHandler$LanguageCache.<clinit>`
- **Комментарий:** ленивый `<clinit>` singleton'а в библиотеке превращает баг библиотеки в «баг того
  мода, который стартовал первым». **Читайте `Suppressed`-ветку:** если там второй мод падает на той
  же строке, чинить надо не у себя. Порядок «кто первый» задаётся `depends` в `fabric.mod.json` и
  меняется от сборки к сборке — то есть виноватый мод может смениться сам собой.

### Ресурс, приходящий из внешнего пайплайна, в dev отсутствует всегда

- **Было (NeoForge 26.1.2):** `getResourceAsStream(...)` разыменовывался без проверки — **та же строка
  без проверки есть и в доportной ветке**, то есть порт этого не вносил.
- **Стало (26.2):** ничего не изменилось в коде — изменилось то, что путь наконец исполнился.
  У MineColonies в `assets/minecolonies/lang/` лежит только `manual_en_us.json`; `en_us.json`
  выгружается из POEditor скриптом и в гит не попадает. В dev- и датаген-прогоне и текущая локаль, и
  фолбэк `en_us` дают `null`, и `new InputStreamReader(null, …)` роняет mod init.
- **Подтверждено:** `blockui/26.1.2/.../LanguageHandler.java:66-75` (без проверки);
  `minecolonies/1.21.1/.../MineColonies.java:114`; `minecolonies/1.21.1/tools/export_lang/exportLang.py:6`
  (`base_url = "https://poeditor.com/api/"`)
- **Комментарий:** искать лоадер-специфичную причину «почему на NeoForge не стреляло» — потерянный
  цикл: код и наличие файла в обеих ветках одинаковые. Ответ «почему раньше не падало» так и не
  найден (в снапшоте 1.21.1 нет `build.gradle`, нельзя проверить, не подкладывал ли файл gradle-таск),
  и выдумывать его не надо. Правило для следующего агента: **любой код, читающий с classpath ресурс,
  который производит внешний пайплайн, обязан переживать `null`** — независимо от лоадера.

### `Inventory` в 26.2: `getContainerSize()` включает экипировку, `canPlaceItem` не переопределён

- **Было (NeoForge 1.21.1):** `new InvWrapper(player.getInventory())` было штатной идиомой — обёртка
  целиком не пускала предметы в броню.
- **Стало (26.2):** `Inventory#getContainerSize()` возвращает `items.size() + EQUIPMENT_SLOT_MAPPING.size()`,
  а `canPlaceItem` `Inventory` **не переопределяет** — дефолт `Container#canPlaceItem` возвращает `true`.
  Обёртка «весь инвентарь» примет что угодно в слот брони и отчитается об успехе. Основные слоты —
  0..35.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/entity/player/Inventory.java:30,408-409,428-436`
  (`grep -c canPlaceItem Inventory.java` → 0); `/opt/mc-src/net/minecraft/world/Container.java:56-58`
- **Комментарий:** чинится **диапазоном слотов, а не проверкой валидности** — проверять нечего,
  `canPlaceItem` всегда `true`. Тихо: тесты зелёные, компилятор молчит, видно только в игре и только
  когда кто-то положит еду в шлем.

### Юнит-тесты с ванильными классами: что работает headless, а что нет

*(тест-сторона записи «Компоненты предметов больше не привязаны к моменту регистрации» из
`findings/minecolonies/`)*

- **Стало (26.2):** в тестовой JVM Loom'а без запущенной игры **работают** `ItemStack.EMPTY`,
  `NonNullList`, `new SimpleContainer(n)` и любая своя реализация `Container`. **Не работают**
  `Items.X` (`IllegalArgumentException: Not bootstrapped`) и — неочевидно — `SimpleContainer#setItem`:
  он зовёт `Container#getMaxStackSize(ItemStack)` → `ItemInstance#getMaxStackSize` → `<clinit>`
  `DataComponents` → `NullPointerException: Components not bound yet`.
  `SharedConstants.tryDetectVersion()` + `Bootstrap.bootStrap()` **не помогает**: компоненты привязывает
  только релоад серверных ресурсов.
- **Подтверждено:** `/opt/mc-src/net/minecraft/world/SimpleContainer.java:121` →
  `/opt/mc-src/net/minecraft/world/Container.java:38-40`; воспроизведено в `blockui/26.2` (`gradle test`)
- **Комментарий:** слот-логику инвентаря headless тестировать **можно**, но контейнер надо писать
  руками (`Container` — 8 абстрактных методов + `clearContent`; `getSlot` и `iterator` — `default`), и
  все стеки в тесте обязаны быть `ItemStack.EMPTY`. Ловушка на ровном месте: **чтение** из
  `SimpleContainer` безопасно, **запись** — нет, и чтение в том же тесте проходит.
