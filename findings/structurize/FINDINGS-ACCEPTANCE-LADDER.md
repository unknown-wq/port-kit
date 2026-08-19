# FINDINGS — Structurize, приёмочная лестница

Порт: NeoForge / MC 1.21.1 → Fabric / MC 26.2. Мод компилировался давно; эта копилка — с первого
прохода `build` → `runDatagen` → `runServer`.

Только то, чего в ките ещё не было (проверено по `findings/structurize/*` и
`findings/minecolonies/FINDINGS-RUNTIME.md`).

---

## Записи

### `outputDirectory` датагена — это одновременно корень ресурсов и корень, который чистит `HashCache`

- **Было (NeoForge 1.21.1):** родительский build-скрипт клал `src/datagen/generated/<modid>` в
  `sourceSets.main.resources` руками; каталог вывода и корень ресурсов настраивались отдельно.
- **Стало (26.2 / Loom 1.17):** `fabricApi.configureDataGeneration { outputDirectory = … }` задаёт
  **и то, и другое сразу**: Loom сам делает `sourceSets.main.resources.srcDir(outputDirectory)`
  (`getAddToResources` по умолчанию `true`) и сам вешает `exclude(".cache/**")` на задачу `jar`. Тот же
  путь `HashCache#purgeStaleAndWrite` обходит целиком, удаляя всё, чего не писали провайдеры этого прогона.
- **Подтверждено:** `net.fabricmc.loom.configuration.fabricapi.FabricApiDataGeneration#configureDataGeneration`
  (байткод: `getOutputDirectory` ← `project.file("src/main/generated")`, `getAddToResources().convention(true)`,
  `Jar.exclude(".cache/**")`); `/opt/mc-src/net/minecraft/data/HashCache.java:104-135`
- **Комментарий:** два молчаливых следствия, оба стоили нам по дефекту.
  **Первое:** если сгенерированный пак лежит **не** в `outputDirectory`, его нет в jar'е. У Structurize
  так потерялись **все шесть тегов мода** — ни строки в логе, видно только `Unknown block tag
  '<ns>:<tag>'` при попытке ими воспользоваться. Лишний уровень вложенности не является ошибкой
  сборки: `src/main/generated/resources/data/<ns>/…` спокойно едет в jar как `resources/data/<ns>/…`,
  куда игра никогда не заглянет.
  **Второе, обратное:** файл, случайно оказавшийся **внутри** `outputDirectory`, но не производимый ни
  одним провайдером, будет удалён следующим прогоном — так пропала авторская лут-таблица.
  Правило: `outputDirectory` = корень пака (в нём сразу `data/` и `assets/`), не класть туда ничего,
  что не генерируется, `.cache/` — в `.gitignore`.

### Сломанный `descriptionId` и отсутствующую лут-таблицу видно с консоли выделенного сервера

- **Было:** проверка имени предмета и его дропа требовала клиента и рук.
- **Стало (26.2):** `/loot spawn <куда> mine <откуда>` печатает в консоль **и** имя таблицы, **и**
  hover-name выпавшего стека:
  `Dropped 1 [Tag Anchor Block] from loot table structurize:blocks/blocktagsubstitution`.
  Сломанный `descriptionId` выдаёт себя как `Dropped 1 [item.<ns>.<path>]`, отсутствующая таблица — как
  `Dropped 0 items`.
- **Подтверждено:** воспроизведено на `runServer` Structurize до и после правки; ключ таблицы строится в
  `/opt/mc-src/net/minecraft/world/level/block/state/BlockBehaviour.java:986,1154`, `descriptionId` — в
  `/opt/mc-src/net/minecraft/world/item/Item.java:135,637,654`
- **Комментарий:** **это закрывает оба «молчаливых» дефекта из кита** (`useBlockDescriptionPrefix`,
  `loot_table/`) без клиента — а клиента в контейнере и нет. Рецепт целиком: `forceload add 0 0`,
  `setblock`, `loot spawn`. Теги мода той же консолью:
  `execute if block <pos> #<ns>:<tag> run say OK` — незарегистрированный тег отвечает
  `Unknown block tag '<ns>:<tag>'` **на этапе разбора команды**, то есть отличает «тега нет вообще» от
  «тег пустой». Команды подаются в `runServer` через stdin
  (`(sleep 40; cat cmds.txt) | gradle runServer --console=plain`); если рядом крутится другой порт, в
  `run/server.properties` надо развести `server-port`.

### Мёртвые `blockstates/*.json` в 26.2 безвредны

- **Было (NeoForge 1.21.1):** файл в `assets/<ns>/blockstates/` для незарегистрированного блока
  разбирался и шумел.
- **Стало (26.2):** `BlockStateModelLoader` сопоставляет найденные файлы с картой `id → StateDefinition`,
  построенной обходом `BuiltInRegistries.BLOCK`, и для неизвестного id пишет
  `Discovered unknown block state definition {}, ignoring` на уровне **DEBUG**, не пытаясь его разобрать.
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/resources/model/BlockStateModelLoader.java:34,37,47`,
  `/opt/mc-src/net/minecraft/client/resources/model/BlockStateDefinitions.java:34-40`
- **Комментарий:** полезно как **отрицательный** результат: исторический мусор в `blockstates/` чистить
  в рамках порта не обязательно, он не ломает загрузку ресурсов и не даёт ошибок. Формат значения
  варианта при этом не сломался: `{"variants": {"": {"model": "<ns>:block/<x>"}}}` из 1.21.1 разбирается
  в 26.2 как есть — `BlockStateModel.Unbaked.CODEC` сводится к `Variant.MAP_CODEC`.

### Половина рантайм-копилки MineColonies к моду-библиотеке не относится — и это видно грепом

- **Стало (26.2):** четыре из двенадцати записей `findings/minecolonies/FINDINGS-RUNTIME.md` в Structurize
  **структурно невозможны**, и это проверяемо до запуска:
  1. «компоненты не привязаны» — ни одного `new ItemStack(...)` в статическом инициализаторе или в
     конструкторе, вызываемом на mod init;
  2. «reload-листенер не имеет права строить `ItemStack`» — у мода **один** reload-листенер, клиентский,
     он чистит кэш рендерера и ничего не декодирует;
  3. «реестр с нерегистрируемым дефолтом» — своих реестров нет ни одного;
  4. «типы аргументов команд» — свои `ArgumentType` не регистрируются, дерево команд стоит на ванильных.
- **Подтверждено:** `grep -rn "FabricRegistryBuilder\|createDefaulted"` → 0;
  `grep -rn "ArgumentTypeRegistry\|registerArgumentType"` → 0; `grep -rn "registerReloadListener"` → 1
  (клиентский); `grep -rn "static final ItemStack"` → 0
- **Комментарий:** вывод для следующего порта: эти четыре дефекта привязаны не к 26.2, а к **наличию у
  мода своей модели данных** — собственных реестров, своих datapack-листенеров, своих типов аргументов,
  `ItemStack` в статике. Мод-библиотека без них проходит их насквозь, и тратить на них ступень не надо:
  достаточно четырёх грепов выше. А вот датаген-ступень (`modId`, ресурсные корни) и
  `useBlockDescriptionPrefix` **от размера мода не зависят** и выстрелили здесь ровно так же.

  Второе отличие — про сверку с оракулом: у MineColonies эволюция кодеков задела 396 файлов, а здесь все
  шесть сгенерированных совпали с оракулом 1.21.1 **побайтно**, потому что сериализация тегов между
  1.21.1 и 26.2 не двигалась. Мод, у которого датаген только теговый, можно сверять простым `diff`, не
  заводя классификацию расхождений.
