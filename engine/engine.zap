# The engine: the window and the frame clock, drawing on the GPU through the RHI (render/), its
# scenes and models (scene/), post-processing (post/), text and noise; sound, glTF and OBJ are
# modules of their own (engine.audio, engine.gltf, engine.obj), as is a guest's memory map
# (engine.memoryMap).
parts render, scene, post, terrain
