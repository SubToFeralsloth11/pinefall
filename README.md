# Pinefall

Godot 4.7 rendering showcase: a misty pine forest pond built from CC0 [Poly Haven](https://polyhaven.com) scans
(`fir_tree_01` alone is 7.8 M triangles), lit with SDFGI, SSIL, SSAO, SSR, PCSS sun shadows, volumetric fog,
a ReflectionProbe, AgX tonemapping and a lens finishing pass.

## Run

```sh
./tools/fetch_assets.sh    # ~650 MB of models, HDRI and ground textures (not committed)
godot --path .
```

| Key | Action |
| --- | --- |
| F | Toggle cinematic shots / free-fly (WASD, Q/E, mouse, Shift, wheel) |
| 1 / 2 / 3 | Native + TAA / FSR2 75% / FSR2 50% |
| H | Hide HUD |
| P | Screenshot to `user://` |
| Esc | Quit |

`godot --path . -- --shots` renders every shot to `screenshots/` and prints the average fps.
