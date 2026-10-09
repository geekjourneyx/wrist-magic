#include <metal_stdlib>
using namespace metal;
struct EffectParameters { float4 originAndProgress; float4 directionAndOpacity; float4 colorAndFlash; float4 shape; };
struct FrameUniforms { float4x4 viewProjection; float3x3 imageUV; uint effectCount; uint cameraKind; };
struct VertexOut { float4 position [[position]]; float2 uv; };
vertex VertexOut fullScreen(uint id [[vertex_id]]) {
  float2 p = float2((id << 1) & 2, id & 2);
  return { float4(p * float2(2,-2) + float2(-1,1),0,1), p };
}
float2 project(float3 p, constant FrameUniforms &u) {
  float4 c = u.viewProjection * float4(p,1);
  return c.w <= 0.001 ? float2(-10) : float2(c.x/c.w * .5 + .5, .5 - c.y/c.w * .5);
}
float segmentDistance(float2 p,float2 a,float2 b) {
  float2 v=b-a; return length(p-a-v*clamp(dot(p-a,v)/max(dot(v,v),.00001),0.,1.));
}
float3 spell(float2 uv, constant EffectParameters &e, constant FrameUniforms &u) {
  float progress=e.originAndProgress.w;
  float2 a=project(e.originAndProgress.xyz,u);
  float2 b=project(e.originAndProgress.xyz + e.directionAndOpacity.xyz * 1.2,u);
  // Correct screen-space distance for the 9:16 portrait surface.
  float2 p=uv*float2(.5625,1); a*=float2(.5625,1); b*=float2(.5625,1);
  float brightness=0;
  if(e.shape.x < .5) {
    float2 head=mix(a,b,min(progress*1.3,1.));
    float d=length(p-head);
    float trail=segmentDistance(p,mix(a,head,max(0.,progress-.3)),head);
    brightness=exp(-d*d/ .00032)*.9 + exp(-trail*trail/.000045)*.35*(1.-progress);
    brightness+=exp(-d*70.)*.2;
  } else if(e.shape.x < 1.5) {
    float2 previous=a;
    for(uint i=1;i<=9;i++) {
      float f=float(i)/9.;
      float2 next=mix(a,b,f);
      if(i!=9) next.x+=sin(float(i)*13.7+e.shape.y*31.)*.017;
      brightness=max(brightness,exp(-pow(segmentDistance(p,previous,next),2.)/.000018));
      previous=next;
    }
    brightness*=.65*(1.-.55*progress);
    brightness+=exp(-pow(length(p-b),2.)/.0008)*e.colorAndFlash.w;
  } else {
    float2 center=mix(a,b,progress*.55);
    float radius=.015+progress*.12;
    float d=abs(length(p-center)-radius);
    brightness=exp(-d*d/.000035)*.6;
    float angle=atan2(p.y-center.y,p.x-center.x);
    brightness+=exp(-d*d/.00022)*pow(max(0.,sin(angle*13.+e.shape.y*7.)),12.)*.16*e.shape.z;
  }
  return e.colorAndFlash.xyz*min(brightness,.95)*e.directionAndOpacity.w;
}
fragment float4 composite(VertexOut in [[stage_in]], texture2d<float> camera [[texture(0)]], texture2d<float> chroma [[texture(1)]], constant FrameUniforms &u [[buffer(0)]], constant EffectParameters *effects [[buffer(1)]]) {
  constexpr sampler s(filter::linear,address::clamp_to_edge);
  float2 uv=(u.imageUV*float3(in.uv,1)).xy;
  float3 rgb;
  if(u.cameraKind==0) {
    float y=camera.sample(s,uv).r;
    float2 cbcr=chroma.sample(s,uv).rg-float2(.5);
    rgb=float3(y+1.402*cbcr.y,y-.344136*cbcr.x-.714136*cbcr.y,y+1.772*cbcr.x);
  } else { rgb=camera.sample(s,uv).rgb; }
  for(uint i=0;i<u.effectCount;i++) rgb+=spell(in.uv,effects[i],u);
  return float4(clamp(rgb,0.,1.),1);
}
fragment float4 present(VertexOut in [[stage_in]], texture2d<float> image [[texture(0)]]) {
  constexpr sampler s(filter::linear,address::clamp_to_edge); return image.sample(s,in.uv);
}
