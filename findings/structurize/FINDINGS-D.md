# FINDINGS-D — копилка знаний агента D (рендер), Structurize → Fabric / MC 26.2

Только то, чего **не было** в порт-ките (`PORT-ANY-MOD-26.2.md`, `NOTES-C.md`), в `FINDINGS-A.md`
и в `PORT-GAPS.md` порта Domum Ornamentum. Каждая находка с подтверждением.

---

## 0. Главное: как устроен кадр в 26.2

Уровень рисуется в две фазы: **extract** (снять состояние мира в render-state объекты) и
**submit → draw** (сложить узлы в очередь, потом отрисовать пофазно). Прямой отрисовки из мод-кода
нет вообще: нет `MultiBufferSource`, нет `VertexBuffer`, нет `ShaderInstance`, нет
`RenderSystem.applyModelViewMatrix`.

Точки входа мода — `net.fabricmc.fabric.api.client.rendering.v1.level.LevelRenderEvents`
(из `fabric-rendering-v1`, версия в пине — `25.3.1+6988455e9e`):

| Событие | Колбэк | Что даёт контекст |
|---|---|---|
| `START_MAIN` | `startMain(LevelTerrainRenderContext)` | `gameRenderer()`, `levelRenderer()`, `levelState()`, `sectionsToRender()` |
| `COLLECT_SUBMITS` | `collectSubmits(LevelRenderContext)` | **+ `submitNodeCollector()`, `poseStack()`** ← сюда мод кладёт геометрию |
| `AFTER_OPAQUE_TERRAIN`, `BEFORE_/AFTER_TRANSLUCENT_TERRAIN`, `AFTER_SOLID_FEATURES`, `AFTER_TRANSLUCENT_FEATURES`, `BEFORE_BLOCK_OUTLINE`, `BEFORE_GIZMOS`, `END_MAIN` | `LevelRenderContext` | те же поля |
| `END_EXTRACTION` | `endExtraction(LevelExtractionContext)` | `level()` (`ClientLevel`), `camera()` (`Camera`), `deltaTracker()` — но **collector'а нет** |

- **Подтверждено:** `javap` по
  `fabric-rendering-v1-25.3.1+6988455e9e.jar`, классы
  `.../api/client/rendering/v1/level/LevelRenderEvents{,$CollectSubmits}.class`,
  `LevelRenderContext.class`, `LevelExtractionContext.class`.
- **Комментарий:** `RenderLevelStageEvent.Stage` из NeoForge отобразить не на что — «стадий»
  больше нет, порядок отрисовки задаёт `RenderType` (§2). Практический приём: оставить свой enum
  стадий ради call-site'ов и прогонять их подряд внутри одного `COLLECT_SUBMITS` (так сделано в
  `util/WorldRenderMacros`).
  **Ловушка имени:** у Fabric есть свой `net.fabricmc.fabric.api.client.rendering.v1.WorldRenderContext` —
  это **не** `com.ldtteam.structurize.event.WorldRenderContext` и не `LevelRenderContext`.

---

## 1. Произвольная геометрия из мода: `submitCustomGeometry`

```java
// net.minecraft.client.renderer.OrderedSubmitNodeCollector:177
void submitCustomGeometry(PoseStack poseStack, RenderType renderType, SubmitNodeCollector.CustomGeometryRenderer r);
// net.minecraft.client.renderer.SubmitNodeCollector
interface CustomGeometryRenderer { void render(PoseStack.Pose pose, VertexConsumer buffer); }
```
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/SubmitNodeCollector.java`,
  `/opt/mc-src/net/minecraft/client/renderer/OrderedSubmitNodeCollector.java:177`,
  реализация — `/opt/mc-src/net/minecraft/client/renderer/SubmitNodeCollection.java:318-329`.
- **Комментарий:** прямая замена старому `bufferSource.getBuffer(type)` + ручному
  `buf.addVertex(matrix, x, y, z).setColor(...)`: тело `populateXxx(..., Matrix4f m, VertexConsumer buf)`
  переносится один в один, `m` берётся как `pose.pose()`. `VertexConsumer#addVertex(Matrix4fc,f,f,f)`
  и `setColor(int,int,int,int)` не изменились
  (`/opt/mc-src/com/mojang/blaze3d/vertex/VertexConsumer.java:16,18,110`).
- **Куда попадёт геометрия — решает сам `RenderType`** (`SubmitNodeCollection:322-328`):
  `isOutline()` → фаза outline, `hasBlending()` → `translucentCustomGeometry`, иначе → `solid`.
  То есть «когда рисовать» больше не выбирается стадией события.
- Буфер строится в `CustomFeatureRenderer#buildGroup`
  (`/opt/mc-src/net/minecraft/client/renderer/feature/CustomFeatureRenderer.java`); `PoseStack.Pose`
  копируется на момент submit'а, после вызова можно спокойно `popPose()`.

### Новый абстрактный член `VertexConsumer#setLineWidth(float)`
Любой собственный делегирующий `VertexConsumer` (у нас `client/ChunkOffsetBufferBuilderWrapper`)
не компилируется, пока не добавить `setLineWidth`.
**Подтверждено:** `/opt/mc-src/com/mojang/blaze3d/vertex/VertexConsumer.java:30`.

---

## 2. Свой `RenderType` без `RenderStateShard`

`RenderStateShard`, `RenderType.CompositeState.builder()` и все шарды (`LEQUAL_DEPTH_TEST`,
`TRANSLUCENT_TRANSPARENCY`, `COLOR_WRITE`, `NO_CULL`, …) удалены. Осталась одна фабрика:

```java
RenderType.create(String name, RenderSetup setup);                       // rendertype/RenderType.java:41
RenderSetup.builder(RenderPipeline).createRenderSetup();                 // rendertype/RenderSetup.java:76
```
Каждый бывший шард стал свойством **иммутабельного** `RenderPipeline`:

| шард 1.21.1 | 26.2 |
|---|---|
| `setTransparencyState(TRANSLUCENT_TRANSPARENCY)` | `.withColorTargetState(new ColorTargetState(BlendFunction.TRANSLUCENT))` |
| `setTransparencyState(GLINT_TRANSPARENCY)` | `BlendFunction.GLINT` |
| `setDepthTestState(LEQUAL_DEPTH_TEST)` | `new DepthStencilState(CompareOp.GREATER_THAN_OR_EQUAL, writeDepth)` ← **обратный depth!** |
| `setDepthTestState(GREATER_DEPTH_TEST)` | `CompareOp.LESS_THAN_OR_EQUAL` |
| `RenderSystem.depthFunc(GL_NEVER/GL_ALWAYS)` | `CompareOp.NEVER_PASS` / `CompareOp.ALWAYS_PASS` |
| `setCullState(CULL/NO_CULL)` | `.withCull(true/false)` |
| `setWriteMaskState(COLOR_WRITE)` | `DepthStencilState(..., writeDepth=false)` |
| `setWriteMaskState(COLOR_DEPTH_WRITE)` | `DepthStencilState(..., writeDepth=true)` |
| `VertexFormat.Mode.TRIANGLES/DEBUG_LINES` | `PrimitiveTopology.TRIANGLES/DEBUG_LINES` (`com.mojang.blaze3d.PrimitiveTopology`) |
| `bufferSizeIn`, `useDelegateIn`, `needsSortingIn` | исчезли; сортировка — `RenderSetup.builder(...).sortOnUpload()` |

- **Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/rendertype/RenderType.java:41`,
  `.../rendertype/RenderSetup.java:76,126-200`,
  `/opt/mc-src/com/mojang/blaze3d/pipeline/DepthStencilState.java:11`
  (`DEFAULT = new DepthStencilState(CompareOp.GREATER_THAN_OR_EQUAL, true)` — доказательство
  обратного depth-буфера), `/opt/mc-src/com/mojang/blaze3d/platform/CompareOp.java`,
  `/opt/mc-src/com/mojang/blaze3d/pipeline/BlendFunction.java:12-19`,
  `/opt/mc-src/com/mojang/blaze3d/PrimitiveTopology.java`.

**Готовый рецепт «POSITION_COLOR без текстуры»** — не изобретать шейдер, а наследовать снippet:

```java
RenderPipelines.register(RenderPipeline.builder(RenderPipelines.DEBUG_FILLED_SNIPPET)
    .withLocation(Identifier.fromNamespaceAndPath(MOD_ID, "pipeline/my_lines"))
    .withVertexBinding(0, DefaultVertexFormat.POSITION_COLOR)
    .withPrimitiveTopology(PrimitiveTopology.TRIANGLES)
    .withColorTargetState(new ColorTargetState(BlendFunction.TRANSLUCENT))
    .withDepthStencilState(new DepthStencilState(CompareOp.GREATER_THAN_OR_EQUAL, true))
    .withCull(true)
    .build());
```
`DEBUG_FILLED_SNIPPET` = `GLOBALS_SNIPPET` + `BindGroupLayouts.MATRICES_PROJECTION` +
шейдеры `core/position_color` (`/opt/mc-src/.../RenderPipelines.java:177-186`). Своих `.glsl` писать
не нужно. Для линий с шириной есть `LINES_SNIPPET`, но у него формат
`POSITION_COLOR_NORMAL_LINE_WIDTH`, а не `POSITION_COLOR`.

`RenderPipelines.register(...)` кладёт пайплайн в `PIPELINES_BY_LOCATION`, откуда его забирает
`ShaderManager` при перезагрузке ресурсов (`/opt/mc-src/.../ShaderManager.java:153`) — регистрация
из статического инициализатора клиентского класса попадает в предзагрузку.

### ⚠️ Три символа живы только благодаря transitive access widener Fabric
`RenderType.create`, `RenderPipelines.register`, `RenderPipelines.*_SNIPPET` в **сыром**
деобфусцированном jar'е package-private/private. В `/opt/mc-src` они выглядят публичными и над
каждым стоит javadoc «Access widened by fabric-transitive-access-wideners-v1 to accessible».

- **Подтверждено:** `javap -cp minecraft-merged-deobf-26.2.jar net.minecraft.client.renderer.rendertype.RenderType`
  → `static ... create(...)`; и строки в
  `fabric-transitive-access-wideners-v1-8.1.4+67c847259e.jar!/fabric-transitive-access-wideners-v1.classtweaker`:
  ```
  transitive-accessible method net/minecraft/client/renderer/rendertype/RenderType create (Ljava/lang/String;Lnet/minecraft/client/renderer/rendertype/RenderSetup;)Lnet/minecraft/client/renderer/rendertype/RenderType;
  transitive-accessible method net/minecraft/client/renderer/RenderPipelines register (Lcom/mojang/blaze3d/pipeline/RenderPipeline;)Lcom/mojang/blaze3d/pipeline/RenderPipeline;
  transitive-accessible field  net/minecraft/client/renderer/RenderPipelines DEBUG_FILLED_SNIPPET Lcom/mojang/blaze3d/pipeline/RenderPipeline$Snippet;
  ```
- **Комментарий:** в «javac без Loom» это даёт **ложные** `has private access` / `is not public`.
  Формат AW у Fabric 26.2 — **`.classtweaker`**, а не `.accesswidener`, ключевое слово
  `transitive-accessible`. Лечится прогоном по ремапнутому jar'у из `loom-cache` проекта
  (см. `FINDINGS-B2.md`), что `typecheck.sh` и делает.

---

## 3. Блочные модели: `BakedModel` мёртв, есть `BlockModelResolver` + `BlockModelRenderState`

```java
BlockModelResolver resolver = new BlockModelResolver(Minecraft.getInstance().getModelManager());
BlockModelRenderState st = new BlockModelRenderState();
resolver.update(st, blockState, BlockDisplayContext.create());   // резолв, можно один раз и закэшировать
if (!st.isEmpty()) st.submit(poseStack, submitNodeCollector, lightCoords, OverlayTexture.NO_OVERLAY, 0);
```
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/block/BlockModelResolver.java`,
  `/opt/mc-src/net/minecraft/client/renderer/block/BlockModelRenderState.java:74,110`,
  `/opt/mc-src/net/minecraft/client/renderer/block/model/BlockDisplayContext.java`.
- **Что заменяет:** `BlockRenderDispatcher#renderSingleBlock(...)` и `#renderBatched(...)` — обоих
  нет, класса `BlockRenderDispatcher` нет вовсе.
- **Важно:** `BlockModelRenderState#submit` сама выбирает лист — `Sheets.cutoutBlockItemSheet()`
  или `Sheets.translucentBlockItemSheet()` (`BlockModelRenderState:67`). Навязать свой `RenderType`
  (как раньше `NeoForgeRenderTypes.ITEM_LAYERED_TRANSLUCENT`) нельзя. Это **item**-овые листы:
  ни ambient occlusion, ни затенения граней от соседей.
- `BlockModelRenderState` можно сабмитить повторно каждый кадр: `submitBlockModel` копирует
  `PoseStack.Pose` и список `BlockStateModelPart` (`SubmitNodeCollection.java:225-228`).
- В `BlockEntityRendererProvider.Context` резолвер уже лежит: `context.blockModelResolver()`
  (`/opt/mc-src/net/minecraft/client/renderer/blockentity/BlockEntityRendererProvider.java:23-31`).

### Свет: `LevelRenderer.getLightColor` больше нет
`LightCoordsUtil.getLightCoords(BlockAndLightGetter level, BlockPos pos)`; `pack/max/withBlock` там же.
`LightTexture.FULL_BRIGHT` (`=15728880`) → `LightCoordsUtil.FULL_BRIGHT`.
**Подтверждено:** `/opt/mc-src/net/minecraft/util/LightCoordsUtil.java:9,13,48,105`.

### `BlockAndTintGetter` не удалён — он переехал в клиентский пакет
`FINDINGS-A.md` пишет «`BlockAndTintGetter` и `getShade` исчезли». Уточнение: исчез
`net.minecraft.world.level.BlockAndTintGetter`, но существует
**`net.minecraft.client.renderer.block.BlockAndTintGetter extends BlockAndLightGetter`**
с `cardinalLighting()` и `getBlockTint(BlockPos, ColorResolver)`. `getShade` в нём действительно нет.
**Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/block/BlockAndTintGetter.java`.

---

## 4. `BlockEntityRenderer` — точный контракт 26.2

```java
public interface BlockEntityRenderer<T extends BlockEntity, S extends BlockEntityRenderState> {
    S createRenderState();
    default void extractRenderState(T be, S state, float partialTicks, Vec3 cameraPosition,
                                    ModelFeatureRenderer.@Nullable CrumblingOverlay breakProgress);
    void submit(S state, PoseStack poseStack, SubmitNodeCollector collector, CameraRenderState camera);
    default boolean shouldRenderOffScreen();          // БЕЗ аргумента (было shouldRenderOffScreen(T))
    default int getViewDistance();
    default boolean shouldRender(T be, Vec3 cameraPosition);
}
```
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/blockentity/BlockEntityRenderer.java`.
- **Двухпараметрический дженерик** — самая частая ошибка при порте
  (`wrong number of type arguments; required 2`).
- Базовое заполнение — статический `BlockEntityRenderState.extractBase(be, state, breakProgress)`
  (**не** `super.extractRenderState`, это интерфейс); поля `blockPos`, `blockEntityType`,
  `lightCoords`, `breakProgress`; `blockState` приватный.
  **Подтверждено:** `/opt/mc-src/.../blockentity/state/BlockEntityRenderState.java:25`.
- `BlockEntityRenderer#getRenderBoundingBox(T)` — **удалён**, per-BE фрустум-куллинга у мода нет.
- Регистрация: `net.fabricmc.fabric.api.client.rendering.v1.BlockEntityRendererRegistry.register(
  BlockEntityType<E>, BlockEntityRendererProvider<? super E, ? super S>)` — вывод `S` работает,
  `MyRenderer::new` подставляется без явных типов.

### `BlockEntityRenderDispatcher` / `EntityRenderDispatcher` — что осталось
```java
// BlockEntityRenderDispatcher
void prepare(Vec3 cameraPos);                                     // было prepare(Level, Camera, HitResult)
@Nullable <E,S> S tryExtractRenderState(E be, float partialTicks, @Nullable CrumblingOverlay, boolean isGloballyRendered);
<S> void submit(S state, PoseStack, SubmitNodeCollector, CameraRenderState);
// EntityRenderDispatcher
void prepare(Camera camera, Entity crosshairPickEntity);          // Level из сигнатуры ушёл
boolean shouldRender(E entity, Frustum culler, double camX, camY, camZ);
EntityRenderState extractEntity(E entity, float partialTicks);
<S> void submit(S state, CameraRenderState camera, double x, double y, double z, PoseStack, SubmitNodeCollector);
```
- **Подтверждено:** `/opt/mc-src/.../blockentity/BlockEntityRenderDispatcher.java:68,72,98`,
  `/opt/mc-src/.../entity/EntityRenderDispatcher.java:122,127,132,147`.
- Публичных полей `.level`, `.camera`, `.cameraHitResult` у `BlockEntityRenderDispatcher` больше нет;
  у `EntityRenderDispatcher` остались `camera` и `crosshairPickEntity`.
- **Следствие для фейк-левелов:** поддельная `Camera` больше не нужна (`Camera#setup` удалён) —
  достаточно `beDispatcher.prepare(локальнаяПозицияКамеры)`.
- `EntityRenderDispatcher#distanceToSqr(double,double,double)` удалён (остался `distanceToSqr(Entity)`);
  `cameraOrientation()` удалён — брать `levelState().cameraRenderState.orientation` (`Quaternionf`).

---

## 5. `LevelRenderState` / `CameraRenderState` — откуда брать камеру и фрустум

```java
LevelRenderState st = ctx.levelState();
CameraRenderState cam = st.cameraRenderState;
Vec3        camPos  = cam.pos;
Frustum     frustum = cam.cullFrustum;
Quaternionf orient  = cam.orientation;
Matrix4f    proj    = cam.projectionMatrix;
```
**Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/state/level/LevelRenderState.java:14`,
`/opt/mc-src/net/minecraft/client/renderer/state/level/CameraRenderState.java:16-31`.

### `Frustum#cubeInFrustum(DDDDDD)` — ловушка
Приватный **и** возвращает `int` (видимо при `-1` или `-2`), а не `boolean`. Правильный публичный
путь — `frustum.isVisible(AABB)`; расширять доступ не нужно. Есть ещё публичный
`int cubeInFrustum(BoundingBox)`.
**Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/culling/Frustum.java:85-94`.
Конструктор копирования `new Frustum(Frustum)` и `prepare(camX,camY,camZ)` живы (`:26,73`).

### `Minecraft#getDeltaTracker()`
`/opt/mc-src/net/minecraft/client/Minecraft.java:2664` — единственный способ получить `DeltaTracker`
в фазе `COLLECT_SUBMITS` (в `LevelRenderContext` его нет, только в `LevelExtractionContext`).

---

## 6. Текст в мире: `Font#drawInBatch` → `submitText`

```java
void submitText(PoseStack poseStack, float x, float y, FormattedCharSequence string, boolean dropShadow,
                Font.DisplayMode displayMode, int lightCoords, int color, int backgroundColor, int outlineColor);
```
**Подтверждено:** `/opt/mc-src/net/minecraft/client/renderer/OrderedSubmitNodeCollector.java:44-56`.
`Font.DisplayMode.{NORMAL,SEE_THROUGH}` сохранились. Порядок аргументов **другой**, чем у
`drawInBatch` (`text, x, y, color, dropShadow, matrix, buffers, mode, backgroundColor, light`).
`Component#getVisualOrderText()` даёт нужный `FormattedCharSequence`.

---

## 7. `ClientTooltipComponent` переписан на extract

```java
int getHeight(Font font);                                    // ← появился параметр Font
int getWidth(Font font);
default void extractText(GuiGraphicsExtractor g, Font font, int x, int y);
default void extractImage(Font font, int x, int y, int w, int h, GuiGraphicsExtractor g);
default boolean showTooltipWithItemInHand();
```
**Подтверждено:** `/opt/mc-src/net/minecraft/client/gui/screens/inventory/tooltip/ClientTooltipComponent.java`.
`renderText(Font,int,int,Matrix4f,MultiBufferSource.BufferSource)` и
`renderImage(Font,int,int,GuiGraphics)` удалены. Рисование —
`g.text(font, Component, x, y, color, dropShadow)`, `g.item(stack,x,y)`,
`g.itemDecorations(font, stack, x, y)` (`GuiGraphicsExtractor.java:271,874,912`).
Регистрация на Fabric — `ClientTooltipComponentCallback.EVENT` из `fabric-rendering-v1`.

---

## 8. Кейбинды: категория стала `Identifier`, конфликт-контекстов нет

```java
new KeyMapping(String name, InputConstants.Type type, int value, KeyMapping.Category category);
KeyMapping.Category.register(Identifier);       // record Category(Identifier id)
// ключ перевода: id.toLanguageKey("key.category")  →  key.category.<namespace>.<path>
KeyMappingHelper.registerKeyMapping(KeyMapping); // net.fabricmc.fabric.api.client.keymapping.v1
```
- **Подтверждено:** `/opt/mc-src/net/minecraft/client/KeyMapping.java:90,92,206,227,232`;
  `javap net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper` из
  `fabric-key-mapping-api-v1-2.0.5+e2bdee789e.jar`.
- **Строковых категорий больше нет** — старый ключ `key.<mod>.categories.general` в lang-файле
  мёртв, нужен новый `key.category.<mod>.<path>`.
- `IKeyConflictContext` / `KeyConflictContext` / `KeyModifier` — **чисто NeoForge**, аналога нет ни
  в ванили, ни во fabric-api. Кейбинд с модификатором (`Shift+←`) выразить нечем; контекстную
  активность приходится проверять вручную в обработчике.
- `KeyMapping#isActiveAndMatches(...)` — тоже NeoForge, в ванили нет.

---

## 9. Что окончательно мертво в рендере (проверено `find`)

| Символ | Статус |
|---|---|
| `VertexBuffer`, `ShaderInstance`, `MultiBufferSource`, `ItemBlockRenderTypes`, `BakedModel`, `BlockRenderDispatcher`, `LightTexture`, `BlockEntityWithoutLevelRenderer` | файла нет в `/opt/mc-src` |
| `com.mojang.blaze3d.shaders.Uniform` | переехал в `com.mojang.blaze3d.opengl.Uniform` (бэкенд-специфичный, моду недоступен) |
| `GlStateManager` | переехал в `com.mojang.blaze3d.opengl.GlStateManager`; трогать нельзя — в 26.2 есть ещё и Vulkan-бэкенд |
| `RenderSystem.applyModelViewMatrix`, `.blendFunc`, `.enableBlend`, `.depthFunc`, `.getShader` | удалены (остались `getModelViewStack()`, `getModelViewMatrixCopy()`) |
| `FogRenderer` | переехал в `net.minecraft.client.renderer.fog.FogRenderer`, `setupFog/setupNoFog` нет |
| `RenderBuffers` | жив, но отдаёт только `fixedBufferPack()`, `sectionBufferPool()`, `stagedVertexBuffer()`; `bufferSource()`, `outlineBufferSource()`, `crumblingBufferSource()` удалены |
| `Entity#noCulling` | удалён; решение принимает `EntityRenderer#affectedByCulling(T)` (protected) |
| `EntityType#is(TagKey)` | удалён → `entityType.builtInRegistryHolder().is(tag)` |
| `glBlendColor` / глобальная blend-константа | выразить нечем: blend — свойство иммутабельного `RenderPipeline` |

---

## 10. Организационное

### `IFakeLevelBlockGetter#getAABB()` в реализации C8 отсутствует
`client/BlueprintRenderer` (1.21.1) звал `blueprint.getAABB()` — метод приходил из настоящей
`com.ldtteam.common.fakelevel.IFakeLevelBlockGetter`. В восстановленном
`compat/common/fakelevel/IFakeLevelBlockGetter` его нет. Обошлось построением `AABB` из
`getSizeX/Y/Z` на месте вызова; если понадобится ещё где-то — добавлять `default AABB getAABB()`
в интерфейс (зона A).

### `BlueprintUtils#instantiateTileEntities` держал мёртвый параметр
Сигнатура `(Blueprint, Level, Map<BlockPos, ModelData>)` непереносима: `ModelData` — NeoForge.
Единственный вызывающий (`BlueprintRenderer`) переписан на `BlueprintUtils.constructTileEntity(...)`
напрямую. Канал «данные от блок-сущности к модели» в 26.2 —
`RenderDataBlockEntity#getRenderData()` (`fabric-block-getter-api-v2`), читается через
`BlockGetter#getBlockEntityRenderData(BlockPos)`; отдельная карта не нужна.
