// Personal ambient canvas, gpu-next/libplacebo. No CPU filters or screen capture.
//!PARAM ambient_mode
//!TYPE int
//!MINIMUM 1
//!MAXIMUM 4
1
//!PARAM ambient_aspect
//!TYPE float
//!MINIMUM 0.1
//!MAXIMUM 10
1.3333333
//!PARAM ambient_source
//!TYPE float
//!MINIMUM 0.1
//!MAXIMUM 10
1.7777778
//!PARAM ambient_brightness
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.8
//!PARAM ambient_coverage
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.8
//!PARAM ambient_blur
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 128
32
//!PARAM ambient_reaction
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 2
0.3
//!PARAM ambient_clock
//!TYPE DYNAMIC float
0
//!PARAM ambient_serial
//!TYPE float
1

//!TEXTURE AMB_STATE
//!SIZE 64 36
//!FORMAT rgba32f
//!FILTER NEAREST
//!STORAGE

//!TEXTURE AMB_STAMP
//!SIZE 64 36
//!FORMAT rgba32f
//!FILTER NEAREST
//!STORAGE

//!TEXTURE AMB_HISTORY
//!SIZE 64 576
//!FORMAT rgba32f
//!FILTER NEAREST
//!STORAGE

//!HOOK MAIN
//!BIND HOOKED
//!BIND AMB_STATE
//!BIND AMB_STAMP
//!BIND AMB_HISTORY
//!SAVE AMB_SMALL
//!WIDTH 64
//!HEIGHT 36
//!COMPUTE 8 8
//!DESC Ambient temporal sample 64x36
void hook() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if(p.x>=64 || p.y>=36) return;
    vec2 uv=(vec2(p)+0.5)/vec2(64,36);
    vec3 now=HOOKED_tex(uv).rgb;
    vec4 stamp=imageLoad(AMB_STAMP,p);
    vec3 old=imageLoad(AMB_STATE,p).rgb;
    float dt=ambient_clock-stamp.x;
    bool reset=frame<2 || stamp.y!=ambient_serial || dt<0.0 || dt>1.0;
    float a=ambient_reaction<=0.0?1.0:1.0-exp(-max(dt,0.0)/ambient_reaction);
    vec3 color=reset?now:mix(old,now,a);
    imageStore(AMB_STATE,p,vec4(color,1.0));
    imageStore(AMB_STAMP,p,vec4(ambient_clock,ambient_serial,0.0,1.0));
    if(reset) for(int i=0;i<16;i++) imageStore(AMB_HISTORY,ivec2(p.x,p.y+i*36),vec4(0));
    int slot=int(mod(floor(max(ambient_clock,0.0)*12.0),16.0));
    imageStore(AMB_HISTORY,ivec2(p.x,p.y+slot*36),vec4(color,ambient_serial));
    imageStore(out_image,p,vec4(color,1));
}

//!HOOK MAIN
//!BIND AMB_SMALL
//!SAVE AMB_H
//!WIDTH 64
//!HEIGHT 36
//!DESC Ambient horizontal blur
vec4 hook() {
    if(ambient_blur<0.01) return AMB_SMALL_tex(AMB_SMALL_pos);
    float sigma=max(0.2,ambient_blur/16.0);
    vec4 total=vec4(0); float weights=0;
    for(int i=-12;i<=12;i++) {
        float w=exp(-float(i*i)/(2.0*sigma*sigma));
        total+=AMB_SMALL_tex(AMB_SMALL_pos+vec2(float(i)/64.0,0))*w; weights+=w;
    }
    return total/weights;
}

//!HOOK MAIN
//!BIND AMB_H
//!SAVE AMB_BLUR
//!WIDTH 64
//!HEIGHT 36
//!DESC Ambient vertical blur
vec4 hook() {
    if(ambient_blur<0.01) return AMB_H_tex(AMB_H_pos);
    float sigma=max(0.2,ambient_blur/16.0);
    vec4 total=vec4(0); float weights=0;
    for(int i=-12;i<=12;i++) {
        float w=exp(-float(i*i)/(2.0*sigma*sigma));
        total+=AMB_H_tex(AMB_H_pos+vec2(0,float(i)/36.0))*w; weights+=w;
    }
    return total/weights;
}

//!HOOK MAIN
//!BIND HOOKED
//!BIND AMB_BLUR
//!BIND AMB_HISTORY
//!WIDTH ambient_source ambient_aspect > HOOKED.w * ambient_source ambient_aspect > ! HOOKED.w ambient_source / ambient_aspect * * +
//!HEIGHT ambient_source ambient_aspect > HOOKED.w ambient_aspect / * ambient_source ambient_aspect > ! HOOKED.w ambient_source / * +
//!DESC Ambient canvas (film passthrough)
vec3 echo_sample(vec2 uv,float delay) {
    int slot=int(mod(floor(max(ambient_clock-delay,0.0)*12.0),16.0));
    vec2 p=clamp(uv,vec2(0),vec2(1))*vec2(63,35);
    ivec2 lo=ivec2(floor(p)); ivec2 hi=min(lo+1,ivec2(63,35));
    vec2 f=fract(p);
    vec4 c00=imageLoad(AMB_HISTORY,ivec2(lo.x,lo.y+slot*36));
    vec4 c10=imageLoad(AMB_HISTORY,ivec2(hi.x,lo.y+slot*36));
    vec4 c01=imageLoad(AMB_HISTORY,ivec2(lo.x,hi.y+slot*36));
    vec4 c11=imageLoad(AMB_HISTORY,ivec2(hi.x,hi.y+slot*36));
    if(c00.a!=ambient_serial) return AMB_BLUR_tex(clamp(uv,vec2(0),vec2(1))).rgb;
    return mix(mix(c00.rgb,c10.rgb,f.x),mix(c01.rgb,c11.rgb,f.x),f.y);
}
vec4 hook() {
    vec2 image_size=vec2(HOOKED_size.x,HOOKED_size.x/ambient_source);
    vec2 canvas=vec2(max(image_size.x,image_size.y*ambient_aspect),max(image_size.y,image_size.x/ambient_aspect));
    vec2 offset=(canvas-image_size)*0.5;
    vec2 point=HOOKED_pos*canvas;
    vec2 uv=(point-offset)/image_size;
    if(all(greaterThanEqual(uv,vec2(0))) && all(lessThanEqual(uv,vec2(1)))) return HOOKED_tex(uv);
    vec2 outside=max(max(-uv,uv-1.0),vec2(0))*image_size;
    float distance=max(outside.x/max(offset.x,0.001),outside.y/max(offset.y,0.001));
    float reach=max(0.0001,ambient_coverage);
    float fade=pow(clamp(1.0-distance/reach,0.0,1.0),0.55);
    vec2 sample_uv=clamp(uv,vec2(0),vec2(1));
    if(ambient_mode==2) {
        float cover=max(canvas.x/image_size.x,canvas.y/image_size.y);
        sample_uv=(point-canvas*0.5)/(image_size*cover)+0.5;
    } else if(ambient_mode==4) {
        sample_uv=1.0-abs(mod(uv,2.0)-1.0);
    }
    vec3 color=AMB_BLUR_tex(clamp(sample_uv,vec2(0),vec2(1))).rgb;
    if(ambient_mode==4 && ambient_blur<0.01 && ambient_reaction<=0.0) color=HOOKED_tex(clamp(sample_uv,vec2(0),vec2(1))).rgb;
    if(ambient_mode==3) {
        vec3 trail=vec3(0); float sigma=ambient_blur/1024.0;
        for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) trail+=echo_sample(sample_uv+vec2(x,y)*sigma,distance*1.1);
        color=trail/9.0;
        fade*=0.65+0.35*cos(distance*18.8495559-ambient_clock*4.0);
    }
    return vec4(color*ambient_brightness*fade,1.0);
}
