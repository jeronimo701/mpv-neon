package neon.androidplayer;

import android.content.Context;
import android.graphics.SurfaceTexture;
import android.opengl.GLES11Ext;
import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.os.Handler;
import android.os.Looper;
import android.view.Surface;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/** Renders both eyes from one MediaPlayer decoder. Never buffers a second copy. */
final class StereoView extends GLSurfaceView {
    static final int DUPLICATE = 1, HALF_SBS = 2, FULL_SBS = 3;
    static final int CLEAN = 0, VIGNETTE = 1, SOFT = 2;
    interface Output {
        void ready(Surface surface);
        void failed();
    }
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Eyes eyes;
    private volatile boolean closed;
    private record ViewState(int mode, int effect, float strength, int width, int height, int fitMode) {}
    private volatile ViewState state = new ViewState(DUPLICATE, CLEAN, .4f, 1920, 1080, 0);

    StereoView(Context context, Output callback) {
        super(context);
        setEGLContextClientVersion(2);
        setPreserveEGLContextOnPause(true);
        eyes = new Eyes(callback);
        setRenderer(eyes);
        setRenderMode(RENDERMODE_WHEN_DIRTY);
    }

    void configure(int mode, int effect, int strength, int width, int height, int fitMode) {
        ViewState prev = state;
        state = new ViewState(mode, effect, Math.max(0, Math.min(100, strength)) / 100f,
            width > 0 ? width : prev.width(), height > 0 ? height : prev.height(),fitMode);
        if (!closed) requestRender();
    }

    /** Caller detaches the MediaPlayer surface before closing this view. */
    void dispose() {
        closed = true;
        eyes.release();
    }

    private final class Eyes implements Renderer {
        private final Output callback;
        private final FloatBuffer quad = ByteBuffer.allocateDirect(8 * Float.BYTES)
            .order(ByteOrder.nativeOrder()).asFloatBuffer();
        private final float[] transform = new float[16];
        private SurfaceTexture texture;
        private Surface surface;
        private int textureId, program, xSize, ySize;
        private boolean newFrame, hasFrame, reportedFrame;

        Eyes(Output callback) {
            this.callback = callback;
            quad.put(new float[]{-1,-1, 1,-1, -1,1, 1,1}).position(0);
        }

        @Override public synchronized void onSurfaceCreated(GL10 unused, EGLConfig config) {
            if (closed) return;
            // EGL may be recreated without destroying the Java view.
            Surface previousSurface = surface;
            SurfaceTexture previousTexture = texture;
            surface = null; texture = null;
            hasFrame = newFrame = reportedFrame = false;
            try {
                program = link(VERTEX, FRAGMENT);
                int[] names = new int[1];
                GLES20.glGenTextures(1,names,0);
                textureId = names[0];
                GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId);
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR);
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);
                texture = new SurfaceTexture(textureId);
                texture.setOnFrameAvailableListener(t -> {
                    synchronized (Eyes.this) {
                        if (closed || t != texture) return;
                        newFrame = true;
                    }
                    requestRender();
                }, ui);
                surface = new Surface(texture);
                Surface next = surface;
                ui.post(() -> {
                    try { if (!closed) callback.ready(next); }
                    finally { free(previousSurface, previousTexture); }
                });
            } catch (RuntimeException e) {
                android.util.Log.e("NeonStereo", "Cannot create SBS output", e);
                ui.post(() -> {
                    try { if (!closed) callback.failed(); }
                    finally { free(previousSurface, previousTexture); }
                });
            }
        }

        @Override public synchronized void onSurfaceChanged(GL10 unused, int width, int height) {
            xSize = width; ySize = height;
        }

        @Override public synchronized void onDrawFrame(GL10 unused) {
            GLES20.glViewport(0,0,xSize,ySize);
            GLES20.glClearColor(0f,0f,0f,1f);
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT);
            if (closed || texture == null || xSize < 2 || ySize < 1) return;
            if (newFrame) {
                newFrame = false;
                try {
                    texture.updateTexImage();
                    texture.getTransformMatrix(transform);
                } catch (RuntimeException e) {
                    android.util.Log.e("NeonStereo","SBS texture unavailable",e);
                    ui.post(() -> { if (!closed) callback.failed(); });
                    return;
                }
                hasFrame = true;
            }
            if (!hasFrame) return;
            ViewState cfg = state;
            int eyeWidth = xSize / 2;
            float eyeAspect = eyeWidth / (float)ySize;
            float sourceAspect = cfg.width() / (float)cfg.height();
            if (cfg.mode() == FULL_SBS) sourceAspect *= .5f;
            float fitX = Math.min(1f, sourceAspect / eyeAspect);
            float fitY = Math.min(1f, eyeAspect / sourceAspect);
            switch (cfg.fitMode()) {
                case 1 -> {fitX=1;fitY=eyeAspect/sourceAspect;}
                case 2 -> {fitX=sourceAspect/eyeAspect;fitY=1;}
                case 3 -> {fitX=Math.max(1f,sourceAspect/eyeAspect);fitY=Math.max(1f,eyeAspect/sourceAspect);}
                case 4 -> {fitX=1;fitY=1;}
            }
            GLES20.glUseProgram(program);
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,textureId);
            GLES20.glUniform1i(u("image"),0);
            GLES20.glUniformMatrix4fv(u("transform"),1,false,transform,0);
            GLES20.glUniform2f(u("fit"),fitX,fitY);
            GLES20.glUniform1i(u("mode"),cfg.mode());
            GLES20.glUniform1i(u("style"), cfg.effect());
            GLES20.glUniform1f(u("strength"),cfg.strength());
            GLES20.glUniform2f(u("texel"),1f/cfg.width(),1f/cfg.height());
            int position = GLES20.glGetAttribLocation(program,"position");
            quad.position(0);
            GLES20.glEnableVertexAttribArray(position);
            GLES20.glVertexAttribPointer(position,2,GLES20.GL_FLOAT,false,0,quad);
            for (int eye=0;eye<2;eye++) {
                GLES20.glViewport(eye * eyeWidth,0,eyeWidth,ySize);
                GLES20.glUniform1f(u("eye"),eye);
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP,0,4);
            }
            GLES20.glDisableVertexAttribArray(position);
            if (!reportedFrame) {
                reportedFrame = true;
                android.util.Log.i("NeonStereo", "First SBS frame: " + xSize + "x" + ySize);
            }
        }

        private int u(String name) { return GLES20.glGetUniformLocation(program,name); }
        synchronized void release() {
            free(surface,texture); surface=null; texture=null;
        }
    }

    private static void free(Surface surface, SurfaceTexture texture) {
        if (surface != null) surface.release();
        if (texture != null) texture.release();
    }
    private static int shader(int type, String code) {
        int s = GLES20.glCreateShader(type);
        GLES20.glShaderSource(s,code); GLES20.glCompileShader(s);
        int[] ok = new int[1];
        GLES20.glGetShaderiv(s,GLES20.GL_COMPILE_STATUS,ok,0);
        if (ok[0] == 0) {
            String error=GLES20.glGetShaderInfoLog(s);
            GLES20.glDeleteShader(s);
            throw new IllegalStateException(error);
        }
        return s;
    }
    private static int link(String vert, String frag) {
        int v=shader(GLES20.GL_VERTEX_SHADER,vert), f=shader(GLES20.GL_FRAGMENT_SHADER,frag);
        int p=GLES20.glCreateProgram();
        GLES20.glAttachShader(p,v); GLES20.glAttachShader(p,f); GLES20.glLinkProgram(p);
        GLES20.glDeleteShader(v); GLES20.glDeleteShader(f);
        int[] ok=new int[1]; GLES20.glGetProgramiv(p,GLES20.GL_LINK_STATUS,ok,0);
        if (ok[0]==0) {
            String error=GLES20.glGetProgramInfoLog(p);
            GLES20.glDeleteProgram(p); throw new IllegalStateException(error);
        }
        return p;
    }
    private static final String VERTEX = """
        attribute vec2 position;
        varying vec2 uv;
        void main() { uv=position*0.5+0.5; gl_Position=vec4(position,0.,1.); }
        """;
    private static final String FRAGMENT = """
        #extension GL_OES_EGL_image_external : require
        #ifdef GL_FRAGMENT_PRECISION_HIGH
        precision highp float;
        #else
        precision mediump float;
        #endif
        uniform samplerExternalOES image;
        uniform mat4 transform;
        uniform vec2 fit;
        uniform vec2 texel;
        uniform int mode;
        uniform int style;
        uniform float strength;
        uniform float eye;
        varying vec2 uv;
        vec3 sampleEye(vec2 p) {
            vec2 margin=texel*vec2(mode != 1 ? 1.25 : .65,.65);
            p=clamp(p,margin,1.-margin);
            if (mode != 1) p.x=(p.x+eye)*.5;
            vec2 st=(transform*vec4(p,0.,1.)).xy;
            return texture2D(image,st).rgb;
        }
        void main() {
            vec2 p=(uv-.5)/fit+.5;
            if (style == 2 && strength > 0.) {
                // Far edge of the apparent screen is slightly narrower.
                float recession=1.-.10*strength*clamp(p.y,0.,1.);
                p.x=(p.x-.5)/recession+.5;
            }
            vec2 edges=min(p,1.-p);
            float e=min(edges.x,edges.y);
            if (e<0.) { gl_FragColor=vec4(0.,0.,0.,1.); return; }
            vec3 rgb=sampleEye(p);
            float a=1.;
            if (style != 0 && strength > 0.) {
                float width=.14*strength;
                // A curved corner, with softness measured in image space.
                vec2 corner=max(vec2(width)-edges,vec2(0.));
                float d=width-length(corner);
                float fade=smoothstep(0.,width,d);
                if (style == 2 && fade < .999) {
                    vec2 r=texel*mix(2.,14.,strength)*(1.-fade);
                    r.x *= mode == 1 ? 1. : 2.;
                    vec3 blur=(sampleEye(p+vec2(r.x,0.))+sampleEye(p-vec2(r.x,0.))
                        +sampleEye(p+vec2(0.,r.y))+sampleEye(p-vec2(0.,r.y)))*.25;
                    rgb=mix(rgb,blur,1.-fade);
                    a=fade;
                } else if (style == 1) {
                    a=mix(1.,fade,.35+.65*strength);
                }
            }
            gl_FragColor=vec4(rgb*a,1.);
        }
        """;
}
