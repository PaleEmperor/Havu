# Havu

**An illustration studio I made for my wife, Sini.**

[**Download Havu for Android**](https://github.com/PaleEmperor/Havu/releases/download/v0.1.0-beta.52/havu-beta.apk) · [All releases](https://github.com/PaleEmperor/Havu/releases)

I started making Havu because I wanted Sini to have somewhere of her own to draw.
A little studio on her tablet, with brushes she could make her own, illustrations
she could scale into shop menus and posters, and just enough pine green. The
duck and bear on the Projects screen are the two of us.

It’s a love letter to her. If it turns out to be useful to you too, I’d love
for you to use it, share it, or make it your own.

**Made with ♥ for Sini by Björn**

## Get the Android beta

Open the download link above on your Android tablet, then open
`havu-beta.apk` and follow the installation prompts. This is a beta for ARM64
Android devices, built with the Galaxy Tab and S Pen in mind.

Havu works offline. It has editable vector layers, pixel paint layers,
customizable brushes, typography, and SVG and PNG export. Drawing requires
no account or subscription, and Havu has no AI features.

## Run and inspect

Use Godot **4.7.2**. Import `project.godot` and press **F5**.

```sh
./tools/dev.sh          # run the app
./tools/dev.sh editor   # open development tools
./tools/test.sh         # isolated headless checks
```

Godot's Remote scene tree and Debugger work while the app runs. **F12** opens
Havu's live pressure, frame-rate, memory and document monitor.

## Workspace

On Android, Havu follows the tablet’s portrait or landscape orientation. The
workspace adjusts to the window size. Rotation keeps the artwork’s dimensions,
and a zoomed view keeps its current zoom and centered point.

Havu starts on Projects. Create a blank canvas, open an existing file, choose a
recent project, or open the editable café example. Use **Resume last session**
to pick up the most recent workspace. The **havu** button in the editor returns
to Projects.

Your first blank illustration opens the short **Getting started** tour.
Skip it any time, or replay it from **⋯ → Getting started** in the editor.

The icon rail uses familiar drawing tools. The curved stroke in the top bar opens
the brush library; each preview is drawn by the same geometry engine as the canvas.
Tap the top-bar swatch to open the movable Color panel. **Wheel** previews color
as you drag. **Sliders** lets you enter exact RGB or HSV values. **Palette**
contains the Pine & Tide colors and your saved swatches. The current swatch,
hex field, eyedropper, and six recent colors are available in every view.
Saved and recent swatches survive restart. The stacked-sheets icon toggles layers.
In **Workspace settings**, drag **UI scale** between 80% and 130% to resize the
interface live. The setting is saved on release. **Reset** restores 100%.
The stroke icon opens **Library**, and the sliders icon opens **Settings** in
the same **Brushes** panel. Switch between the two tabs without moving or
resizing the panel. The whole panel can be moved, resized, or docked.
Drag any workspace panel
toward another panel’s edge to join them in a row or column. Join individual
panels inside a group to build nested layouts. The preview outlines the full
result. Use **Move group** to reposition the group or drag an individual panel
header away to detach it. The three-dot menu contains workspace options. The three-line File menu contains New, Open, Save, Save As and Export.
Drag a panel by its header. The outline previews where it will dock before
you release. Drop on the bin when it reads **Release to hide** to close a panel. The toolbar keeps its direction at the first dock preview. Drag closer to the
edge to preview vertical at the sides or horizontal at the top or bottom. Drag the corner grip to resize a panel. Lists, text and the color wheel use the
extra room, and compact panels scroll. Use **Panels**
in the top bar to reopen it. Havu remembers panel layouts. Under **⋯ → Workspace
settings**, choose the toolbar orientation or turn off edge snapping, automatic
rotation, the drag bin, contextual actions, or footer metrics.

- **B** Brush · **V** Select · **A** Nodes · **E** Eraser · **G** Fill
- **I** Picker · **R** Rectangle · **O** Ellipse · **T** Text · **H** Hand
- **One finger** pan · **Two fingers** pan and pinch to zoom
- **Space + drag** pan · **Wheel** zoom · **Ctrl+0** fit
- **Ctrl+Z** undo · **Ctrl+Shift+Z** redo · **Ctrl+D** duplicate
- **Ctrl+S** save · **Ctrl+Shift+S** save as · **Ctrl+O** open · **Ctrl+N** new
- **Escape** cancel current gesture · **Delete** remove selected object

Enable **Draw with finger** in **⋯ → Input settings** to draw with one finger.
On Android, choose **Detect pen button** in the same menu, then press one end
of the rocker while it is near the screen. Assign **Color picker**, **Eraser**,
or **Pan canvas** to each end separately. Hold it while tapping or dragging.
Two-finger navigation still works, and the Hand tool pans with one finger.

The editable café menu is hand-authored vector artwork. Select an element to move
it, drag its lower-right corner to scale it, or use Nodes to reshape a stroke.
Select text to open Typography. Tap the current font to browse the 58 bundled
faces. Each name is shown in its own typeface. Use **Add fonts…** to import
.ttf or .otf files into Havu.

On Android, tap a text or number field to open Havu’s keyboard. The text
keyboard includes symbols, accents, and a **Device keyboard** option when
Android makes it available.

## Canvas size

Use **File → Resize canvas** to change an existing illustration’s width or
height. Tap **Width** or **Height** to open Havu’s number pad. Choose
**Adapt vector layout** to keep artwork near its original edges and corners
while scaling it proportionally. Grouped objects keep their relative spacing.
**Scale artwork to fit** scales and centers the illustration as a whole. Resizing the bounds of a paint canvas keeps its pixel
scale and crops paint outside smaller bounds. Undo restores the previous size
and artwork.

## Shapes and paths

Open **Shapes** on the tool rail for rectangles, rounded rectangles, squares,
ellipses, circles, triangles, diamonds, stars, lines and arrows. Drag on the
page to draw one. **Style** controls fill and outline separately, including
their colors and transparency, outline width and overall opacity. Turn off
Fill for a hollow shape. Select an existing shape and open **Style** to edit it.

Use **Pen path** to tap out a custom outline. **Finish** leaves it open, and
**Close** makes a fillable shape. Use **Nodes** to reposition its points.
Choose **Add node** beside the Nodes tool and tap a path, polygon edge, or brush
stroke to add a point you can drag. **Spread** controls how much of the line
bends around the node. Paths start at 0% for single-point editing, and brush
strokes start at 25% for a gentle local bend. SVG export keeps these shapes editable at any size. Imported photos and other
pixel images stay raster images when included in an SVG. The **Fill** bucket
colors vector shapes and can add an editable fill inside touching vector lines
or brush outlines.

Open **Select** on the tool rail and pick **Rectangle**, **Square**,
**Ellipse**, **Circle**, or **Freehand** to select whole objects enclosed by an area. Drag a selected
object to move the selection together. **Duplicate** and **Delete** work
across unlocked layers. Use **Paint inside selection** to use the area itself
as a brush boundary, even when it contains no objects.

Select several vectors and choose **Group** to keep them together. Tap any
member to select the group. Drag it to move, or drag the lower-right handle
to scale it proportionally. **Ungroup** makes the objects individually selectable.

## Layers

New illustrations start with an editable vector layer. Use **New vector** to
add another, or **Layers → … → New paint layer** to paint with pixels.

On a vector layer, **Layers → ⋯ → Merge touching** joins compatible solid
ink and same-color filled shapes as you draw. Nearly meeting ink tips can join,
and a closed outline keeps its center transparent. The toggle applies to marks
added during that run. Turning it on again starts a fresh run.

Drag the **Opacity** slider to preview the active layer and release to commit
one undo step. The row lock protects its artwork, opacity, name and position
in the stack. The checkerboard button enables **Alpha lock**. New brush marks
stay inside the layer’s solid vector artwork. Imported images and translucent
areas are outside the current alpha-lock painting area.

Use **⋯ → Merge Down** to combine the active layer with the one below, or
**Merge Visible** to combine visible, unlocked layers while keeping hidden
layers. The original marks stay editable and their opacity is preserved.
Undo restores the pre-merge stack.

Use **Solo** beside **New layer** to work on one layer in isolation. Solo follows
the selected layer and leaves visibility, history, and exports intact. Tap it
again to return to the full stack.

## Painting and brushes

Havu includes 124 offline brushes across nine categories, including Watercolor
and Effects. Search by brush or collection name, or open My brushes for saved and
imported presets. Each row previews the brush using the canvas renderer. Light
pressure on a mixing brush picks up more underlying color. Firm pressure adds
more of the selected color. In **Brush settings**, edit size, opacity,
stabilization and spacing. Open **Pressure**, **Tip & texture** and **Mixing**
for the controls available on that brush engine. The sample stays visible as
you scroll and updates as you make changes. The **Test pad** lets you try the
brush separately from the illustration. Use **Save as** to make a personal
preset, **Update** to save edits to it, and **Reset** to reload the saved values.
Personal brushes can be shared as `.havubrush` files.

Tap the star beside the category picker to add the active brush to
**Favorites**. **Recent** lists your latest brushes. Both shelves survive
restart. You can switch brushes while tuning and return to your unsaved
settings during the same session. Use **Save as** or **Update** to keep them.

Use **Pressure** to set the pen response range and tune width and opacity
independently. **Taper** controls how the start and end of a stroke narrow.
The preview shows both ends, and Havu applies the end taper when you lift the
pen. Under **Mixing**, set pigment load to 0% to blend existing colors.

The library includes 73 vector adaptations of CC0 brush settings. The original
settings informed Havu’s brush size, opacity, mixing, pressure response and tip
shape. Havu generates the stroke previews locally. The catalog records each
upstream preset path. [MyPaint Brushes v2.0.2](https://github.com/mypaint/mypaint-brushes/tree/v2.0.2),
[SenlinOS MyPaintBrushes-GIMP](https://github.com/SenlinOS/MyPaintBrushes-GIMP/tree/069bfc75f6595af42305ce3c020a905b58aa4a68).

The engine stores vector geometry, pressure and colors rather than a bitmap of
the canvas. Paint and texture are **approximations**, not Procreate's pigment
engine. Soft edges use several translucent vector bands; grain uses vector
flecks. Very large documents or long textured strokes may become slow.

Fill works on vector shapes and areas enclosed by touching lines or brush
outlines. Select a shape or a closed outline and enable **Paint inside selection**
to clip new brush marks. The eraser removes whole vector objects on vector layers.

## Images, layers and transparency

Use **File → Import image as layer** for PNG, JPEG or WebP photos and logos.
Havu embeds the image so the project can move without its source file. Imported
images remain pixel images and can be moved or resized. The import limit is
8 MB per file and 4096 pixels per edge.

Use **Layer actions** to set opacity, duplicate a layer, or export the active
layer as a transparent PNG at the whole canvas size. Turn off **Show canvas
background** in File for transparent whole-project exports. The checkerboard
is a workspace guide. SVG exports retain vector marks and text and embed
imported images as raster assets.

## Files and recovery

`.havu` files are versioned JSON documents with layers, text, paths, pressure and
colors. Normal filesystem saves stage a temporary file and rename it only after
writing succeeds. Android document-provider URIs use an internal recovery copy
before writing the selected URI; provider writes cannot promise atomic rename.

A recovery document is written about every 12 seconds and when the app loses
focus or closes. Save / Save As creates an explicit project file outside recovery.
Switching projects preserves unsaved artwork as a recovery copy in Recent
projects. Select **Resume last session** on startup to restore the latest canvas.

SVG export embeds the bundled faces used in the illustration. Imported fonts
are installed in Havu on the current device. Install the same font files on
another device to keep the text editable there. PNG preserves the rendered
appearance. PNG export uses the native renderer at up to 2× document size, capped at
4096 pixels on the longest edge. **PNG export needs a graphics-enabled runtime
and has not been validated by the headless checks.**

## Android status

The Android beta is distributed as a signed ARM64 APK. The source includes the
Android export preset and a USB build and install helper. S Pen input, file
pickers, and export behavior can vary across Android devices. [Android setup](docs/ANDROID.md)

## Free brush resources

Havu bundles its own procedural presets and adaptations of public brush settings. Related resources include
[MyPaint's CC0 brush settings](https://github.com/mypaint/mypaint-brushes/blob/master/Licenses.dep5)
and [GDQuest's CC BY 4.0 Krita brushes](https://github.com/GDQuest/krita-free-brushes).
These are research sources, **not compatible downloads**: `.myb`, Krita bundles,
Procreate `.brush` and Clip Studio `.sut` files cannot currently be imported.
The app's resource dialog states that limitation before opening either collection.

## Source layout

- `scripts/document.gd`: data validation, history, atomic filesystem saving.
- `scripts/artwork.gd`: vector geometry, drawing, picking, color sampling, SVG.
- `scripts/canvas.gd`: pen/touch input, editing, pressure and navigation.
- `scripts/studio.gd`: desktop/tablet UI, recovery, file dialogs, PNG export.
- `scripts/brush_library.gd` / `brush_preview.gd`: presets and real stroke previews.
- `tests/test_app.gd`: document and application workflow checks.

## License

Havu’s original source and artwork are shared under the MIT License. The
bundled fonts keep their own licenses, and the brush notices credit the
upstream collections. [MIT License](LICENSE) · [Third-party notices](docs/THIRD_PARTY.md)
