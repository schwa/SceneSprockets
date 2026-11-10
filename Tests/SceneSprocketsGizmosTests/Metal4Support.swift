import Metal

// CI runners have a paravirtual GPU without Metal 4.
let deviceSupportsMetal4 = MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) ?? false
