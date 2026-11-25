# Havu

**A little illustration studio for Android tablets.**

[**Download the Android APK**](https://github.com/PaleEmperor/Havu/releases/download/v0.1.0-beta.78/havu-beta.apk) · [All releases](https://github.com/PaleEmperor/Havu/releases)

I wanted my wife to have somewhere of her own to draw. A little studio on her
tablet, with brushes she could make her own, artwork she could scale into shop
menus and posters, and just enough pine green.

Havu is a love letter to her. If it makes your drawing time a little nicer too,
I’d love for you to use it, share it, or make it your own.

**Made with ♥ for Sini by Björn**

## Install and start drawing

1. Open the download link on your ARM64 Android tablet. Open `havu-beta.apk`
   when it finishes downloading and follow the installation prompts.
2. Tap **New illustration** and choose a canvas preset or enter your own
   dimensions. The first blank project opens a short tour. You can skip it
   and replay it later from **⋯ → Getting started**.
3. Draw with a stylus. One finger pans by default, and two fingers pinch to zoom.
   To paint with your finger, turn on **Draw with finger** under **⋯ → Input settings**.

## Make the workspace yours

- **Brushes and color.** Tap the stroke preview to browse brushes or tune a
  preset. Tap the swatch to pick a color. Supported styluses can vary stroke
  width and opacity with pressure. Use **+** in the brush library to import
  `.havubrush` or `.myb` files into **My brushes**. Imported `.myb` settings are
  adapted to Havu’s brush engine. Review the preview and compatibility notes
  before adding a MyPaint brush.
- **Vector and paint layers.** Use editable vectors for shapes, lettering, and
  artwork you want to resize. Add a paint layer when you want to work with pixels.
  Selection starts on the active layer. Turn on **Select across visible layers**
  from the Select menu for artwork spread across layers. Turn on **Keep selecting**
  to add or remove objects and whole groups by tapping them. **Merge vectors**
  joins matching solid fills or solid ink on one layer into one editable shape.
  **Merge vectors on grouping** applies the same operation when you group artwork.
  In the selection action bar, use **Move to layer…** beside **Duplicate** and
  **Delete** to send artwork to a compatible layer or create a new vector layer.
  Tap a gap enclosed by shapes or lines on the active vector layer with **Fill**
  to turn the gap into its own editable shape.
- **Transform and arrange.** Drag the round selection handle to rotate. Open
  **Transform** for flips, quarter turns, and snapping to the canvas or 15°
  angles. **Align & arrange** aligns objects, spaces them evenly, and changes
  their drawing order within a vector layer.
- **Drawing symmetry and cutouts.** Open **Transform → Drawing symmetry…** to
  mirror your brush strokes or repeat them around a center. Use
  **Transform → Symmetry copies…** to mirror or repeat existing vector artwork.
  **Radial repeat…** uses the first point of a finished stroke as the center.
  For a cutout, select a filled vector shape, choose **Transform → Cut out a shape…**,
  and draw as many loops as you need. You can begin outside the shape or cross
  the canvas edge. Choose **Transform → Finish cutting** when you’re done.
- **Panels.** Drag a panel by its heading to move or dock it. Open **Panels** to
  bring it back, or change **UI scale** under **⋯ → Workspace settings** to make
  controls easier to reach.
- **Stylus buttons.** On supported pens, use **Detect pen button** in
  **Input settings** to assign the eraser, color picker, or pan.

## Save and share

Use **Open folder…** on the Projects screen to keep a folder of illustrations
together. Tap the arrow beside the canvas title to switch to another project
in that folder while you work.

Tap **Save** to keep an editable `.havu` project. Use **File** to export SVG or
PNG, or choose **Resume last session** on the Projects screen to pick up where
you left off. Under **File → Resize canvas**, **Preserve composition** moves the
illustration together and shrinks it only when needed to fit. Paint stays on
editable paint layers.

Projects containing rotated or mirrored objects require beta 55 or newer.
A union with disconnected parts requires beta 54 or newer. Projects using
earlier features still save in their existing format.

Havu is in beta and works offline. Drawing requires no account or subscription,
and Havu has no AI features.

## Open source

Havu’s original source and artwork are shared under the MIT License.
Bundled fonts keep their own licenses. [MIT License](LICENSE) · [Third-party notices](docs/THIRD_PARTY.md)
