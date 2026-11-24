# Android build and tablet testing

To install the beta on an ARM64 tablet, open the APK on the device and follow
Android's installation prompts. [Download the APK](https://github.com/PaleEmperor/Havu/releases/download/v0.1.0-beta.74/havu-beta.apk)

Havu’s Android beta uses Godot’s ARM64 debug APK export. Build with
`tools/android.py` to compile the native keyboard and S Pen support into the APK.

## Build the APK on Linux

Save these files to `~/Downloads` with their original names:

1. `commandlinetools-linux-15859902_latest.zip`, the Linux package under
   **Command line tools only**. [Android Developers downloads](https://developer.android.com/studio#command-line-tools-only)
2. `Godot_v4.7.2-stable_android_debug.perfetto.apk`, the official Android debug
   template. [Godot 4.7.2 template download](https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_android_debug.perfetto.apk)

If the matching Android templates are already installed in Godot, skip the
second download. On the development machine, the script can reuse the OpenJDK
17 bundled with Prism Launcher. Run the following from the project folder in a
normal terminal with internet access:

```sh
python3 tools/android.py setup && python3 tools/android.py build
```

Setup verifies the downloads, configures the project-local debug key and
installs Platform Tools, Build Tools 35.0.1 and Android Platform 35. Review and
accept the SDK licenses if prompted. If downloads are in another folder, pass
`--downloads /path/to/folder` to `setup`. For an already configured SDK, run
`python3 tools/android.py doctor` followed by `python3 tools/android.py build`.
[Godot's Android export guide](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html)

The build checks the APK signature before writing `builds/havu-beta.apk`.
The installed package is `studio.havu.illustration`.

The APK preset enables ARM64 and requests no Internet or broad storage permission.
Android's native file picker grants access to individual chosen documents.

## Connect the Samsung tablet

Enable Developer options and USB debugging, connect a USB data cable, unlock the
tablet and accept its computer authorization prompt. Follow the
[official Android device instructions](https://developer.android.com/studio/run/device).

```sh
python3 tools/android.py devices
python3 tools/android.py install
```

Installation requires exactly one authorized physical device. It uses `adb
install -r` to retain app data, then launches the app. It never uninstalls an app.
You can instead use Godot's Android one-click deployment once the SDK is configured.

## First test with Sini

1. Start from the splash and choose **New illustration** on the Projects screen.
   Draw on the starting vector layer. Try a short tap and then hold **Undo** to step
   backward through the brushwork. Create a shape and use **Nodes** to edit the
   brush stroke.
2. Open **Brushes**. Try Studio ink, Graphite, Chisel marker and Soft glaze.
   Switch between **Library** and **Settings** and confirm the panel stays in place.
   Draw several marks and try rectangle, ellipse, and freehand selection from **Select**.
3. Paint two overlapping colors, choose Color mixer, then compare very light and
   firm S Pen pressure. Check the pressure monitor with F12 if a keyboard is connected. Pen pressure and finger drawing preferences are under **⋯ → Input settings**.
4. Keep a palm on the screen. Fingers should navigate rather than paint by default.
   Finger events are suppressed during an active pen/mouse gesture. This is basic
   input filtering, not a validated Samsung palm-rejection implementation.
5. Pinch and pan, then zoom far into a stroke. The vector geometry should remain
   sharp; translucency bands and polygonal texture can become visible.
6. Draw an outline-only ellipse and select it from the middle. Choose **Paint inside**
   and brush over the edge. Repeat with a freehand marquee. Use **Paint freely** to
   clear the boundary, then test undo and SVG export.
7. Select and move artwork. Resize from its lower-right handle. Try Nodes on a stroke.
8. Add typed text. Browse fonts in **Typography**, import a .ttf or .otf with
   **Add fonts…**, and place text with it. Save a `.havu` file through the native
   picker and reopen it to check that the selected face is retained.
9. Export SVG and PNG and inspect both in another app. SVG font support differs
   between consumers; PNG should retain the exact native-rendered appearance.
10. Leave the app mid-session and return. Verify recovery without replacing your
    explicit saved project.
11. Tap the illustration name with a finger and rename it using the tablet keyboard.
    Dock and undock a panel to check its corners. Sample the visible color where two
    translucent strokes overlap, then zoom into fresh Ink, round Paint, and Mixer
    strokes and check the edges.
12. Add a pixel layer with **Layers → … → New paint layer**. Draw a closed outline
    and fill it with the bucket. Test the eraser, save the file, and reopen it.
    SVG exports embed the painted pixels alongside vector geometry.

Record Android version, exact tablet model, lag/crash steps, pressure readings,
and any unexpected drawing or file behavior. Do not call the Android build ready
for regular use until save/reopen and exported appearance pass on the device.
