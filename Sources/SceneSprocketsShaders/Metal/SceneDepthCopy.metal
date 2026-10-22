#include <metal_stdlib>

using namespace metal;

namespace SceneDepthCopy {

    // Copies the scene's depth attachment into a color texture that particle shaders can read (soft particles).
    [[kernel]] void copy_depth(
        uint2 tid [[thread_position_in_grid]],
        depth2d<float, access::read> sceneDepth [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]]
    ) {
        if (tid.x >= output.get_width() || tid.y >= output.get_height()) {
            return;
        }
        output.write(float4(sceneDepth.read(tid), 0, 0, 0), tid);
    }
}
