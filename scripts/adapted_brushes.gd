extends RefCounted
## Vector adaptations of CC0 brush settings. Havu generates its own stroke previews.
const SOURCES = {
	"MyPaint": "https://github.com/mypaint/mypaint-brushes/tree/v2.0.2",
	"SenlinOS": "https://github.com/SenlinOS/MyPaintBrushes-GIMP/tree/069bfc75f6595af42305ce3c020a905b58aa4a68",
}

# Each row keeps its upstream path alongside the tuned Havu parameters.
const COLLECTIONS = {
	"MyPaint": [
		["Blend and paint", "Blending", "mix", 59, 0.8, 0.92, 0.19, {"pressure_curve": 0.15}, "brushes/classic/blend+paint.myb"],
		["Blending knife", "Blending", "mix", 104, 0.83, 0.99, 0.29, {"pressure_curve": 0.6, "tip_ratio": 0.2, "tip_angle": 0}, "brushes/classic/blending_knife.myb"],
		["Classic calligraphy", "Markers & lettering", "marker", 32, 0.92, 0, 0.33, {"pressure_curve": 0.3, "tip_ratio": 0.18, "tip_angle": -44}, "brushes/classic/calligraphy.myb"],
		["Classic charcoal", "Dry textures", "chalk", 12, 0.67, 0, 0.19, {"pressure_curve": 0.15, "grain": 1.42}, "brushes/classic/charcoal.myb"],
		["Dry bristle", "Dry textures", "chalk", 24, 0.77, 0, 0.19, {"pressure_curve": 0.15, "grain": 0.98}, "brushes/classic/dry_brush.myb"],
		["Ink blots", "Effects", "chalk", 70, 0.59, 0, 0.09, {"pressure_curve": 0.15, "grain": 0.75}, "brushes/classic/ink_blot.myb"],
		["Fat felt marker", "Markers & lettering", "marker", 34, 0.92, 0, 0.45, {"pressure_curve": 0.15, "tip_ratio": 0.14, "tip_angle": 23}, "brushes/classic/marker_fat.myb"],
		["Small felt marker", "Markers & lettering", "marker", 8, 0.92, 0, 0.45, {"pressure_curve": 0.15, "tip_ratio": 0.14, "tip_angle": 23}, "brushes/classic/marker_small.myb"],
		["Classic modeling brush", "Painting", "paint", 7, 0.59, 0.2, 0.17, {"pressure_curve": 0.15}, "brushes/classic/modelling.myb"],
		["Classic pen", "Inking", "ink", 11, 1, 0, 0.25, {"pressure_curve": 0.3}, "brushes/classic/pen.myb"],
		["Pointed comic ink", "Inking", "ink", 37, 1, 0, 0.22, {"pressure_curve": 3.1}, "brushes/classic/pointy_ink.myb"],
		["Pointillist dots", "Effects", "chalk", 22, 0.65, 0, 0.09, {"pressure_curve": 0.6, "grain": 0.82}, "brushes/classic/puantilism.myb"],
		["Steady ink", "Inking", "ink", 16, 1, 0, 0.65, {"pressure_curve": 0.3}, "brushes/classic/slow_ink.myb"],
		["Textured ink", "Dry textures", "chalk", 14, 0.85, 0, 0.19, {"pressure_curve": 0.15, "grain": 0.98}, "brushes/classic/textured_ink.myb"],
		["Wet palette knife", "Painting", "paint", 31, 0.98, 0.74, 0.17, {"pressure_curve": 0.15, "tip_ratio": 0.15, "tip_angle": 0}, "brushes/classic/wet_knife.myb"],
		["Deevad 2B pencil", "Sketching", "pencil", 12, 0.28, 0, 0.12, {"pressure_curve": 0.6, "grain": 0.97}, "brushes/deevad/2B_pencil.myb"],
		["Deevad 4H pencil", "Sketching", "pencil", 12, 0.14, 0, 0.07, {"pressure_curve": 0.6, "grain": 0.97}, "brushes/deevad/4H_pencil.myb"],
		["Deevad airbrush", "Glazes & shading", "soft", 150, 0.37, 0.05, 0.2, {"pressure_curve": 0.15}, "brushes/deevad/airbrush.myb"],
		["Deevad ballpoint", "Inking", "ink", 7, 0.71, 0, 0.22, {"pressure_curve": 0.15}, "brushes/deevad/ballpen.myb"],
		["Wet digital round", "Blending", "mix", 80, 0.63, 0.99, 0.19, {"pressure_curve": 0.15}, "brushes/deevad/basic_digital_brush_smudging.myb"],
		["Hard digital round", "Painting", "paint", 52, 0.95, 0.05, 0.17, {"pressure_curve": 0.15}, "brushes/deevad/basic_digital_brush.myb"],
		["Digital palette knife", "Markers & lettering", "marker", 47, 0.72, 0, 0.3, {"pressure_curve": 0.15, "tip_ratio": 0.28, "tip_angle": 70}, "brushes/deevad/basic_digital_knife.myb"],
		["Deevad blender", "Blending", "mix", 84, 0.6, 0.99, 0.19, {"pressure_curve": 0.15}, "brushes/deevad/blending.myb"],
		["Deevad chalk", "Dry textures", "chalk", 10, 0.58, 0, 0.19, {"pressure_curve": 0.15, "grain": 0.89}, "brushes/deevad/chalk.myb"],
		["Short color pull", "Blending", "mix", 22, 0.87, 0.99, 0.29, {"pressure_curve": 0.15}, "brushes/deevad/grainy_blending.myb"],
		["Fine rigger", "Inking", "ink", 4, 0.73, 0, 0.22, {"pressure_curve": 0.5}, "brushes/deevad/rigger_brush_thin.myb"],
		["Deevad rough", "Dry textures", "chalk", 30, 0.36, 0, 0.14, {"pressure_curve": 0.5, "grain": 1.13}, "brushes/deevad/rough.myb"],
		["Soft dip pen", "Inking", "ink", 13, 1, 0, 0.22, {"pressure_curve": 1.3}, "brushes/deevad/soft-dip-pen.myb"],
		["Pigment spray", "Effects", "chalk", 72, 0.59, 0, 0.13, {"pressure_curve": 0.15, "grain": 0.33}, "brushes/deevad/spray.myb"],
		["Fine watercolor", "Watercolor", "paint", 23, 0.46, 0.8, 0.17, {"pressure_curve": 0.15}, "brushes/deevad/thin_watercolor.myb"],
		["Expressive watercolor", "Watercolor", "paint", 90, 0.46, 0.33, 0.17, {"pressure_curve": 3.1}, "brushes/deevad/watercolor_expressive.myb"],
		["Watercolor glaze", "Watercolor", "soft", 100, 0.25, 0.8, 0.2, {"pressure_curve": 1}, "brushes/deevad/watercolor_glazing.myb"],
		["Dieterle 8B graphite", "Sketching", "pencil", 21, 0.72, 0, 0.07, {"pressure_curve": 0.15, "grain": 1.01}, "brushes/Dieterle/8B_Pencil#1.myb"],
		["Offset fountain nib", "Markers & lettering", "marker", 7, 0.74, 0, 0.3, {"pressure_curve": 0.15, "tip_ratio": 0.86, "tip_angle": 0}, "brushes/Dieterle/Fount-offset#1.myb"],
		["Wet flat bristle", "Watercolor", "paint", 19, 0.29, 0.86, 0.17, {"pressure_curve": 0.15, "tip_ratio": 0.48, "tip_angle": -30}, "brushes/Dieterle/WateryFlatbrush.myb"],
		["Beam light", "Glazes & shading", "soft", 17, 0.48, 0.05, 0.33, {"pressure_curve": 0.15}, "brushes/ramon/Beamlight.myb"],
		["Dirty grain", "Dry textures", "chalk", 10, 0.85, 0, 0.09, {"pressure_curve": 0.15, "grain": 0.55}, "brushes/ramon/Dirty_Noise.myb"],
		["Glow airbrush", "Glazes & shading", "soft", 150, 0.27, 0.05, 0.33, {"pressure_curve": 0.15}, "brushes/ramon/Glow_Airbrush.myb"],
		["Ramon pastel", "Dry textures", "chalk", 31, 0.85, 0, 0.09, {"pressure_curve": 0.15, "grain": 0.76}, "brushes/ramon/Pastel_1.myb"],
		["Ramon sketcher", "Sketching", "pencil", 7, 0.78, 0, 0.07, {"pressure_curve": 0.15, "grain": 0.73}, "brushes/ramon/Sketch_1.myb"],
		["Ramon color smear", "Blending", "mix", 112, 0.8, 0.99, 0.19, {"pressure_curve": 0.15}, "brushes/ramon/Smear.myb"],
		["Ramon fine pen", "Inking", "ink", 8, 0.98, 0, 0.22, {"pressure_curve": 0.15}, "brushes/ramon/Thin_Pen.myb"],
		["Flat wet paint", "Painting", "paint", 33, 0.91, 0.4, 0.17, {"pressure_curve": 0.15, "tip_ratio": 0.27, "tip_angle": 0}, "brushes/ramon/Wet_Direction.myb"],
		["Tanda acrylic round", "Painting", "paint", 34, 0.99, 0.13, 0.17, {"pressure_curve": 2}, "brushes/tanda/acrylic-03-paint.myb"],
		["Wet acrylic", "Painting", "paint", 39, 0.99, 0.67, 0.17, {"pressure_curve": 2.9}, "brushes/tanda/acrylic-04-with-water.myb"],
		["Tanda vine charcoal", "Dry textures", "chalk", 18, 0.83, 0, 0.09, {"pressure_curve": 0.3, "grain": 0.94}, "brushes/tanda/charcoal-03.myb"],
		["Tanda compressed charcoal", "Dry textures", "chalk", 17, 0.77, 0, 0.09, {"pressure_curve": 0.15, "grain": 1.58}, "brushes/tanda/charcoal-04.myb"],
		["Tanda flat marker", "Markers & lettering", "marker", 19, 0.38, 0, 0.3, {"pressure_curve": 0.4, "tip_ratio": 0.43, "tip_angle": -25}, "brushes/tanda/marker-05.myb"],
		["Tanda oil round", "Painting", "paint", 31, 0.99, 0.48, 0.17, {"pressure_curve": 0.7}, "brushes/tanda/oil-03-paint.myb"],
		["Oil mop", "Blending", "mix", 53, 0.4, 0.99, 0.19, {"pressure_curve": 0.7}, "brushes/tanda/oil-mop.myb"],
		["Tanda 2B pencil", "Sketching", "pencil", 7, 0.28, 0, 0.07, {"pressure_curve": 0.6, "grain": 0.97}, "brushes/tanda/pencil-2b.myb"],
		["Fine paint spatter", "Effects", "chalk", 51, 0.59, 0, 0.14, {"pressure_curve": 0.15, "grain": 0.23}, "brushes/tanda/splatter-02.myb"],
		["Scumbled paper", "Dry textures", "chalk", 120, 0.78, 0, 0.09, {"pressure_curve": 0.15, "grain": 1.35}, "brushes/tanda/texture-06.myb"],
		["Tanda watercolor round", "Watercolor", "paint", 43, 0.46, 0.84, 0.17, {"pressure_curve": 3.1}, "brushes/tanda/watercolor-02-paint.myb"],
	],
	"SenlinOS": [
		["Senlin drafting pencil", "Sketching", "pencil", 11, 0.62, 0, 0.07, {"pressure_curve": 0.15, "grain": 1.02}, "SLOS_MPB/001_Pencil.myb"],
		["Frame line", "Inking", "ink", 5, 1, 0, 0.72, {"pressure_curve": 0.15}, "SLOS_MPB/002_Frame-Line.myb"],
		["Senlin dip pen", "Inking", "ink", 2, 1, 0, 0.22, {"pressure_curve": 1.1}, "SLOS_MPB/003_Dip-Pen.myb"],
		["Senlin calligraphy", "Markers & lettering", "marker", 58, 0.92, 0, 0.3, {"pressure_curve": 0.15, "tip_ratio": 0.15, "tip_angle": -90}, "SLOS_MPB/005_Calligraphy.myb"],
		["Senlin felt pen", "Markers & lettering", "marker", 38, 0.47, 0, 0.3, {"pressure_curve": 0.15, "tip_ratio": 0.86, "tip_angle": 0}, "SLOS_MPB/011_Marker.myb"],
		["Senlin flat marker", "Markers & lettering", "marker", 52, 0.85, 0, 0.3, {"pressure_curve": 0.15, "tip_ratio": 0.15, "tip_angle": 0}, "SLOS_MPB/012_Flat-Marker.myb"],
		["Wax crayon", "Dry textures", "chalk", 23, 0.53, 0, 0.19, {"pressure_curve": 0.15, "grain": 0.89}, "SLOS_MPB/014_Crayon.myb"],
		["Senlin flat brush", "Markers & lettering", "marker", 59, 0.92, 0, 0.3, {"pressure_curve": 0.15, "tip_ratio": 0.28, "tip_angle": 70}, "SLOS_MPB/016_Flat-Brush.myb"],
		["Senlin detail paint", "Painting", "paint", 9, 0.29, 0.05, 0.17, {"pressure_curve": 0.5}, "SLOS_MPB/017_Thin-Brush.myb"],
		["Senlin classic paint", "Painting", "paint", 91, 0.97, 0.74, 0.17, {"pressure_curve": 1.8}, "SLOS_MPB/019_Classic-Paint.myb"],
		["Wet brush blender", "Blending", "mix", 83, 0.76, 0.99, 0.19, {"pressure_curve": 0.7}, "SLOS_MPB/020_Wet-Brush.myb"],
		["Wet scrub blender", "Blending", "mix", 47, 0.8, 0.92, 0.19, {"pressure_curve": 0.15, "tip_ratio": 0.27, "tip_angle": -15}, "SLOS_MPB/021_Wet-ScrubbingBrush.myb"],
		["Senlin watercolor", "Watercolor", "paint", 78, 0.46, 0.8, 0.17, {"pressure_curve": 1}, "SLOS_MPB/022_Watercolor.myb"],
		["Wet watercolor bloom", "Watercolor", "soft", 135, 0.25, 0.33, 0.2, {"pressure_curve": 3.1}, "SLOS_MPB/023_Wet-Watercolor.myb"],
		["Paint splash", "Effects", "chalk", 82, 0.65, 0, 0.09, {"pressure_curve": 0.15, "grain": 0.25}, "SLOS_MPB/024_Splash.myb"],
		["Sand grain", "Dry textures", "chalk", 53, 0.48, 0, 0.09, {"pressure_curve": 0.15, "grain": 0.31}, "SLOS_MPB/025_Sand.myb"],
		["Senlin blend", "Blending", "mix", 118, 0.87, 0.99, 0.19, {"pressure_curve": 0.15}, "SLOS_MPB/028_Blend.myb"],
		["Senlin smear", "Blending", "mix", 34, 0.87, 0.99, 0.19, {"pressure_curve": 3.1}, "SLOS_MPB/029_Smear.myb"],
		["Cloud glaze", "Glazes & shading", "soft", 94, 0.34, 0.05, 0.2, {"pressure_curve": 0.15}, "SLOS_MPB/032_Clouds.myb"],
	],
}

static func presets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for collection in COLLECTIONS:
		for spec in COLLECTIONS[collection]:
			var brush := {"format": "havu-brush", "version": 1, "name": spec[0],
				"category": spec[1], "brush": spec[2], "size": spec[3], "opacity": spec[4],
				"blend": spec[5], "smoothing": spec[6], "collection": collection, "source_path": spec[8]}
			brush.merge(spec[7])
			result.append(brush)
	return result
