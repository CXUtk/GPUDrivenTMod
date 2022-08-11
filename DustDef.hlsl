#pragma once

struct Dust2D
{
    float   isActive; 
    float2  positionWS;
    float2  velocity;
    float2  force;
    float   rotation;
    float2  scale;
    float4  texCoords;

    float2  oldPos[5];
    float   oldPosSize;
};

