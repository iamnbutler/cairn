/// Metal shaders, compiled at run time from source when the renderer starts (a few tens of
/// milliseconds once), so the package needs no Metal build step or resource bundle.
///
/// Everything here works in device pixels, y down, origin top-left. The instance structs must
/// match `RectInstance` and `GlyphInstance` in Renderer.swift; their strides are checked at init.
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct RectI {
    float4 rect;    // x, y, w, h in device pixels
    float4 fill;    // premultiplied
    float4 border;  // premultiplied
    float2 shape;   // corner radius, border width (device pixels)
    float2 pad;
};

struct RectOut {
    float4 pos [[position]];
    float2 p;       // position relative to the rect's centre
    float2 half_size [[flat]];
    float4 fill [[flat]];
    float4 border [[flat]];
    float2 shape [[flat]];
};

vertex RectOut rect_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           const device RectI *rects [[buffer(0)]],
                           constant float2 &viewport [[buffer(1)]]) {
    RectI r = rects[iid];
    float2 corner = float2(vid & 1, vid >> 1);
    // One pixel of margin so antialiased edges at fractional positions are covered.
    float2 lo = r.rect.xy - 1.0, hi = r.rect.xy + r.rect.zw + 1.0;
    float2 px = mix(lo, hi, corner);
    RectOut o;
    o.pos = float4(px.x / viewport.x * 2.0 - 1.0, 1.0 - px.y / viewport.y * 2.0, 0.0, 1.0);
    o.p = px - (r.rect.xy + r.rect.zw * 0.5);
    o.half_size = r.rect.zw * 0.5;
    o.fill = r.fill;
    o.border = r.border;
    o.shape = r.shape;
    return o;
}

// Signed distance to a rounded box centred at the origin; negative inside.
static float sd_round_box(float2 p, float2 half_size, float radius) {
    float2 d = abs(p) - (half_size - radius);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

// Coverage of a pixel by a shape whose edge is `d` pixels from the pixel centre: exact for
// straight axis-aligned edges (a box filter), approximate at corners.
static float coverage(float d) { return saturate(0.5 - d); }

fragment float4 rect_fragment(RectOut in [[stage_in]]) {
    float radius = in.shape.x, bw = in.shape.y;
    float outer = coverage(sd_round_box(in.p, in.half_size, radius));
    float4 c = in.fill * outer;
    if (bw > 0.0) {
        float2 inner_half = in.half_size - bw;
        float inner = 0.0;
        if (inner_half.x > 0.0 && inner_half.y > 0.0) {
            inner = coverage(sd_round_box(in.p, inner_half, max(radius - bw, 0.0)));
        }
        float ring = outer * (1.0 - inner);
        c = in.border * ring + c * (1.0 - in.border.a * ring);
    }
    return c;
}

struct GlyphI {
    float4 rect;    // x, y, w, h in device pixels (whole pixels)
    float4 uv;      // texel rect in the atlas page: x0, y0, x1, y1
    float4 color;   // premultiplied text colour
    float4 misc;    // x: 1 for a colour glyph
};

struct GlyphOut {
    float4 pos [[position]];
    float2 uv;
    float4 color [[flat]];
    float is_color [[flat]];
};

vertex GlyphOut glyph_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                             const device GlyphI *glyphs [[buffer(0)]],
                             constant float2 &viewport [[buffer(1)]]) {
    GlyphI g = glyphs[iid];
    float2 corner = float2(vid & 1, vid >> 1);
    float2 px = g.rect.xy + corner * g.rect.zw;
    GlyphOut o;
    o.pos = float4(px.x / viewport.x * 2.0 - 1.0, 1.0 - px.y / viewport.y * 2.0, 0.0, 1.0);
    o.uv = mix(g.uv.xy, g.uv.zw, corner);
    o.color = g.color;
    o.is_color = g.misc.x;
    return o;
}

fragment float4 glyph_fragment(GlyphOut in [[stage_in]],
                               texture2d<float> mask [[texture(0)]],
                               texture2d<float> color [[texture(1)]]) {
    // Quads are pixel-aligned and 1:1 with the atlas, so nearest sampling is exact.
    constexpr sampler s(coord::pixel, filter::nearest, address::clamp_to_edge);
    if (in.is_color > 0.5) {
        return color.sample(s, in.uv) * in.color.a;
    }
    return in.color * mask.sample(s, in.uv).r;
}
"""
