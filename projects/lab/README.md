# The graphics lab

One window, a scene per key, each a test of the engine and the language: 1 Hello (the 2D batch,
text, lines), 2 Plasma (every pixel computed on the CPU, rows on every processor), 3 Sprites
(thousands bouncing), 4 Isometric (a 2.5D tile world, depth-sorted props, click to walk),
5 Materials (physically based spheres, the sky they mirror), 6 Shadows (a 4096 shadow map, a sun
that circles), 7 Relief (parallax occlusion mapping), 8 Lights (hundreds of point lights from a
storage block), 9 Crowd (up to 250 000 cubes in one draw), 0 Glow (HDR, bloom, a glossy floor).
The 3D scenes are drawn multisampled in HDR and tone mapped. Tab goes to the next scene, F1 hides
the panel, Esc ends.

    zap run projects/lab/main.zap
    zap run projects/lab/main.zap --scene 6 --frames 120 --step 16 --shot shadows.png
    zap run projects/lab/main.zap --tour 200          every scene for 200 frames without vsync, its speed printed
    zap run projects/lab/main.zap --tour 3 --step 16 --shot lab.png

`deep/` and `flat/` are the scenes, `physics/` the physics ones, `bench/` the measures,
`maketiles.zap` writes the isometric tiles into `assets/`.
