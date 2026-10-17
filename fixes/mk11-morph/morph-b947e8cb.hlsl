// Mortal Kombat 11's face morph cs_b947e8cbb6ef2fd9, rewritten: the same as
// morph-9f038ca4.hlsl without the vertex-colour mask.
// Built into mk11-morph-shaders.h with tools/hlslc.c (cs_6_0).
cbuffer Globals : register(b0)
{
    uint bUseBlurSkinning;
    uint bDistanceFogEnabled;
    uint MaxIndex;
    float Weight;
};
Buffer<float> PositionDeltas : register(t0);
Buffer<uint> SourceIndices : register(t1);
RWStructuredBuffer<float3> OutputPositions : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint i = min(tid.x, MaxIndex);
    uint v = SourceIndices[i];
    float3 d = float3(PositionDeltas[3 * i], PositionDeltas[3 * i + 1], PositionDeltas[3 * i + 2]);
    OutputPositions[v] = mad(d, Weight, OutputPositions[v]);
}
