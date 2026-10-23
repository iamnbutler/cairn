import Metal
import QuartzCore
import simd

/// Must match `Quad` in the shader: two float4s and a float, 48-byte stride.
struct QuadInstance {
    var rect: SIMD4<Float>
    var color: SIMD4<Float>
    var radius: Float
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Quad { float4 rect; float4 color; float radius; };
struct VOut {
    float4 pos [[position]];
    float2 local;
    float2 size;
    float4 color;
    float radius;
};

vertex VOut quad_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                        constant Quad *quads [[buffer(0)]],
                        constant float2 &viewport [[buffer(1)]]) {
    float2 corner = float2(vid & 1, vid >> 1);
    Quad q = quads[iid];
    float2 p = q.rect.xy + corner * q.rect.zw;
    VOut o;
    o.pos = float4(p.x / viewport.x * 2 - 1, 1 - p.y / viewport.y * 2, 0, 1);
    o.local = corner * q.rect.zw;
    o.size = q.rect.zw;
    o.color = q.color;
    o.radius = q.radius;
    return o;
}

fragment float4 quad_fragment(VOut in [[stage_in]]) {
    float2 half_size = in.size * 0.5;
    float2 p = in.local - half_size;
    float2 d = abs(p) - (half_size - in.radius);
    float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - in.radius;
    float a = saturate(0.5 - dist) * in.color.a;
    return float4(in.color.rgb * a, a);
}
"""

/// Paints frames' quads with Metal. Runs on the render thread.
final class Renderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init() throws {
        precondition(MemoryLayout<QuadInstance>.stride == 48, "QuadInstance layout drifted from the shader")
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        let lib = try device.makeLibrary(source: shaderSource, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "quad_vertex")
        desc.fragmentFunction = lib.makeFunction(name: "quad_fragment")
        let att = desc.colorAttachments[0]!
        att.pixelFormat = .bgra8Unorm
        att.isBlendingEnabled = true
        att.sourceRGBBlendFactor = .one
        att.sourceAlphaBlendFactor = .one
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: desc)
    }

    func draw(_ frame: Frame, in layer: CAMetalLayer, viewport: SIMD2<Float>) {
        guard let drawable = layer.nextDrawable() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1)
        pass.colorAttachments[0].storeAction = .store

        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
        if !frame.quads.isEmpty {
            var instances = frame.quads.map { q in
                QuadInstance(
                    rect: SIMD4(Float(q.x), Float(q.y), Float(q.w), Float(q.h)),
                    color: SIMD4(Float(q.rgba >> 24 & 0xff), Float(q.rgba >> 16 & 0xff),
                                 Float(q.rgba >> 8 & 0xff), Float(q.rgba & 0xff)) / 255,
                    radius: Float(q.radius))
            }
            var vp = viewport
            let buf = device.makeBuffer(bytes: &instances, length: instances.count * 48)!
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBuffer(buf, offset: 0, index: 0)
            enc.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                               instanceCount: instances.count)
        }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
