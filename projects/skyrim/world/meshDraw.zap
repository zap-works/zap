# A batch of triangles on the GPU, as every distant or exterior layer of a scene keeps one: its
# vertices (of the vertex struct of the program that draws them) and triangles in one buffer each,
# and the textures it owns, which stay as long as it is drawn (the scene's list holds only handles).

import engine

pub type MeshDraw:
	model engine.Model
	indices engine.IndexBuffer
	textures engine.GpuTexture[] = []

# the vertices and triangles sent to the GPU
pub fn newMeshDraw<V Copy>(vertices V[], indices u32[]) MeshDraw:
	MeshDraw(model = engine.newModel(vertices), indices = engine.newIndexBuffer(indices))
