Texture2D<float> _Input;
RWTexture2D<float> _Output;
SamplerState _pointClampSampler;
float2 _gRcpBufferDim;

[numthreads(8, 8, 1)]
void Blit(uint3 id : SV_DispatchThreadID)
{
    float2 UV = (id.xy) * _gRcpBufferDim;
    _Output[id.xy] = _Input.SampleLevel(_pointClampSampler, UV,0);;
}

[numthreads(8, 8, 1)]
void Gather(uint3 id : SV_DispatchThreadID)
{
    float2 UV = (id.xy+1.0f) * _gRcpBufferDim;
    float4 temp = _Input.Gather(_pointClampSampler, UV);
    float maxZ = min(min(temp.x, temp.y), min(temp.z, temp.w));
    _Output[id.xy] = maxZ;
}