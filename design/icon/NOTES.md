# Readback icon studies

## Plan

- **Undertone** — Carve an off-centre hollow into a smooth porcelain seed. The hollow gives a quiet object a place for a voice to resonate.
- **Reed** — Turn one broad strip of champagne metal through a half twist. The same surface has a written side and a spoken side.
- **Cadence** — Form a circular graphite relief from a repeating rise and a short fall. Like a voice reading a phrase, its emphasis returns at regular intervals.
- **Dovetail** — Machine two offset square apertures into one continuous nickel link. A reply passes from one register to the next without breaking the connection.
- **Rest** — Sink a single thumb-sized depression into a charcoal tile, treating a pause as a physical place to settle.
- **Aftertone** — Curl the edge of a dark enamel disc upward, as though the last syllable were still moving through it.

Build the first four. Rest depends heavily on low-contrast shading. Aftertone and Cadence explore similar circular forms, and Cadence has the more distinctive silhouette. Judge each study at 1024, 32 and 16 px in three successive render passes. Keep intermediate renders under studies/.

## First proofs

The full-size plates and the native-size rows are in `studies/round-1/`.

- **Undertone** — The outside contour holds, but the pale hollow looks like a dimple at 32 and disappears at 16. Cut it through, open the mouth and keep the ivory lip.
- **Reed** — The two bright patches land on the same face. At 1024 the far end has an awkward triangular nub. At 16 it reads like a leaf. Turn the strip edge-on in the middle and present its two broad ends to the camera.
- **Cadence** — The six flutes make a beautiful highlight path at 1024. Their centre pinches to a point and all six blend into a grey disc at 16. Try four wider flutes, more relief on the silhouette and a real central opening.
- **Dovetail** — The two holes survive at 16. The face is too much like two square washers fused together and the slight off-axis rotation looks unintentional. Resolve one end into a circle so the casting itself changes from one register to another. Square the horizontal edges to the canvas.
- The right softbox makes a conspicuous grey patch on every housing. Reduce the housing's specular response.

## Second proofs

- **Undertone** — Opening the well worked. At 16 there is now a dark centre. At 1024 the thick end and round eye give it a map-pin silhouette. Broaden the foot, sweep the lip across the opening and lower one side.
- **Reed** — The two faces read as one turn at 32, but the waist nearly breaks at 16. The bronze looks polished in spots instead of evenly brushed. Give the edge more thickness, clear the housing at the twist, and soften the two square reflections.
- **Cadence** — Four lobes and a punched centre hold up much better. At 1024 the abrupt junction of the flutes and the circular hole looks unfinished. Shape the bore to echo the outside, roll both lips and widen the dark centre slightly.
- **Dovetail** — The square and round counters make the transition clearer. The stepped shoulder gives the top half an unintended letterform. Replace the step with a continuous waisted bridge and give the square end a small machined corner radius.

## Third proofs and selection

I compared the three sheets at native pixel sizes on both backgrounds and inspected the 1024 px renders for transitions in the metal and glaze. The final sheet uses the third render of each selected object.

### Cadence

Four repetitions of a long rise and a short fall give one pressed metal disc the rhythm of a spoken phrase. I borrowed superwhisper's use of a travelling highlight to describe a continuous surface. The last revision carries the four-fold symmetry through the bore and rounds the rim, so each highlight turns cleanly into the opening. At 16 px the hole and lobes remain visible. The direction of the fluting becomes subtle, and the mark can also read as a small impeller.

### Undertone

A pale celadon shell surrounds an off-centre hollow, suggesting a small resonating chamber. I took Raycast's product-shot treatment as the reference for the contact shadow and superwhisper's single-material restraint for the porcelain. The broader foot and lower lip removed the pointed map-pin outline of the second pass. Its weakness is the 16 px view, where the asymmetric ring survives but the glazed lip almost disappears.

### Reed

One brass strip turns over to carry a written reply onto its spoken side. Superwhisper provided the lighting lesson here. Both faces have the same finish, and their orientation determines which one catches the softbox. The thicker third-pass edge keeps the diagonal connected and the satin finish spreads the lower reflection. At 16 px the silhouette suggests a bow tie or hourglass. The separate menu bar drawing thickens the waist slightly.

### Dovetail, archived

One machined piece changes from a square opening to a round one. Cognition's closed geometry informed the two counters. The third pass removed the accidental letterform and both counters stay open at 16 px. The outline resembles a bottle opener, though, and that association is stronger than the idea of a reply changing form. Its three studies remain available for comparison.

## Rebuild and files

From the folder containing this note, run `python3 -B source/publish.py --rebuild`. It uses Blender Cycles, ImageMagick 7 and the macOS Helvetica font. This rebuilds the three selected objects, composites their contact and cast shadows, exports the black-alpha menu bar templates, and lays out the final sheet. Geometry, material and lighting controls are in `source/render.py`. The housing is a 4.65-exponent superellipse with a modelled shoulder. At 100 pixels per scene unit its 8.24-unit footprint is 824 pixels wide on the 1024-pixel canvas.

To regenerate an earlier study, run `blender -b --python source/render.py -- 1` followed by `python3 source/finish.py 1`, substituting 2 or 3 for the other rounds. The four finished study images and `proof.png` in each round folder are sufficient for comparison. Files ending in `-plate.png` hold the uncomposited render. Rebuilds use the local CPU renderer.

Each selected design has an 18 × 18 template and a 36 × 36 `@2x` companion for the same 18 pt menu bar slot. The Dock and Finder checks used downsampled PNGs on #ECECEC and #1E1E1E. The menu bar checks used black coverage on light and the same coverage tinted white on dark. These are rendered appearance checks. No installation in a running copy of Readback was performed.

## Pick

**Cadence.** At 16 px I can still pick out its four turns around a dark centre. At Dock size, each turn catches light on its way into the next one. That repetition feels close to the experience of listening to someone phrase a sentence, and it gives Readback a recognisable silhouette in the menu bar.

## Cadence in Reed’s brass

The selected icon is `final/cadence-brass.png` (pass 5). The four rises now taper as they approach a rounder opening, and the face curves gently down into its lip. The highlight on each rise travels partway around the disc. Cadence and Reed share the same brushed pale brass shader, brushing coordinates and three softboxes. The graphite housing and its shoulder use the original geometry, material and shadow treatment.

I checked five full-size renders and their 32 and 16 px reductions on both backgrounds. The straight recolour in pass 1 kept the pointed blades. Pass 2 rounded them but caught a second broad reflection near the bottom. Pass 3 tightened the lip. Pass 4 restored some definition to the folds and became the crisper alternative, `cadence-brass-a.png`. Pass 5 softened the folds where they meet the bore. At 64 and 32 px the metal still reads champagne alongside Reed. At 16 px the dark centre holds on both backgrounds, though much of the turning motion disappears. In monochrome the quieter outline can resemble a rounded washer.

The comparison sheet is `final/cadence-brass-contact.png`. Both options have matching 18 px and 36 px menu bar templates. To rebuild the brass icons, templates and sheet, run `python3 -B source/publish.py --cadence-brass --rebuild` from the project root. The five comparisons are in `studies/cadence-brass/`.
The final satin pass narrows the brush roughness range from 0.28–0.48 to 0.365–0.395, keeping its midpoint and the direction of the brushing.
Full-size fold and bore-lip crops show cleaner highlights. At 64, 32 and 16 px, the largest channel differences from the archived render are 2, 1 and 1 levels out of 255.
