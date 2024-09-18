#include <metal_stdlib>
using namespace metal;

struct Vertex
{
    float4 position [[position]];
};

struct Uniforms
{
    float2 position;
    float2 size;
    float cornerRadius;
    float time;
};

float roundedBoxSDF(float2 center, float2 size, float cornerRadius)
{
    return length(max(abs(center) - size + cornerRadius, 0.0)) - cornerRadius;
}

vertex Vertex vertex_main(const device Vertex *vertices [[buffer(0)]],
                          uint vid [[vertex_id]])
{
    return vertices[vid];
}

fragment float4 fragment_main(Vertex vertexOut [[stage_in]],
                              constant Uniforms &uniforms [[buffer(0)]],
                              texture2d<float> texture [[texture(0)]],
                              sampler sampler [[sampler(0)]])
{
    float2 position = vertexOut.position.xy;
    float2 center = uniforms.position;
    float2 size = uniforms.size;
    
    float4 cameraColor = texture.sample(sampler, position);
    
    float cornerRadius = uniforms.cornerRadius;
    
    float rectDistance = roundedBoxSDF(position - center - size * 0.5, size * 0.5, cornerRadius);
    float rectAlpha = 1.0 - smoothstep(0.0, 2.0, rectDistance);
    float4 rectColor = mix(float4(1.0, 1.0, 1.0, 1.0), float4(cameraColor.rgb, rectAlpha), rectAlpha);
    
    float shadowDistance = roundedBoxSDF(position - center - size * 0.5, size * 0.5, cornerRadius);
    float shadowAlpha = 1.0 - smoothstep(-30.0, 30.0, shadowDistance);
    float4 shadowColor = float4(0.4, 0.4, 0.4, shadowAlpha);
    
    return mix(rectColor, shadowColor, shadowAlpha - rectAlpha);
}
