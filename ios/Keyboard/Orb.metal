/*
 * The keyboard orb's body, translated line for line from ask-ndtv's orb.frag.glsl. At rest it is a small
 * pulsing dot of the vivid pigment; conversation springs it open into a solid watercolour blob whose
 * interior is three noise-warped waterlines — low, mid and high band — over a near-white body,
 * composited with linear burn so pigments deepen where they pool. The fourth band (air) drives the fine
 * grain. Pattern phase advances with the integral of speech energy (cumulative), so the water travels
 * while a voice acts. State transitions are damped springs computed here from flip timestamps; the
 * driver (OrbView.swift) only flips flags.
 *
 * Differences from the GLSL, all deliberate:
 *  - GLSL mod() floors; Metal's fmod() truncates, so mod289 spells out the GLSL definition.
 *  - smoothstep with edge0 > edge1 is undefined in MSL, so glslSmoothstep spells out the formula.
 *  - vUv comes from the fragment position (y flipped so the water sits at the bottom).
 *  - Two extra uniforms: dotRadius (the resting dot is larger than the source's 0.17 so it reads in a
 *    30 pt keyboard) and scale (the whole-orb CSS breathing, applied here instead of as a transform).
 */

#include <metal_stdlib>
using namespace metal;

/// Must match `OrbView.Uniforms` field for field (all float4 / float2 / float, so no padding surprises).
struct OrbUniforms {
    float4 bands;
    float4 cumulative;
    float4 stateOn;
    float4 stateChangedAt;
    float4 colorBase;
    float4 colorLow;
    float4 colorMid;
    float4 colorHigh;
    float2 size;
    float time;
    float level;
    float alpha;
    float dotRadius;
    float scale;
    float unused;
};

struct OrbVarying {
    float4 position [[position]];
};

/// One triangle that covers the whole drawable; no vertex buffer.
vertex OrbVarying orbVertex(uint id [[vertex_id]]) {
    float2 corner = float2((id << 1) & 2, id & 2);
    OrbVarying out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

/* 3D simplex noise — the canonical Ashima Arts / Stefan Gustavson implementation (MIT, webgl-noise),
   reproduced as is customary. Sampled with time on the third axis, so the pattern evolves in place
   rather than scrolling past. */
static float4 mod289(float4 x) { return x - 289.0 * floor(x / 289.0); }
static float3 mod289(float3 x) { return x - 289.0 * floor(x / 289.0); }

static float4 permute(float4 x) {
    return mod289(((x * 34.0) + 1.0) * x);
}

static float4 taylorInvSqrt(float4 r) {
    return 1.79284291400159 - 0.85373472095314 * r;
}

static float snoise(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);
    float3 i = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);
    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;
    i = mod289(i);
    float4 p = permute(
        permute(
            permute(i.z + float4(0.0, i1.z, i2.z, 1.0)) +
                i.y + float4(0.0, i1.y, i2.y, 1.0)
        ) + i.x + float4(0.0, i1.x, i2.x, 1.0)
    );
    float n_ = 1.0 / 7.0;
    float3 ns = n_ * D.wyz - D.xzx;
    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);
    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);
    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);
    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);
    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;
    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

static float snoise01(float3 v) {
    return snoise(v) * 0.5 + 0.5;
}

/// FBM over 2D position with a separate evolution axis.
static float fbm(float2 p, float w) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i += 1) {
        value += amplitude * snoise01(float3(p, w));
        p = p * 2.03 + float2(17.3, 9.1);
        w = w * 1.7 + 3.1;
        amplitude *= 0.5;
    }
    return value;
}

/// GLSL's smoothstep formula, which the source relies on with reversed edges.
static float glslSmoothstep(float edge0, float edge1, float x) {
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// Damped-spring step response: rises to 1 with one soft overshoot.
static float springIn(float t) {
    t = max(t, 0.0);
    return 1.0 - exp(-5.5 * t) * cos(9.0 * t);
}

static float stateAmount(float on, float changedAt, float time) {
    float t = time - changedAt;
    return on > 0.5
        ? clamp(springIn(t), 0.0, 1.2)
        : 1.0 - clamp(t / 0.4, 0.0, 1.0);
}

// Linear burn: overlapping colour deepens instead of washing out.
static float3 burn(float3 base, float3 blend) {
    return max(base + blend - 1.0, 0.0);
}

static float3 burnMix(float3 base, float3 blend, float amount) {
    return mix(base, burn(base, blend), amount);
}

// A soft horizontal waterline inside the body, pushed around by noise. 1 above the line, 0 below.
// The band lifts the line and energises its wobble.
static float waveLayer(float2 uv, float height, float frequency, float speed, float drift, float band,
                       float softness, float time) {
    float wobble =
        (snoise01(float3(uv * float2(frequency, frequency * 0.7), time * speed + drift)) - 0.5) *
        (0.55 + band * 0.9);
    float line = uv.y - height - band * 0.22;
    return glslSmoothstep(-softness - band * 0.06, softness + band * 0.1, line + wobble * 0.45);
}

constexpr sampler grainSampler(address::repeat, filter::linear);

// One tap of the prebaked grain: two decorrelated channels, crossfaded on a slow beat carried by the
// air band's history.
static float grainTap(float2 uv, float2 offset, texture2d<float> noise, constant OrbUniforms &u) {
    float2 tuv = uv * 0.9 + offset;
    float a = noise.sample(grainSampler, tuv).r;
    float b = noise.sample(grainSampler, float2(tuv.x, 1.0 - tuv.y)).g;
    float beat = sin(u.time * 0.8 + u.cumulative.w * 2.0) * 0.5 + 0.5;
    return mix(a, b, beat) - 0.5;
}

fragment float4 orbFragment(OrbVarying in [[stage_in]],
                            constant OrbUniforms &u [[buffer(0)]],
                            texture2d<float> noise [[texture(0)]]) {
    float time = u.time;
    float2 vUv = float2(in.position.x / u.size.x, 1.0 - in.position.y / u.size.y);
    float2 p = (vUv - 0.5) * 2.0 / u.scale;
    // The body bobs gently, like something floating.
    p.y += 0.02 * sin(time * 1.4);
    float r = length(p);

    float listen = stateAmount(u.stateOn.x, u.stateChangedAt.x, time);
    float think = stateAmount(u.stateOn.y, u.stateChangedAt.y, time);
    float speak = stateAmount(u.stateOn.z, u.stateChangedAt.z, time);
    float capture = stateAmount(u.stateOn.w, u.stateChangedAt.w, time);
    // 0 is the resting dot, 1 is the full watercolour body. Springs carry the morph.
    float convo = clamp(max(max(listen, speak), max(think, capture)), 0.0, 1.0);

    // ── Geometry: dot at rest, blob in conversation ──
    float dotRadius = u.dotRadius + 0.015 * sin(time * 2.1);

    float blobRadius = 0.66;
    blobRadius += 0.03 * listen + 0.06 * speak - 0.05 * capture;
    blobRadius += u.level * 0.05;
    blobRadius += 0.008 * sin(time * 0.5);

    float radius = mix(dotRadius, blobRadius, convo);

    float edge = glslSmoothstep(0.02, -0.015, r - radius);
    if (edge <= 0.0) {
        return float4(0.0);
    }

    // ── Interior ── circle space, y up, 0…1 across the body.
    float2 uv = p / (2.0 * radius) + 0.5;

    float4 phases = float4(
        u.cumulative.x * 0.25,
        -u.cumulative.y * 0.55,
        u.cumulative.z * 1.1,
        u.cumulative.w * 0.35
    );

    // Fine prebaked grain first — the tooth the procedural warps bite into.
    float grain0 = grainTap(uv, float2(phases.w * 0.05, 0.37), noise, u);
    float grain1 = grainTap(uv, float2(0.61 + phases.x * 0.04, 0.83), noise, u);
    uv += grain0 * (0.05 + u.bands.w * 0.06);

    // Warp on warp: a broad simplex domain warp, then the fbm-of-fbm cascade.
    float2 broad = float2(
        fbm(uv * 1.15 + float2(0.0, 7.31), time * 0.14 + phases.x * 0.3),
        fbm(uv * 1.15 + float2(5.17, 2.73), time * 0.12 + phases.z * 0.15)
    ) - 0.5;
    uv += broad * 0.4;

    float2 q = float2(
        fbm(uv * 0.9, time * 0.16 + phases.x * 0.4),
        fbm(uv * 0.9 + float2(3.1, 1.7), time * 0.13 + phases.y * 0.3)
    );
    float cascade = fbm(uv * 1.4 + q * 1.1, time * 0.1 + phases.y * 0.35);
    uv += (cascade - 0.5) * 0.5 + grain1 * 0.03;

    // Three waterlines, low sitting deepest. Thinking steepens the tempo.
    float tempo = 1.0 + think * 0.6;
    float low = waveLayer(uv, 0.28, 2.2, 0.22 * tempo, phases.x, u.bands.x, 0.16, time);
    float mid = waveLayer(uv, 0.45, 3.6, 0.3 * tempo, phases.y, u.bands.y, 0.13, time);
    float high = waveLayer(uv, 0.66, 5.4, 0.4 * tempo, phases.z, u.bands.z, 0.1, time);

    // Each band's pigment pools below its line; burn makes the pools deepen where they overlap.
    float3 water = u.colorBase.rgb;
    water = burnMix(water, u.colorLow.rgb, (1.0 - low) * 0.72);
    water = burnMix(water, u.colorMid.rgb, (1.0 - mid) * 0.5);
    water = burnMix(water, u.colorHigh.rgb, (1.0 - high) * 0.45);

    // The cascade doubles as lighting.
    water *= 0.92 + 0.2 * (cascade - 0.5) + 0.06 * u.level + grain1 * u.bands.w * 0.06;

    // The resting dot is the vivid pigment itself, breathing in opacity.
    float3 dotColour = u.colorLow.rgb * (0.9 + 0.1 * sin(time * 2.1));
    float dotPulse = 0.7 + 0.3 * sin(time * 4.487);

    float3 colour = mix(dotColour, water, convo);
    float alpha = edge * mix(dotPulse, 1.0, convo) * u.alpha;
    // Premultiplied, so the soft edge composites with no dark fringe.
    return float4(colour * alpha, alpha);
}
