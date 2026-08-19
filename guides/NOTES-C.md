# NOTES-C — NeoForge 1.21.1 → Fabric 26.2, **client area** (renderers, models, screens, HUD, sounds, mixins)

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
