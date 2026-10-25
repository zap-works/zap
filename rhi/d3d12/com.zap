# Direct3D 12 and DXGI are COM: an object is the address of a pointer to its table of methods,
# and a method is called with the object first. Each method the backend calls is declared here
# as an `extern loaded fn` and given its address from an object's table (bindMethods* once for
# the objects there is one of, or one class of: the device, the queue, the command lists, the
# fence, the factory, the swapchain; bindExtern before the call for the others). The slots are
# the methods' places in their interfaces' tables, as d3d12.h and dxgi1_6.h declare them. A
# method that returns a struct (a descriptor handle, an allocation's size) writes it where its
# second argument points (MSVC's convention for methods). Reading the tables, QueryInterface,
# Release and GUIDs are std/win's.

import win

extern "d3d12.dll" fn D3D12CreateDevice(adapter i64, level i64, riid u8[], out device i64) i32
extern "d3d12.dll" fn D3D12SerializeRootSignature(
	desc RootSignatureDesc,
	version i64,
	out blob i64,
	out errors i64
) i32
extern "dxgi.dll" fn CreateDXGIFactory2(flags i64, riid u8[], out factory i64) i32

# ---------- IDXGIFactory6 ----------
extern loaded fn factoryEnumAdapterByGpuPreference(
	object i64,
	index i64,
	preference i64,
	riid u8[],
	out adapter i64
) i32
extern loaded fn factoryCreateSwapChainForHwnd(
	object i64,
	queue i64,
	hwnd i64,
	desc SwapChainDesc1,
	fullscreen i64,
	output i64,
	out swapchain i64
) i32
extern loaded fn factoryMakeWindowAssociation(object i64, hwnd i64, flags i64) i32
extern loaded fn factoryCheckFeatureSupport(object i64, feature i64, out value u32, size i64) i32
# ---------- IDXGIAdapter1 ----------
extern loaded fn adapterGetDesc1(object i64, mut desc AdapterDesc1) i32
# ---------- IDXGISwapChain3 ----------
extern loaded fn swapchainPresent(object i64, interval i64, flags i64) i32
extern loaded fn swapchainGetBuffer(object i64, index i64, riid u8[], out buffer i64) i32
extern loaded fn swapchainResizeBuffers(
	object i64,
	count i64,
	width i64,
	height i64,
	format i64,
	flags i64
) i32
extern loaded fn swapchainGetCurrentBackBufferIndex(object i64) u32
# ---------- ID3D12Device ----------
extern loaded fn deviceCreateCommandQueue(
	object i64,
	desc CommandQueueDesc,
	riid u8[],
	out queue i64
) i32
extern loaded fn deviceCreateCommandAllocator(
	object i64,
	kind i64,
	riid u8[],
	out allocator i64
) i32
extern loaded fn deviceCreateGraphicsPipelineState(
	object i64,
	desc GraphicsPipelineDesc,
	riid u8[],
	out pipeline i64
) i32
extern loaded fn deviceCreateComputePipelineState(
	object i64,
	desc ComputePipelineDesc,
	riid u8[],
	out pipeline i64
) i32
extern loaded fn deviceCreateCommandList(
	object i64,
	nodeMask i64,
	kind i64,
	allocator i64,
	pipeline i64,
	riid u8[],
	out list i64
) i32
extern loaded fn deviceCreateDescriptorHeap(
	object i64,
	desc DescriptorHeapDesc,
	riid u8[],
	out heap i64
) i32
extern loaded fn deviceGetDescriptorHandleIncrementSize(object i64, kind i64) u32
extern loaded fn deviceCreateRootSignature(
	object i64,
	nodeMask i64,
	blob i64,
	size i64,
	riid u8[],
	out signature i64
) i32
extern loaded fn deviceCreateShaderResourceView(
	object i64,
	resource i64,
	desc ShaderResourceViewDesc,
	handle i64
)
extern loaded fn deviceCreateUnorderedAccessView(
	object i64,
	resource i64,
	counter i64,
	desc UnorderedAccessViewDesc,
	handle i64
)
extern loaded fn deviceCreateRenderTargetView(object i64, resource i64, desc i64, handle i64)
extern loaded "deviceCreateRenderTargetView" fn deviceCreateRenderTargetViewOf(
	object i64,
	resource i64,
	desc RenderTargetViewDesc,
	handle i64
)
extern loaded fn deviceCreateDepthStencilView(
	object i64,
	resource i64,
	desc DepthStencilViewDesc,
	handle i64
)
extern loaded fn deviceCreateSampler(object i64, desc SamplerDescription, handle i64)
extern loaded fn deviceCopyDescriptorsSimple(
	object i64,
	count i64,
	destination i64,
	source i64,
	kind i64
)
extern loaded fn deviceGetResourceAllocationInfo(
	object i64,
	mut info AllocationInfo,
	visibleMask i64,
	count i64,
	desc ResourceDesc
) i64
extern loaded fn deviceCreateCommittedResource(
	object i64,
	heap HeapProperties,
	heapFlags i64,
	desc ResourceDesc,
	state i64,
	clear i64,
	riid u8[],
	out resource i64
) i32
extern loaded "deviceCreateCommittedResource" fn deviceCreateCommittedTarget(
	object i64,
	heap HeapProperties,
	heapFlags i64,
	desc ResourceDesc,
	state i64,
	clear ClearValue,
	riid u8[],
	out resource i64) i32
extern loaded fn deviceCreateHeap(object i64, desc HeapDesc, riid u8[], out heap i64) i32
extern loaded fn deviceCreatePlacedResource(
	object i64,
	heap i64,
	offset i64,
	desc ResourceDesc,
	state i64,
	clear i64,
	riid u8[],
	out resource i64
) i32
extern loaded fn deviceCreateFence(
	object i64,
	initial i64,
	flags i64,
	riid u8[],
	out fence i64
) i32
extern loaded fn deviceGetDeviceRemovedReason(object i64) i32
extern loaded fn deviceCreateQueryHeap(
	object i64,
	desc QueryHeapDesc,
	riid u8[],
	out heap i64
) i32
extern loaded fn deviceCreateCommandSignature(
	object i64,
	desc CommandSignatureDesc,
	rootSignature i64,
	riid u8[],
	out signature i64
) i32
# ---------- ID3D12Device1 ----------
extern loaded fn deviceCreatePipelineLibrary(
	object i64,
	blob u8[],
	size i64,
	riid u8[],
	out library i64
) i32
# ---------- ID3D12PipelineLibrary ----------
extern loaded fn libraryStorePipeline(object i64, name u8[], pipeline i64) i32
extern loaded fn libraryLoadGraphicsPipeline(
	object i64,
	name u8[],
	desc GraphicsPipelineDesc,
	riid u8[],
	out pipeline i64
) i32
extern loaded fn libraryGetSerializedSize(object i64) i64
extern loaded fn librarySerialize(object i64, data u8[], size i64) i32
# ---------- ID3D12CommandQueue ----------
extern loaded fn queueExecuteCommandLists(object i64, count i64, lists i64[])
extern loaded fn queueSignal(object i64, fence i64, value i64) i32
extern loaded fn queueGetTimestampFrequency(object i64, out frequency i64) i32
# ---------- ID3D12CommandAllocator ----------
extern loaded fn allocatorReset(object i64) i32
# ---------- ID3D12Fence ----------
extern loaded fn fenceGetCompletedValue(object i64) i64
extern loaded fn fenceSetEventOnCompletion(object i64, value i64, event i64) i32
# ---------- ID3D12Resource ----------
extern loaded fn resourceMap(object i64, subresource i64, range i64, out data i64) i32
extern loaded fn resourceGetGPUVirtualAddress(object i64) i64
# ---------- ID3D12DescriptorHeap ----------
extern loaded fn heapGetCpuStart(object i64, out handle i64) i64
extern loaded fn heapGetGpuStart(object i64, out handle i64) i64
# ---------- ID3DBlob ----------
extern loaded fn blobGetBufferPointer(object i64) i64
extern loaded fn blobGetBufferSize(object i64) i64
# ---------- ID3D12GraphicsCommandList ----------
extern loaded fn listClose(object i64) i32
extern loaded fn listReset(object i64, allocator i64, pipeline i64) i32
extern loaded fn listDrawInstanced(
	object i64,
	vertices i64,
	instances i64,
	firstVertex i64,
	firstInstance i64
)
extern loaded fn listDrawIndexedInstanced(
	object i64,
	indices i64,
	instances i64,
	firstIndex i64,
	baseVertex i64,
	firstInstance i64
)
extern loaded fn listDispatch(object i64, x i64, y i64, z i64)
extern loaded fn listCopyBufferRegion(
	object i64,
	destination i64,
	destinationOffset i64,
	source i64,
	sourceOffset i64,
	n i64
)
extern loaded fn listCopyTextureRegion(
	object i64,
	destination TextureCopyLocation,
	x i64,
	y i64,
	z i64,
	source TextureCopyLocation,
	box i64
)
extern loaded fn listResolveSubresource(
	object i64,
	destination i64,
	destinationSub i64,
	source i64,
	sourceSub i64,
	format i64
)
extern loaded fn listIASetPrimitiveTopology(object i64, topology i64)
extern loaded fn listRSSetViewports(object i64, count i64, viewport Viewport)
extern loaded fn listRSSetScissorRects(object i64, count i64, rect Rect)
extern loaded fn listSetPipelineState(object i64, pipeline i64)
extern loaded fn listResourceBarrier(object i64, count i64, barriers ResourceBarrier[])
extern loaded fn listSetDescriptorHeaps(object i64, count i64, heaps i64[])
extern loaded fn listSetGraphicsRootSignature(object i64, signature i64)
extern loaded fn listSetComputeRootSignature(object i64, signature i64)
extern loaded fn listSetComputeRootDescriptorTable(object i64, index i64, handle i64)
extern loaded fn listSetComputeRootConstantBufferView(object i64, index i64, address i64)
extern loaded fn listSetComputeRootShaderResourceView(object i64, index i64, address i64)
extern loaded fn listSetComputeRootUnorderedAccessView(object i64, index i64, address i64)
extern loaded fn listSetGraphicsRootDescriptorTable(object i64, index i64, handle i64)
extern loaded fn listSetGraphicsRootConstantBufferView(object i64, index i64, address i64)
extern loaded fn listSetGraphicsRootShaderResourceView(object i64, index i64, address i64)
extern loaded fn listIASetIndexBuffer(object i64, view IndexBufferView)
extern loaded fn listIASetVertexBuffers(
	object i64,
	first i64,
	count i64,
	views VertexBufferView[]
)
extern loaded fn listOMSetRenderTargets(
	object i64,
	count i64,
	colors i64[],
	single i64,
	depth i64[]
)
extern loaded "listOMSetRenderTargets" fn listOMSetColorTarget(
	object i64,
	count i64,
	colors i64[],
	single i64,
	depth i64
)
extern loaded fn listClearDepthStencilView(
	object i64,
	view i64,
	flags i64,
	depth f32,
	stencil i64,
	rectCount i64,
	rects i64
)
extern loaded fn listClearRenderTargetView(
	object i64,
	view i64,
	color f32[],
	rectCount i64,
	rects i64
)
extern loaded fn listEndQuery(object i64, heap i64, kind i64, index i64)
extern loaded fn listResolveQueryData(
	object i64,
	heap i64,
	kind i64,
	first i64,
	count i64,
	destination i64,
	offset i64
)
extern loaded fn listExecuteIndirect(
	object i64,
	signature i64,
	most i64,
	commands i64,
	offset i64,
	counts i64,
	countOffset i64
)

# the object as another of its interfaces; a failure stops the program
fn queryInterface(object i64, riid u8[], what str):
	result = win.queryInterface(object, riid)
	if result == 0:
		fail("rhi: QueryInterface({what}) failed")
	result

iidFactory6 = win.guid("c1b6694f-ff09-44a9-b03c-77900a0a1d17")
iidAdapter1 = win.guid("29038f61-3839-4626-91fd-086879011a05")
iidSwapchain3 = win.guid("94d99bdb-f1f8-4ab0-b236-7da0170edab1")
iidDevice = win.guid("189819f1-1db6-4b57-be54-1821339b85f7")
iidQueue = win.guid("0ec870a6-5d7e-4c22-8cfc-5baae07616ed")
iidAllocator = win.guid("6102dee4-af59-4b09-b999-b44d73f09b24")
iidCommandList = win.guid("5b160d0f-ac1b-4185-8ba8-b3ae42a5a455")
iidFence = win.guid("0a753dcf-c4d8-4b91-adf6-be5a60d95a76")
iidDescriptorHeap = win.guid("8efb471d-616c-4f49-90f7-127bb763fa51")
iidResource = win.guid("696442be-a72e-4059-bc79-5b5c98040fad")
iidHeap = win.guid("6b3b2502-6e51-45b3-90ee-9884265e8df3")
iidRootSignature = win.guid("c54a6b66-72df-4ee8-8be5-a946a1429214")
iidPipelineState = win.guid("765a30f3-f624-4c6f-a828-ace948622445")
iidDevice1 = win.guid("77acce80-638e-4e65-8895-c1f23386863e")
iidQueryHeap = win.guid("0d9658ae-ed45-469e-a61d-970ec583cab4")
iidCommandSignature = win.guid("c36a797c-ec80-4f0a-8985-a7b2475082d1")
iidPipelineLibrary = win.guid("c64226a8-9201-46af-b4cc-53fb9ff7414f")

# the result of a call that returns an HRESULT: a failure stops the program, its code shown
fn check(hr i32, what str):
	if hr < 0:
		removed = ""
		if (i64(hr) & 0xFFFF_FFFF) == 0x887A_0005 and deviceForReasons != 0:
			removed = ", the device removed: {win.hresultText(deviceGetDeviceRemovedReason(deviceForReasons))}"
		fail("rhi: {what} failed ({win.hresultText(hr)}{removed})")

# the device asked why it was removed when a call fails for that
mut deviceForReasons = 0

# the methods of the objects there is one of (or one class of), from their tables
fn bindFactory(factory i64):
	bindExtern(factoryMakeWindowAssociation, win.method(factory, 8))
	bindExtern(factoryCreateSwapChainForHwnd, win.method(factory, 15))
	bindExtern(factoryCheckFeatureSupport, win.method(factory, 28))
	bindExtern(factoryEnumAdapterByGpuPreference, win.method(factory, 29))

fn bindDevice(device i64):
	deviceForReasons = device
	bindExtern(deviceCreateCommandQueue, win.method(device, 8))
	bindExtern(deviceCreateCommandAllocator, win.method(device, 9))
	bindExtern(deviceCreateGraphicsPipelineState, win.method(device, 10))
	bindExtern(deviceCreateComputePipelineState, win.method(device, 11))
	bindExtern(deviceCreateCommandList, win.method(device, 12))
	bindExtern(deviceCreateDescriptorHeap, win.method(device, 14))
	bindExtern(deviceGetDescriptorHandleIncrementSize, win.method(device, 15))
	bindExtern(deviceCreateRootSignature, win.method(device, 16))
	bindExtern(deviceCreateShaderResourceView, win.method(device, 18))
	bindExtern(deviceCreateUnorderedAccessView, win.method(device, 19))
	bindExtern(deviceCreateRenderTargetView, win.method(device, 20))
	bindExtern(deviceCreateRenderTargetViewOf, win.method(device, 20))
	bindExtern(deviceCreateDepthStencilView, win.method(device, 21))
	bindExtern(deviceCreateSampler, win.method(device, 22))
	bindExtern(deviceCopyDescriptorsSimple, win.method(device, 24))
	bindExtern(deviceGetResourceAllocationInfo, win.method(device, 25))
	bindExtern(deviceCreateCommittedResource, win.method(device, 27))
	bindExtern(deviceCreateCommittedTarget, win.method(device, 27))
	bindExtern(deviceCreateHeap, win.method(device, 28))
	bindExtern(deviceCreatePlacedResource, win.method(device, 29))
	bindExtern(deviceCreateFence, win.method(device, 36))
	bindExtern(deviceGetDeviceRemovedReason, win.method(device, 37))
	bindExtern(deviceCreateQueryHeap, win.method(device, 39))
	bindExtern(deviceCreateCommandSignature, win.method(device, 41))

fn bindQueue(queue i64):
	bindExtern(queueExecuteCommandLists, win.method(queue, 10))
	bindExtern(queueSignal, win.method(queue, 14))
	bindExtern(queueGetTimestampFrequency, win.method(queue, 16))

fn bindFence(fence i64):
	bindExtern(fenceGetCompletedValue, win.method(fence, 8))
	bindExtern(fenceSetEventOnCompletion, win.method(fence, 9))

fn bindLibrary(library i64):
	bindExtern(libraryStorePipeline, win.method(library, 8))
	bindExtern(libraryLoadGraphicsPipeline, win.method(library, 9))
	bindExtern(libraryGetSerializedSize, win.method(library, 11))
	bindExtern(librarySerialize, win.method(library, 12))

fn bindAllocator(allocator i64):
	bindExtern(allocatorReset, win.method(allocator, 8))

fn bindSwapchain(swapchain i64):
	bindExtern(swapchainPresent, win.method(swapchain, 8))
	bindExtern(swapchainGetBuffer, win.method(swapchain, 9))
	bindExtern(swapchainResizeBuffers, win.method(swapchain, 13))
	bindExtern(swapchainGetCurrentBackBufferIndex, win.method(swapchain, 36))

fn bindCommandList(list i64):
	bindExtern(listClose, win.method(list, 9))
	bindExtern(listReset, win.method(list, 10))
	bindExtern(listDrawInstanced, win.method(list, 12))
	bindExtern(listDrawIndexedInstanced, win.method(list, 13))
	bindExtern(listDispatch, win.method(list, 14))
	bindExtern(listCopyBufferRegion, win.method(list, 15))
	bindExtern(listCopyTextureRegion, win.method(list, 16))
	bindExtern(listResolveSubresource, win.method(list, 19))
	bindExtern(listIASetPrimitiveTopology, win.method(list, 20))
	bindExtern(listRSSetViewports, win.method(list, 21))
	bindExtern(listRSSetScissorRects, win.method(list, 22))
	bindExtern(listSetPipelineState, win.method(list, 25))
	bindExtern(listResourceBarrier, win.method(list, 26))
	bindExtern(listSetDescriptorHeaps, win.method(list, 28))
	bindExtern(listSetComputeRootSignature, win.method(list, 29))
	bindExtern(listSetGraphicsRootSignature, win.method(list, 30))
	bindExtern(listSetComputeRootDescriptorTable, win.method(list, 31))
	bindExtern(listSetGraphicsRootDescriptorTable, win.method(list, 32))
	bindExtern(listSetComputeRootConstantBufferView, win.method(list, 37))
	bindExtern(listSetGraphicsRootConstantBufferView, win.method(list, 38))
	bindExtern(listSetComputeRootShaderResourceView, win.method(list, 39))
	bindExtern(listSetGraphicsRootShaderResourceView, win.method(list, 40))
	bindExtern(listSetComputeRootUnorderedAccessView, win.method(list, 41))
	bindExtern(listIASetIndexBuffer, win.method(list, 43))
	bindExtern(listIASetVertexBuffers, win.method(list, 44))
	bindExtern(listOMSetRenderTargets, win.method(list, 46))
	bindExtern(listOMSetColorTarget, win.method(list, 46))
	bindExtern(listClearDepthStencilView, win.method(list, 47))
	bindExtern(listClearRenderTargetView, win.method(list, 48))
	bindExtern(listEndQuery, win.method(list, 53))
	bindExtern(listResolveQueryData, win.method(list, 54))
	bindExtern(listExecuteIndirect, win.method(list, 59))

# the resource's address on the GPU
fn gpuAddress(resource i64):
	bindExtern(resourceGetGPUVirtualAddress, win.method(resource, 11))
	resourceGetGPUVirtualAddress(resource)

# the resource's memory mapped (an upload or readback heap's): the CPU's address
fn mapResource(resource i64):
	bindExtern(resourceMap, win.method(resource, 8))
	check(resourceMap(resource, 0, 0, out at), "ID3D12Resource::Map")
	at

fn heapCpuStart(heap i64):
	bindExtern(heapGetCpuStart, win.method(heap, 9))
	heapGetCpuStart(heap, out handle)
	handle

fn heapGpuStart(heap i64):
	bindExtern(heapGetGpuStart, win.method(heap, 10))
	heapGetGpuStart(heap, out handle)
	handle

# a blob's bytes: its address and size
fn blobBytes(blob i64):
	bindExtern(blobGetBufferPointer, win.method(blob, 3))
	bindExtern(blobGetBufferSize, win.method(blob, 4))
	(blobGetBufferPointer(blob), blobGetBufferSize(blob))
