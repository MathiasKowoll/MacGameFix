// Mortal Kombat 11's face morph cs_9f038ca4c3a6eb7a, rewritten: each vertex an
// expression moves gets PositionDeltas[i] * Weight, scaled by the alpha of its
// vertex colour, added to its position. The game reads the delta as one element
// of an R32G32B32_FLOAT buffer view, which D3DMetal serves as two floats an
// element; mk11-face-fix.c creates every such view as an R32_FLOAT view three
// times as long, and this reads the three floats of a delta one by one.
// Built into mk11-morph-shaders.h with tools/hlslc.c (cs_6_0).
cbuffer Globals : register(b0)
{
    uint bUseBlurSkinning;
    uint bDistanceFogEnabled;
    uint MaxIndex;
    float Weight;
};
Buffer<float4> VertexColorBuffer : register(t0);
Buffer<float> PositionDeltas : register(t1);
Buffer<uint> SourceIndices : register(t2);
RWStructuredBuffer<float3> OutputPositions : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint i = min(tid.x, MaxIndex);
    uint v = SourceIndices[i];
    float3 d = float3(PositionDeltas[3 * i], PositionDeltas[3 * i + 1], PositionDeltas[3 * i + 2]);
    float w = VertexColorBuffer[v].w * Weight;
    OutputPositions[v] = mad(d, w, OutputPositions[v]);
}
