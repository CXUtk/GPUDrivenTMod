#include "DustDef.hlsl"
#include "RNG.hlsl"

cbuffer cbSettings
{
	float4x4 	_ModelTransform;
	float4x4	_VPTransform;
	uint 		_MaximumDusts;
	float2 		_Center;
	float 		_Multiplier;
	float   	_DeltaTime;
	float 		_Frames;
	float		_Scale;
};

cbuffer tileCollision
{
	float2 _TileSize;
	float2 _TileStartOffset;
};

RWStructuredBuffer<Dust2D>	_dusts : register(u0);
RWStructuredBuffer<uint>	_dustsDeadList : register(u1);
StructuredBuffer<Dust2D>	_dustsReadonly : register(t0);
Texture2D<float4>			_TileSDF;

static float2 defaultVertexPos[4] =
{
	float2(-0.5, 0.5),
	float2(-0.5, -0.5),
	float2(0.5, 0.5),
	float2(0.5, -0.5)
};

static float scales[5] =
{
	0.8,
	0.65,
	0.5,
	0.35,
	0.1
};

void GenerateNewDust(float2 pos, float2 vel, float2 scale)
{
	uint prev;
	InterlockedAdd(_dustsDeadList[0], 1, prev);

	if(prev == _MaximumDusts)
	{
		InterlockedExchange(_dustsDeadList[0], _MaximumDusts, prev);
		return;
	}

	uint nextId = _dustsDeadList[prev + 1];
	_dusts[nextId].isActive = 1;
	_dusts[nextId].rotation = 0;
	_dusts[nextId].positionWS = pos;
	_dusts[nextId].velocity = vel;
	_dusts[nextId].force = 0;
	_dusts[nextId].texCoords = float4(0, 0, 1, 0.3333);
	_dusts[nextId].scale = scale;
	_dusts[nextId].oldPosSize = 0;
}

void RemoveDust(uint index)
{
	uint prev;
	InterlockedAdd(_dustsDeadList[0], -1, prev);

	if ((int)prev < 0)
	{
		InterlockedExchange(_dustsDeadList[0], 0, prev);
		return;
	}

	_dustsDeadList[prev + 1] = index;
	_dusts[index].isActive = 0;
}


[numthreads(256, 1, 1)]
void InitializeDeadList (uint3 id : SV_DispatchThreadID)
{
	if (id.x >= _MaximumDusts) return;
	_dustsDeadList[id.x + 1] = id.x;
}

[numthreads(256, 1, 1)]
void ComputeVelocity (uint3 id : SV_DispatchThreadID)
{
	if (id.x >= _MaximumDusts || _dusts[id.x].isActive == 0)
		return;

	Dust2D dust = _dusts[id.x];

	float2 dirToCenter = (_Center - dust.positionWS);
	float2 dir = normalize(dirToCenter);

	//float2 vt = dust.velocity;
	//float2 ft = dust.force;
	//float factor = _Multiplier / (0.1 + dot(dirToCenter, dirToCenter));
	//float2 ft_1 = dirToCenter * factor + float2(dirToCenter.y, -dirToCenter.x) * factor * 0.5;
	//_dusts[id.x].positionWS += vt * _DeltaTime + 0.5 * ft * _DeltaTime * _DeltaTime;
	//_dusts[id.x].velocity += _DeltaTime * 0.5 * (ft + ft_1);

	//_dusts[id.x].force = ft_1;
	
	_dusts[id.x].force = float2(0, 0.05);
	_dusts[id.x].velocity += _dusts[id.x].force * _DeltaTime;
	if (length(_dusts[id.x].velocity) > 8)
	{
		_dusts[id.x].velocity = normalize(_dusts[id.x].velocity) * 8.0;
	}
}

[numthreads(256, 1, 1)]
void UpdatePosition (uint3 id : SV_DispatchThreadID)
{
	if (id.x >= _MaximumDusts || _dusts[id.x].isActive == 0) return;
	
	int l = min(4, _dusts[id.x].oldPosSize);
	_dusts[id.x].oldPosSize++;
	for (int i = l; i >= 1; i--)
	{
		_dusts[id.x].oldPos[i] = _dusts[id.x].oldPos[i - 1];
	}
	_dusts[id.x].oldPos[0] = _dusts[id.x].positionWS;

	float2 posWS = _dusts[id.x].positionWS + _dusts[id.x].velocity * _DeltaTime;
	if(posWS.x < _TileStartOffset.x * 16 || 
		posWS.x >= (_TileStartOffset.x + _TileSize.x) * 16
		|| posWS.y < _TileStartOffset.y * 16 || 
		posWS.y >= (_TileStartOffset.y + _TileSize.y) * 16)
	{
		_dusts[id.x].positionWS += _DeltaTime * _dusts[id.x].velocity;
		return;
	}

	int2 tileCoord = posWS - (_TileStartOffset * 16);
	if(_TileSDF[tileCoord].x < 0)
	{
		float prevs = _TileSDF[tileCoord].x;
		posWS = _dusts[id.x].positionWS;
		tileCoord = posWS - (_TileStartOffset * 16);
		
		float2 N = _TileSDF[tileCoord].yz;
		float2 v = _dusts[id.x].velocity;
		_dusts[id.x].positionWS -= N * prevs;
		
		float2 vn = dot(v, N) * N;
		float2 vt = v - vn;
		_dusts[id.x].velocity = -0.9 * vn + 0.8 * vt;
	}
	_dusts[id.x].positionWS += _DeltaTime * _dusts[id.x].velocity;
}

[numthreads(8, 8, 1)]
void SpawnDusts (uint3 id : SV_DispatchThreadID)
{
	uint rng_state = id.x * 998244353 + id.y * 598244359 + _Frames * 100007;
	rand_pcg(rng_state);
	uint X = rand_pcg(rng_state);

	float x = rand_float(rng_state) * 2 - 1;
	float y = rand_float(rng_state) * 2 - 1;
	float r = rand_float(rng_state) * 2 * 3.14159;
	GenerateNewDust(_Center + float2(x, y) * _Scale, float2(cos(r), sin(r)) * 16.0, float2(8, 8));
}

struct VSInput
{
	float2 GPUInstanceId : POSITION;
};

struct VSInput_Instanced
{
	float2 Position : POSITION;
	float2 TexCoord : TEXCOORD0;
	uint SubVertexId : SV_VertexID;
	uint InstanceId : SV_InstanceID;
};

struct GSInput
{
	uint InstanceId : TEXCOORD0;
};

struct PSInput
{
	float4 Pos : SV_POSITION;
	float4 Color : COLOR0;
	float2 Texcoord : TEXCOORD0;
};

PSInput VertexShaderFunction(VSInput input)
{
	PSInput output;
	output.Pos = float4(1, _dustsReadonly[1].positionWS, 1);
	output.Texcoord = 0;
	output.Color = 0;
	return output;
}


PSInput VertexShaderFunction_Instanced(VSInput_Instanced input)
{
	PSInput output;
	Dust2D dust = _dustsReadonly[input.InstanceId];
	if (dust.isActive > 0.0)
	{
		output.Pos = mul(float4(input.Position * dust.scale, 0, 1) + float4(dust.positionWS, 0, 0), _VPTransform);
	}
	else
	{
		output.Pos = float4(0, 0, 0, 1);
	}
	float4 texCoord = dust.texCoords;
	int id = input.SubVertexId % 4;
	if (id == 0)
	{
		output.Texcoord = float2(texCoord.x, texCoord.y);
	}
	else if (id == 1)
	{
		output.Texcoord = float2(texCoord.z, texCoord.y);
	}
	else if (id == 2)
	{
		output.Texcoord = float2(texCoord.z, texCoord.w);
	}
	else
	{
		output.Texcoord = float2(texCoord.x, texCoord.w);
	}
	output.Color = float4(1, 1, 1, 1);
	return output;
}


GSInput VertexShaderFunction_Billboard(VSInput_Instanced input)
{
	GSInput output;
	output.InstanceId = input.InstanceId;
	return output;
}

[maxvertexcount(24)]
void GeometryShaderFunction_Billboard (point GSInput gIn[1], inout TriangleStream<PSInput> triangleStream)
{
	Dust2D dust = _dustsReadonly[gIn[0].InstanceId];
	if (dust.isActive == 0.0)
		return;
	
	PSInput mainOutput[4];
	float2 texCoordsCorners[4] =
	{
		float2(dust.texCoords.x, dust.texCoords.w),
		float2(dust.texCoords.x, dust.texCoords.x),
		float2(dust.texCoords.z, dust.texCoords.w),
		float2(dust.texCoords.z, dust.texCoords.y)
	};
	
	[unroll(4)]
	for (int i = 0; i < 4; i++)
	{
		mainOutput[i].Pos = mul(float4(defaultVertexPos[i] * dust.scale + dust.positionWS, 0, 1), _VPTransform);
		mainOutput[i].Color = float4(1, 1, 1, 1);
		mainOutput[i].Texcoord = texCoordsCorners[i];
		triangleStream.Append(mainOutput[i]);
	}
	triangleStream.RestartStrip();
	
	if (dust.oldPosSize < 2)
		return;
	
	
	//for (int k = 0; k < min(5, dust.oldPosSize); k++)
	//{
	//	float f = lerp(0.8, 0.1, (k / 4.0));
	//	[unroll(4)]
	//	for (int j = 0; j < 4; j++)
	//	{
	//		mainOutput[j].Pos = mul(float4(defaultVertexPos[j] * dust.scale * f + dust.oldPos[k], 0, 1),
	//			_VPTransform);
	//		mainOutput[j].Color = float4(f, f, f, 1);
	//		mainOutput[j].Texcoord = texCoordsCorners[j];
	//		triangleStream.Append(mainOutput[j]);
	//	}
	//	triangleStream.RestartStrip();
	//}
	for (int k = 0; k < min(5, dust.oldPosSize); k++)
	{
		float2 v1 = dust.velocity;
		
		if (k > 0)
		{
			v1 = dust.oldPos[k - 1] - dust.oldPos[k];
		}
		
		float2 tangent = normalize(v1);
		tangent = float2(-tangent.y, tangent.x);
		
		
		float f = lerp(0.8, 0.1, (k / 4.0));

		mainOutput[0].Pos = mul(float4(tangent * dust.scale * f + dust.oldPos[k], 0, 1),
				_VPTransform);
		mainOutput[0].Color = float4(f, f, f, 1);
		mainOutput[0].Texcoord = float2(0.5, 0.5);
		triangleStream.Append(mainOutput[0]);
		
		mainOutput[1].Pos = mul(float4(-tangent * dust.scale * f + dust.oldPos[k], 0, 1),
				_VPTransform);
		mainOutput[1].Color = float4(f, f, f, 1);
		mainOutput[1].Texcoord = float2(0.5, 0.5);
		triangleStream.Append(mainOutput[1]);
	}
}


Texture2D _DustTexture;
SamplerState _SamplerState
{
	Filter = MIN_MAG_MIP_LINEAR;
};

float4 PixelShaderFunction(PSInput input) : SV_Target
{
	return _DustTexture.SampleLevel(_SamplerState, input.Texcoord, 0) * input.Color;
}

technique11 GPUSimulation
{
	pass InitializeDeadList
	{
		SetComputeShader(CompileShader(cs_5_0, InitializeDeadList()));
	}
	pass ComputeVelocity
	{
		SetComputeShader(CompileShader(cs_5_0, ComputeVelocity()));
	}
	pass UpdatePosition
	{
		SetComputeShader(CompileShader(cs_5_0, UpdatePosition()));
	}
	pass SpawnDusts
	{
		SetComputeShader(CompileShader(cs_5_0, SpawnDusts()));
	}
} 

technique11 GPUDraw
{
	pass DrawDusts
	{
		SetComputeShader(NULL);
		SetVertexShader(CompileShader(vs_5_0, VertexShaderFunction()));
		SetPixelShader(CompileShader(ps_5_0, PixelShaderFunction()));
	}
	pass DrawDusts_Instanced
	{
		SetComputeShader(NULL);
		SetVertexShader(CompileShader(vs_5_0, VertexShaderFunction_Instanced()));
		SetPixelShader(CompileShader(ps_5_0, PixelShaderFunction()));
	}
	pass DrawDusts_Billboard
	{
		SetComputeShader(NULL);
		SetVertexShader(CompileShader(vs_5_0, VertexShaderFunction_Billboard()));
		SetGeometryShader(CompileShader(gs_5_0, GeometryShaderFunction_Billboard()));
		SetPixelShader(CompileShader(ps_5_0, PixelShaderFunction()));
	}
	pass Reset
	{
		SetComputeShader(NULL);
		SetGeometryShader(NULL);
	}
}