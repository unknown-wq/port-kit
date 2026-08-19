# FINDINGS-C — копилка знаний агента C (GUI), Structurize → Fabric / MC 26.2

Только то, чего **не было** в порт-ките (`PORT-ANY-MOD-26.2.md`, `NOTES-C.md`), в
`FINDINGS-A/B1/B2/D/INTEGRATION.md` и в `PORT-GAPS.md`. Каждая находка с подтверждением.

Зона: 13 запаркованных файлов `client/gui/**` (4496 строк), 14 XML-layout'ов, расшивка `GuiStubs`,
строка 20 `PORT-GAPS.md` (кейбинды окна чертежа).

---

## 0. Главное: порт GUI на BlockUI 26.2 — это 77 ошибок компиляции и **две** невидимые ловушки

После снятия `exclude` из `build.gradle` `compileJava` дал **77 ошибок** на 13 файлов, и
**ни одна** не касалась самого BlockUI: все 20 символов библиотеки совпали по именам и сигнатурам.
Ошибки — это ваниль 26.2 и `com.ldtteam.common`.

Опаснее оказались две вещи, которые **компилируются молча и ломают поведение**:

1. `Pane#onKeyTyped(char, int)` на уровне окна больше не вызывается (§2);
2. цвет текста с нулевой альфой теперь не рисуется вовсе (§3).

Если работать только «от списка ошибок», обе уехали бы в ручную проверку на клиенте.

---

## 1. `com.ldtteam.common.config`: `ValueSpec` не существует, метаданные переехали на `ConfigValue`

- **Было (NeoForge 1.21.1):** `ModConfigSpec.ConfigValue#getSpec()` → `ValueSpec` с
  `getTranslationKey()`, `getComment()`, `test(Object)`.
- **Стало (26.2):** `ValueSpec` нет вовсе. `getTranslationKey()` и `getComment()` — прямо на
  `com.ldtteam.common.config.ConfigValue`. `getSpec()` нет, **`test(...)` нет**.
- **Подтверждено:** `/workspace/blockui/26.2/src/main/java/com/ldtteam/common/config/ConfigValue.java:56-70`.
- **Правка импорта** работает, но не полностью:
  ```java
  // было
  import net.neoforged.neoforge.common.ModConfigSpec.ConfigValue;
  import net.neoforged.neoforge.common.ModConfigSpec.DoubleValue;
  import net.neoforged.neoforge.common.ModConfigSpec.ValueSpec;   // ← этой строки не будет
  // стало
  import com.ldtteam.common.config.ConfigValue;
  import com.ldtteam.common.config.ConfigValue.DoubleValue;       // ← вложенный в ConfigValue
  ```
- **Валидация ввода потеряна.** `ValueSpec#test(Number)` проверял диапазон; в 26.2 диапазон
  спрятан внутри `IntValue`/`DoubleValue` и наружу не выдаётся. Замена — проверять только
  парсибельность, обрезку оставить сеттеру (`ConfigValue.IntValue#set` делает `Math.clamp`,
  `ConfigValue.java:117,146,175`). Побочный эффект: поле ввода больше не краснеет на выходе
  за диапазон, значение молча зажимается.
- **`getComment()` возвращает уже переведённый текст, а не ключ.**
  `AbstractConfiguration#build` зовёт `LanguageHandler.translateKey(modId + ".config." + key + ".comment")`
  **в момент конструирования конфига** (`AbstractConfiguration.java:88-102`), то есть очень рано.
  Работает только потому, что `LanguageHandler.loadLangPath("assets/<mod>/lang/%s.json")`
  вызывается **строкой раньше** `new Configurations(...)` — см. `Structurize.java:44,45`.
  **Поменяете порядок этих двух строк — все комментарии в окне настроек станут сырыми ключами.**
- **Ключ перевода не включает категорию:** `nameTKey(key) = modId + ".config." + key`
  (`AbstractConfiguration.java:78`). `defineInteger("light_level", …)` внутри
  `createCategory("blueprint") / createCategory("renderer")` даёт `structurize.config.light_level`,
  а не `structurize.config.blueprint.renderer.light_level`. Путь с категориями идёт только в `getPath()`.

---

## 2. ⚠️ `Pane#onKeyTyped(char, int)` жив, но на уровне окна **мёртв** — компилятор молчит

- **Было (BlockUI 1.21.1):** `BOScreen.keyPressed/charTyped` → `window.onKeyTyped(ch, key)`;
  окно раздавало событие фокусу и дальше в `onUnhandledKeyTyped(ch, key)`. Переопределить
  `onKeyTyped` на окне было штатным приёмом «сделать что-то после любой клавиши».
- **Стало (26.2):** `BOScreen.keyPressed(KeyEvent)` → `window.onKeyEvent(event)`,
  `BOScreen.charTyped(CharacterEvent)` → `window.onCharactedEvent(event)`.
  `BOWindow` **переопределяет оба** и **не** обращается к `onKeyTyped`.
- **Подтверждено:** `/workspace/blockui/26.2/.../BOScreen.java:173,181,196,200`;
  `.../views/BOWindow.java:246,265,272,281`; `.../Pane.java:690`
  (`@Deprecated(forRemoval = true, since = "26.1")`).
- **Ловушка:** `onKeyTyped` **остался** в `Pane` как deprecated, поэтому `@Override` компилируется,
  IDE не ругается, а метод просто никогда не вызывается. В Structurize так тихо умерли
  `WindowShapeTool.onKeyTyped` (пересчёт формы после ввода размеров) и
  `WindowTagTool.onKeyTyped` (обновление списка тегов).
- **Рабочая замена** — переопределять **оба** новых события, потому что нажатие клавиши и ввод
  символа в 26.2 разъехались:
  ```java
  @Override public boolean onKeyEvent(final KeyEvent event)            { final boolean r = super.onKeyEvent(event);       refresh(); return r; }
  @Override public boolean onCharactedEvent(final CharacterEvent event){ final boolean r = super.onCharactedEvent(event); refresh(); return r; }
  ```
- **Для любого мода на BlockUI это надо грепать явно:** `grep -rn 'onKeyTyped' src/` —
  компилятор эту регрессию не покажет.
- **Тот же раскол в `onUnhandledKeyTyped`:** сигнатура стала `(KeyEvent)`, а старый идиом
  `if (ch != 0) return super.onUnhandledKeyTyped(ch, key);` просто исчезает: туда теперь приходят
  только key-события. Обработчик, ловивший **цифры** (`WindowScan`: `if (ch >= '0' && ch <= '9')`),
  надо переносить в `onCharactedEvent(CharacterEvent)` и читать `event.codepoint()`.
  `record CharacterEvent(int codepoint)` — `/opt/mc-src/net/minecraft/client/input/CharacterEvent.java:8`.

---

## 3. ⚠️ Текст с альфой 0 больше не рисуется — «чёрный» цвет NeoForge-стиля даёт невидимые надписи

- **Было (1.21.1):** `Font.drawInBatch` начинался с
  `adjustColor(int c) { return (c & 0xFC000000) == 0 ? c | 0xFF000000 : c; }` — цвет без альфы
  автоматически становился непрозрачным. Поэтому
  `button.setTextColor(ChatFormatting.BLACK.getColor())` (== `0x000000`) рисовало чёрный текст.
- **Стало (26.2):** фиксапа нет, а `GuiGraphicsExtractor#text` начинается с
  **`if (ARGB.alpha(color) != 0)`** — текст с нулевой альфой **не добавляется в очередь**.
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/gui/GuiGraphicsExtractor.java:266`;
  `/opt/mc-src/net/minecraft/client/gui/Font.java:339-347` (никакого `adjustColor`);
  путь BlockUI — `AbstractTextElement.java:278,341` → `BOGuiGraphics#text` → `GuiGraphicsExtractor#text`.
- **Следствие:** любой `setTextColor(rgbБезАльфы)` в моде — это **невидимый текст**, и ни компилятор,
  ни рантайм ничего не скажут.
- **Лечение:** `ARGB.opaque(color)` (`/opt/mc-src/net/minecraft/util/ARGB.java:172`, `color | 0xFF000000`).
- **XML не задет:** `textcolor="black"` идёт через `Parsers.COLOR` → `Color.getByName`, а тот кладёт
  `0xff000000 | rgb` (`/workspace/blockui/26.2/.../Color.java:45`). Ломается **только** цвет,
  посчитанный из java.
- **Греп для любого порта:** `grep -rn 'setTextColor\|setColors\|drawString' src/` и глазами
  проверить старший байт у каждого аргумента.

### Где взять сам цвет: `ChatFormatting` в 26.2 больше не хранит цвет

- **Было:** `ChatFormatting.BLACK.getColor()` → `Integer`, плюс `getId()`, `isColor()`, `isFormat()`.
- **Стало:** `enum ChatFormatting { BLACK('0'), … }` — **только код символа**. Таблица цветов уехала
  в `net.minecraft.network.chat.TextColor`: `TextColor.BLACK … TextColor.WHITE`, значение —
  `getValue()`, плюс `TextColor.fromLegacyFormat(ChatFormatting)` (`@Nullable`) и `TextColor.fromRgb(int)`.
- **Подтверждено:** `/opt/mc-src/net/minecraft/ChatFormatting.java:7-59`;
  `/opt/mc-src/net/minecraft/network/chat/TextColor.java:20-35,55,92,114`.
- **Итоговая замена:** `ChatFormatting.BLACK.getColor()` → `ARGB.opaque(TextColor.BLACK.getValue())`.
  Форматирование стиля (`Component#withStyle(ChatFormatting.GOLD)`) не изменилось.

---

## 4. `KeyMapping#isActiveAndMatches` → `KeyMapping#matches(KeyEvent)`

- **Было:** `KeyMapping#isActiveAndMatches(InputConstants.Key)` — NeoForge-расширение
  (учитывало `IKeyConflictContext`, `KeyModifier` и «не unbound»).
- **Стало:** ванильный **`boolean matches(KeyEvent event)`**
  (`/opt/mc-src/net/minecraft/client/KeyMapping.java:167`) плюс `matches(InputConstants.Key)` (`:177`).
  `matches(KeyEvent)` сам корректно обрабатывает KEYSYM/SCANCODE и unbound.
- **Комментарий:** `InputConstants.Type.KEYSYM.getOrCreate(key)` больше не нужен — `KeyEvent`
  несёт и `key()`, и `scancode()`.
- **Контекст конфликта восстанавливается только наполовину.** Поведенческую половину
  (`BLUEPRINT_WINDOW` из строки 20 `PORT-GAPS.md`) можно вернуть руками: обработчик живёт внутри
  окна, поэтому достаточно явной проверки `ModKeyMappings.isBlueprintWindowActive()`
  (реализована как `Minecraft.getInstance().gui.screen() instanceof BOScreen s
  && s.getWindow() instanceof AbstractBlueprintManipulationWindow`). **Декларативную** половину
  вернуть нечем: у ванильного экрана управления понятия контекста нет, и эти привязки так и будут
  подсвечиваться как конфликтующие с ванильными на тех же клавишах.

---

## 5. Ваниль 26.2: мелочи, всплывшие только в GUI

### `ItemStack#getDescriptionId()` удалён, на `Item` остался
`stack.getDescriptionId()` → `stack.getItem().getDescriptionId()`.
`Item#getDescriptionId()` — `final`, `/opt/mc-src/net/minecraft/world/item/Item.java:333`;
в `ItemStack` метода нет вовсе (есть `getHoverName`, `getItemName`, `getDisplayName`,
`ItemStack.java:802,824,1014`).
**Комментарий:** меняется смысл — `ItemStack#getDescriptionId` в 1.21.1 умел спрашивать
`Item#getDescriptionId(stack)` (переопределяемый по стеку); теперь фильтр по «внутреннему имени»
всегда видит имя предмета, а не вариант стека.

### Константы `EntityType.*` уехали в `EntityTypes`
`EntityType.LEASH_KNOT` / `GLOW_ITEM_FRAME` / `ITEM_FRAME` / `MINECART` →
`net.minecraft.world.entity.EntityTypes.*`. Сам класс `EntityType` остался — это только поля.
**Подтверждено:** `/opt/mc-src/net/minecraft/world/entity/EntityTypes.java:474,549,570,639`.
`FINDINGS-A` фиксировал переезд `ResourceKey` в `EntityTypeIds`; здесь важно, что **значения**
тоже переехали, а `EntityType.getKey(type)` остался на месте.

### `EntityType#create(Level)` → `create(Level, EntitySpawnReason)` и он `@Nullable`
```java
public @Nullable T create(final Level level, final EntitySpawnReason reason);   // EntityType.java:300
public @Nullable T create(final Level level, final EntitySpawnRequest request); // :304
```
Одноаргументной формы нет. Для «сделать образец сущности ради иконки» подходит
`EntitySpawnReason.LOAD`; **результат обязательно проверять на null** — `create` возвращает null,
когда `canSpawn(level)` ложно (мирная сложность, отключённый feature flag).
Дальше `Entity#getPickResult()` (`Entity.java:3852`) — тоже `@Nullable`, так что на цепочке
`create(...).getPickResult()` из 1.21.1 два NPE подряд.

### `BucketItem.content` стал `protected`
NeoForge публиковал его access-трансформером; в ванили 26.2 это `protected final Fluid content`
(`/opt/mc-src/net/minecraft/world/item/BucketItem.java:35`).
**Обходной путь без AccessWidener:** публичный `BucketItem#getFluidContext()` (`:95`) возвращает
`ClipContext.Fluid.SOURCE_ONLY` ровно тогда, когда `content == Fluids.EMPTY`, иначе `NONE`.
**Ограничение:** `MobBucketItem` переопределяет его на `NONE` безусловно (`MobBucketItem.java:71`) —
для ванили эквивалентность держится, для модового ведра с переопределённым `getFluidContext()` нет.

### `Inventory.items` приватное → `getNonEquipmentItems()`
`NonNullList<ItemStack> getNonEquipmentItems()`, `/opt/mc-src/net/minecraft/world/entity/player/Inventory.java:90`.
Дополняет находку `FINDINGS-B1` про `getSelected()`/`selected`: приватным стало **всё** хранилище,
а не только индекс выбранного слота.

### `DirectionProperty` удалён
Направление — обычный `EnumProperty<Direction>`; файла `DirectionProperty.java` в
`/opt/mc-src/net/minecraft/world/level/block/state/properties/` нет.
Различать — `property.getValueClass() == Direction.class` (`Property.java:53`), и **проверку надо
ставить перед** `instanceof EnumProperty`, иначе она недостижима.

### `Player#displayClientMessage(Component, boolean)` удалён и на клиенте
`FINDINGS-A` фиксировал это для серверного `Player`. Уточнение: у `LocalPlayer` метода тоже нет,
замены две и они **разные**: `sendSystemMessage(Component)` (чат, `LocalPlayer.java:439`) и
`sendOverlayMessage(Component)` (строка над хотбаром, `:444`). Старый флаг `actionBar` стал
выбором метода.

### `LevelHeightAccessor`: `getMaxBuildHeight()` был исключающим, `getMaxY()` — включающий
`getMaxY() == getMinY() + getHeight() - 1` (`/opt/mc-src/net/minecraft/world/level/LevelHeightAccessor.java:9,11`).
**Любое `getMaxBuildHeight() - 1` в старом коде превращается в просто `getMaxY()`.**
То же у `com.ldtteam.common.fakelevel.IFakeLevelBlockGetter`: `getMaxX/getMaxZ` там `min + size - 1`,
то есть **включающие**, хотя javadoc над ними всё ещё говорит «exclusive» — javadoc врёт, смотреть
на `isPosInside`, который сравнивает через `<=` (`IFakeLevelBlockGetter.java:55,64,73`).
**Практический след:** `new BlockPos(getMaxX() - 1, getMaxBuildHeight() - 1, getMaxZ() - 1)`
из 1.21.1 должно стать `new BlockPos(getMaxX(), getMaxY(), getMaxZ())` — минус единица уходит
со **всех трёх** осей сразу, иначе окно «содержимое чертежа» молча недосчитается внешнего слоя блоков.

---

## 6. XML-layout'ы BlockUI порт **не** менял — править нечего

14 файлов, 454 строки, ноль изменений. Проверено механически:

- Все использованные теги зарегистрированы в `Loader` (`window, view, list, box, text, button,
  input, image, itemicon, toggle, dropdown, overlay, checkbox`), плюс `layout` — не фабрика,
  а спецслучай `Loader.java:123`.
- Все 26 использованных атрибутов встречаются в исходниках BlockUI 26.2 как строковые литералы.

**Приём для быстрой проверки при любом порте GUI на BlockUI:**
```sh
grep -ohE '<[a-zA-Z]+' assets/<mod>/gui/*.xml | sort -u     # теги → сверить с Loader.register(...)
grep -ohE '[a-zA-Z]+=' assets/<mod>/gui/*.xml | sort -u     # атрибуты → grep по исходникам BlockUI
```

---

## 7. `GuiStubs` оставлен фасадом — и это оказалось выгодно

Расшивка ожидалась как «раскомментировать тела и удалить класс». Класс оставлен живым фасадом:

1. `client/ModKeyMappings` (зона D) обязан спрашивать «открыто ли окно чертежа» — без фасада
   в него возвращается прямой импорт `com.ldtteam.blockui.BOScreen`, и клиентский класс мода
   начинает зависеть от библиотеки GUI напрямую;
2. четыре предмета зоны A и `network/messages/OperationHistoryMessage` остаются вообще без
   BlockUI в импортах — на выделенном сервере эти классы грузятся, и чем меньше в их constant pool
   клиентских типов, тем меньше поводов для `NoClassDefFoundError`;
3. если GUI придётся резать снова (новая версия BlockUI), отключается **одна** точка.

Единственная правка тел против оригинала — `setLastOperations`/`getLastOperations` делегируют
в `WindowUndoRedo.lastOperations`, а не держат вторую копию списка.

**Обобщение для порт-кита:** фасад «мод ↔ его GUI-библиотека» стоит вводить не на время парковки,
а насовсем — он же является границей клиент/сервер и переживает следующий порт.

---

## 8. Организационное

### `timeout N gradle runServer | tee` съедает лог
`runServer` не завершается сам, `timeout` убивает всю трубу вместе с `tee`, и вывод пропадает
целиком (в терминал приходит одно слово `Terminated`). Писать надо прямо в файл:
```sh
(timeout 150 env JAVA_HOME=… gradle runServer > /tmp/runserver.txt 2>&1); pkill -f "[d]evlaunch"
grep -cE '/ERROR|/FATAL' /tmp/runserver.txt
```
Считать `ERROR`/`FATAL` надо по `/ERROR` со слешем (часть префикса `[поток/ERROR]`): голое `ERROR`
ловит ещё и слово в текстах предупреждений и в путях.

### `runServer` не проверяет GUI, но проверяет одно важное
Ни одно окно на выделенном сервере не создаётся, зато проверяется, что расшивка не втащила
клиентские типы в загружаемые сервером классы. После возврата тел `GuiStubs` (там появились
`Minecraft` и `BOScreen`) сервер поднялся с нулём `ERROR` — значит все пять call-site'ов в общем
коде действительно под `level.isClientSide()`, и JVM резолвит `GuiStubs` лениво.
