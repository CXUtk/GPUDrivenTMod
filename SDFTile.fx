#include "RNG.hlsl"

cbuffer cbSettings
{
	float2	_TileSize;
	float2	_TileStartOffset;
};

Texture2D<float4> 	_TileMap : register(t0);
RWTexture2D<float4> _TileSDF : register(u0);


groupshared uint _tileExistence[9];
groupshared bool _selfContains;
groupshared bool _allEmpty;

static float2 centers[9] = {
	float2(-8, -8),
	float2(8, -8),
	float2(24, -8),
	float2(-8, 8),
	float2(8, 8),
	float2(24, 8),
	float2(-8, 24),
	float2(8, 24),
	float2(24, 24),
};

float sdBox(in float2 p, in float2 b)
{
	float2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float3 sdgBox(in float2 p, in float2 b)
{
    float2 w = abs(p) - b;
    float2 s = float2(p.x < 0.0 ? -1 : 1, p.y < 0.0 ? -1 : 1);
    float g = max(w.x, w.y);
    float2 q = max(w, 0.0);
    float l = length(q);
    return float3((g > 0.0) ? l : g, s * ((g > 0.0) ? q / l : ((w.x > w.y) ? float2(1, 0) : float2(0,1))));
}

[numthreads(16, 16, 1)]
void GenerateSDFTile3x3 (uint3 id : SV_DispatchThreadID, uint3 gid : SV_GroupID, uint3 tid : SV_GroupThreadID)
{
	if (tid.x == 0 && tid.y == 0)
	{
		int2 tileMapCoord = gid.xy;
		_selfContains = _TileMap[tileMapCoord].r > 0;
		_allEmpty = true;
		for (int i = -1; i <= 1; i++)
		{
			for (int j = -1; j <= 1; j++)
			{
				int id = (i + 1) * 3 + (j + 1);
				int2 tileCoord = tileMapCoord + int2(j, i);
				_tileExistence[id] = 0;
				if (tileCoord.x < 0 || tileCoord.x >= _TileSize.x || tileCoord.y < 0 || tileCoord.y >= _TileSize.y)
				{
					continue;
				}
				if (_TileMap[tileCoord].r > 0)
				{
					_tileExistence[id] = 1;
					_allEmpty = false;
				}
			}
		}
	}
	GroupMemoryBarrierWithGroupSync();


	if (_selfContains)
	{
		float3 result = 32;
		for (int i = 0; i < 9; i++)
		{
			if (_tileExistence[i] != 1)
			{
				float3 sdfgd = sdgBox(float2(tid.xy + 0.5) - centers[i], 8.0);
				if (sdfgd.x < result.x)
				{
					result = sdfgd;
				}
			}
		}
		_TileSDF[id.xy] = float4(-result, 0);
	}
	else if (_allEmpty)
	{
		_TileSDF[id.xy] = float4(16, 0, 0, 0);
	}
	else
	{
		float3 result = 32;
		for (int i = 0; i < 9; i++)
		{
			if (_tileExistence[i] != 0)
			{
				float3 sdfgd = sdgBox(float2(tid.xy + 0.5) - centers[i], 8.0);
				if (sdfgd.x < result.x)
				{
					result = sdfgd;
				}
			}
		}
		_TileSDF[id.xy] = float4(result, 0);
	}
}

technique11 SDFTile
{
	pass SDF3x3_TGSM
	{
		SetComputeShader(CompileShader(cs_5_0, GenerateSDFTile3x3()));
	}
}