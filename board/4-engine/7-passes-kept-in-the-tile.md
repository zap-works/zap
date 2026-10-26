---
needs: [engine-4, engine-5]
size: XL
---
# Passes kept in the tile

(needs 4 and 5 to measure). Each pass, resolve and compute stage
declares what it uses (rhi/core/barriers.zap), and both backends derive their barriers and
layouts from it. On a tile-based GPU (every Android one) what leaves the tile costs the whole
screen of bandwidth, so the same declarations make subpasses: a pass that reads only its own
pixel of the one before (skyrim's scene, then its grading) stays in the tile
(VK_KHR_dynamic_rendering_local_read); depth and the MSAA target are transient when no later use
reads them (TRANSIENT_ATTACHMENT in LAZILY_ALLOCATED memory where the device has it, depth stored
DONT_CARE, the samples resolved by the pass's resolve attachment rather than vkCmdResolveImage,
which desktops gain too); bloom at a quarter of the screen and the eye's adaptation a compute
reduce (these two change the pictures: their shots kept with `--update` once looked at). No GPU
here is tiled or has lazily allocated memory: measured by `ZAP_RUN=gputime` on Android.
