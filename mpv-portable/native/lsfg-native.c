/* Personal mpv C plugin. Lossless Scaling ABI reference: Jossec101/openls (MIT).
 * Loads the user's local Lossless.dll; never changes the Steam installation.
 * The LS engine still captures the mpv window, not decoded-frame textures.
 */
#define WIN32_LEAN_AND_MEAN
#define MPV_CPLUGIN_DYNAMIC_SYM
#include <windows.h>
#include <ole2.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mpv/client.h>

typedef void (__cdecl *StatusFn)(int, HWND, int, int, int, int, bool, float, int);
typedef bool (__cdecl *InitFn)(StatusFn);
typedef void (__cdecl *UnInitFn)(void);
typedef bool (__cdecl *ActivateFn)(HWND);
typedef void (__cdecl *SettingsFn)(int,int,int,int,float,bool,int,bool,
    int,int,int,float,float,int,bool,bool,bool,bool,int,int,bool,bool,
    int,int,bool,int,int,int,int,int,int,bool,int);
typedef float (__cdecl *RefreshFn)(void);

static mpv_handle *client;
static HMODULE core;
static InitFn core_init;
static UnInitFn core_uninit;
static ActivateFn core_activate;
static SettingsFn core_settings;
static RefreshFn core_refresh;
static bool initialized;
static volatile LONG core_status, core_error, input_w, input_h, output_w, output_h;
static int selected_target;
static HWND target_window;
static int pending_target;
static ULONGLONG pending_time;
static int model=1, flow=50, generation_mode=1, capture=1, draw_fps=1;
static float multiplier=2.0f;
static HWND branded_window;
static HICON brand_small, brand_large;

static void status_callback(int status, HWND window, int iw, int ih,
    int ow, int oh, bool resized, float scale, int error) {
    (void)window; (void)resized; (void)scale;
    InterlockedExchange(&core_status,status); InterlockedExchange(&core_error,error);
    InterlockedExchange(&input_w,iw); InterlockedExchange(&input_h,ih);
    InterlockedExchange(&output_w,ow); InterlockedExchange(&output_h,oh);
}
static void set_text(const char *key, const char *value) {
    mpv_set_property_string(client,key,value);
}
static void set_number(const char *key, int64_t value) {
    mpv_set_property(client,key,MPV_FORMAT_INT64,&value);
}
static void message(const char *text) {
    const char *args[]={"show-text",text,"4500",NULL}; mpv_command(client,args);
}
static void report_error(const char *text) {
    set_text("user-data/lsfg/error",text); message(text);
}
static void pump(void) {
    MSG msg;
    while(PeekMessageW(&msg,NULL,0,0,PM_REMOVE)) {
        TranslateMessage(&msg); DispatchMessageW(&msg);
    }
}
static BOOL CALLBACK find_window(HWND hwnd, LPARAM arg) {
    DWORD pid=0; GetWindowThreadProcessId(hwnd,&pid);
    if(pid==GetCurrentProcessId() && IsWindowVisible(hwnd) && !GetWindow(hwnd,GW_OWNER)) {
        wchar_t cls[128]; GetClassNameW(hwnd,cls,128);
        if(wcscmp(cls,L"mpv")==0) { *(HWND*)arg=hwnd; return FALSE; }
    }
    return TRUE;
}
static HWND player_window(void) {
    HWND result=NULL; EnumWindows(find_window,(LPARAM)&result); return result;
}
static void brand_window(void) {
    if(branded_window && IsWindow(branded_window)) return;
    HWND window=player_window();
    if(!window || window==branded_window) return;
    if(!brand_large) {
        const char *args[]={"expand-path","~~/../assets/player-neon-07.ico",NULL};
        mpv_node result={0};
        if(mpv_command_ret(client,args,&result)<0 || result.format!=MPV_FORMAT_STRING) return;
        wchar_t path[32768];
        MultiByteToWideChar(CP_UTF8,0,result.u.string,-1,path,32768);
        mpv_free_node_contents(&result);
        brand_small=(HICON)LoadImageW(NULL,path,IMAGE_ICON,32,32,LR_LOADFROMFILE);
        brand_large=(HICON)LoadImageW(NULL,path,IMAGE_ICON,256,256,LR_LOADFROMFILE);
    }
    if(brand_large) {
        SendMessageW(window,WM_SETICON,ICON_SMALL,(LPARAM)brand_small);
        SendMessageW(window,WM_SETICON,ICON_BIG,(LPARAM)brand_large);
        branded_window=window;
        set_text("user-data/player/window-icon","neon-07");
    }
}
static bool load_core(void) {
    if(core) return true;
    const char *args[]={"expand-path","~~/../runtime/lsfg/Lossless.dll",NULL};
    mpv_node result={0};
    if(mpv_command_ret(client,args,&result)<0 || result.format!=MPV_FORMAT_STRING) return false;
    wchar_t path[32768];
    MultiByteToWideChar(CP_UTF8,0,result.u.string,-1,path,32768);
    mpv_free_node_contents(&result);
    core=LoadLibraryExW(path,NULL,LOAD_WITH_ALTERED_SEARCH_PATH);
    if(!core) { report_error("LSFG: local Lossless.dll could not be loaded."); return false; }
    core_init=(InitFn)GetProcAddress(core,"Init");
    core_uninit=(UnInitFn)GetProcAddress(core,"UnInit");
    core_activate=(ActivateFn)GetProcAddress(core,"Activate");
    core_settings=(SettingsFn)GetProcAddress(core,"ApplySettings");
    core_refresh=(RefreshFn)GetProcAddress(core,"GetDwmRefreshRate");
    if(!core_init || !core_uninit || !core_activate || !core_settings || !core_refresh) {
        report_error("LSFG: incompatible DLL exports."); FreeLibrary(core); core=NULL; return false;
    }
    set_text("user-data/lsfg/backend","native-dll-window-capture");
    return true;
}
static bool stop_generation(void) {
    if(!initialized || !selected_target) return true;
    bool ok=false;
    __try { ok=core_activate(NULL); }
    __except(EXCEPTION_EXECUTE_HANDLER) { report_error("LSFG: exception while stopping the native core."); }
    selected_target=0; set_number("user-data/lsfg/target",0);
    for(int i=0;i<30 && core_status!=0;i++) { pump(); Sleep(10); }
    return ok;
}
static void select_mode(int target) {
    if(target==0) { pending_target=0; stop_generation(); message("LSFG: off"); return; }
    if(target!=60 && target!=120) return;
    if(selected_target || pending_target) {
        stop_generation();
        pending_target=target; pending_time=GetTickCount64()+1200;
        message("LSFG: switching mode...");
        return;
    }
    target_window=player_window();
    if(!target_window) { report_error("LSFG: open a video window first."); return; }
    if(!load_core()) return;
    if(!initialized) {
        bool ok=false;
        __try { ok=core_init(status_callback); }
        __except(EXCEPTION_EXECUTE_HANDLER) { ok=false; }
        if(!ok) {
            report_error("LSFG Init failed. Close the original Lossless Scaling app if running."); return;
        }
        initialized=true;
    }
    bool ok=false;
    __try {
        /* No spatial scaling. Model, mode, flow, capture and overlay come from F6.
         * No driver changes or cursor clipping; queued presentation.
         */
        core_settings(0,0,0,0,1.0f,false,0,false,
            1,model,generation_mode,multiplier,(float)target,flow,
            false,false,false,false,1,3,false,false,
            capture,1,draw_fps!=0,0,0,0,0,0,0,false,0);
        ok=core_activate(target_window);
    } __except(EXCEPTION_EXECUTE_HANDLER) {
        report_error("LSFG: native activation failed. The player remains usable."); return;
    }
    if(!ok) { report_error("LSFG: Activate returned false."); return; }
    selected_target=target;
    set_number("user-data/lsfg/target",target);
    set_text("user-data/lsfg/error","");
    char text[80]; snprintf(text,sizeof(text),"LSFG DLL: target %d fps (waiting for capture status)",target); message(text);
}

__declspec(dllexport) int mpv_open_cplugin(mpv_handle *handle) {
    client=handle;
    HRESULT apartment=OleInitialize(NULL);
    if(FAILED(apartment)) { report_error("LSFG: could not initialize STA/OLE."); return 0; }
    MSG dummy; PeekMessageW(&dummy,NULL,0,0,PM_NOREMOVE);
    set_text("user-data/lsfg/backend","native-plugin-ready");
    set_number("user-data/lsfg/target",0);
    set_text("user-data/lsfg/status","off");
    bool running=true;
    LONG last_status=-1,last_error=-1;
    while(running) {
        pump();
        brand_window();
        if(pending_target && GetTickCount64()>=pending_time) {
            int target=pending_target; pending_target=0; select_mode(target);
        }
        mpv_event *event=mpv_wait_event(client,0.01);
        if(event->event_id==MPV_EVENT_SHUTDOWN) running=false;
        else if(event->event_id==MPV_EVENT_CLIENT_MESSAGE) {
            mpv_event_client_message *msg=event->data;
            if(msg->num_args>=2 && strcmp(msg->args[0],"lsfg-native-set")==0) select_mode(atoi(msg->args[1]));
            if(msg->num_args==7 && strcmp(msg->args[0],"lsfg-native-config")==0) {
                int m=atoi(msg->args[1]), f=atoi(msg->args[2]), g=atoi(msg->args[3]);
                float x=(float)atof(msg->args[4]);
                int c=atoi(msg->args[5]), d=atoi(msg->args[6]);
                if((m==0 || m==1) && f>=25 && f<=100 && (g==0 || g==1)
                    && x>=2 && x<=4 && (c==0 || c==1) && (d==0 || d==1)) {
                    model=m; flow=f; generation_mode=g; multiplier=x; capture=c; draw_fps=d;
                    set_number("user-data/lsfg/model",model);
                    set_number("user-data/lsfg/flow",flow);
                    set_number("user-data/lsfg/mode",generation_mode);
                    double mx=multiplier;
                    mpv_set_property(client,"user-data/lsfg/multiplier",MPV_FORMAT_DOUBLE,&mx);
                    set_number("user-data/lsfg/capture",capture);
                    set_number("user-data/lsfg/draw-fps",draw_fps);
                    int restart=pending_target?pending_target:selected_target;
                    if(restart) select_mode(restart);
                }
            }
            if(msg->num_args>=1 && strcmp(msg->args[0],"lsfg-native-probe")==0 && load_core()) {
                float hz=core_refresh(); double value=hz;
                mpv_set_property(client,"user-data/lsfg/display-hz",MPV_FORMAT_DOUBLE,&value);
                set_text("user-data/lsfg/probe","exports-ok");
            }
        }
        LONG status=core_status,error=core_error;
        if(status!=last_status || error!=last_error) {
            set_text("user-data/lsfg/status",status==2?"active":status==1?"paused":"off");
            set_number("user-data/lsfg/error-code",error);
            set_number("user-data/lsfg/input-width",input_w); set_number("user-data/lsfg/input-height",input_h);
            set_number("user-data/lsfg/output-width",output_w); set_number("user-data/lsfg/output-height",output_h);
            if(error) report_error("LSFG: capture error; try a smaller player window.");
            last_status=status; last_error=error;
        }
    }
    stop_generation();
    if(initialized) {
        __try { core_uninit(); } __except(EXCEPTION_EXECUTE_HANDLER) {}
    }
    if(core) FreeLibrary(core);
    OleUninitialize();
    return 0;
}
