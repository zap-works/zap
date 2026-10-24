# An Android app's surface (rhi/vulkan's, in an app): the app's ANativeWindow, the window handle
# the engine hands the device (engine/linux/app/window.zap).

extern type AndroidSurfaceCreateInfo:
	sType u32 = 1_000_008_000
	next i64 = 0
	flags u32 = 0
	window i64

extern "vulkan-1.dll" fn vkCreateAndroidSurfaceKHR(
	instance i64,
	info AndroidSurfaceCreateInfo,
	allocator i64,
	out surface i64
) i32

fn surfaceExtension() str:
	"VK_KHR_android_surface"

fn newSurface(instance i64, hwnd i64, hinstance i64):
	_ = hinstance
	info = AndroidSurfaceCreateInfo(window = hwnd)
	check(vkCreateAndroidSurfaceKHR(instance, info, 0, out surface), "vkCreateAndroidSurfaceKHR")
	surface
