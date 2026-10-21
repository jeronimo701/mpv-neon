#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,PWSTR arguments,int show) {
    (void)instance;(void)previous;(void)show;
    wchar_t root[32768],binary[32768],command[32768];
    GetModuleFileNameW(NULL,root,32768);
    wchar_t *slash=wcsrchr(root,L'\\'); if(!slash) return 1; *slash=0;
    if(swprintf(binary,32768,L"%ls\\mpv.exe",root)<0) return 1;
    if(swprintf(command,32768,L"\"%ls\" %ls",binary,arguments)<0) return 1;
    STARTUPINFOW startup={sizeof(startup)}; PROCESS_INFORMATION process={0};
    if(!CreateProcessW(binary,command,NULL,NULL,FALSE,0,NULL,NULL,&startup,&process)) {
        MessageBoxW(NULL,L"mpv.exe was not found or could not start.",L"Player",MB_OK|MB_ICONERROR); return 1;
    }
    CloseHandle(process.hThread); CloseHandle(process.hProcess); return 0;
}
