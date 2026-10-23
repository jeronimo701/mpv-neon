"""Isolated public installer upgrade and playback/LSFG smoke test."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import time

p=argparse.ArgumentParser()
p.add_argument('--payload',required=True,type=Path)
p.add_argument('--installer',required=True,type=Path)
p.add_argument('--work',required=True,type=Path)
a=p.parse_args()
payload=a.payload.resolve(); installer=a.installer.resolve(); work=a.work.resolve()
work.mkdir(parents=True,exist_ok=False)
dest=work/'portable update'; cfg=dest/'portable_config'
cfg.mkdir(parents=True)
custom='# keep user shortcuts\nSPACE cycle pause\n'
theme='{"theme":"youtube","accent":"youtube"}'
(cfg/'input.conf').write_text(custom,encoding='utf-8')
(cfg/'ui-theme.json').write_text(theme,encoding='utf-8')
serverdir=dest/'runtime/torrserver';serverdir.mkdir(parents=True)
binary=serverdir/'TorrServer-windows-amd64.exe'
shutil.copy2(payload/'runtime/torrserver'/binary.name,binary)
data=work/'server-data';data.mkdir()
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
server=subprocess.Popen([str(binary),'--ip','127.0.0.1','--port',str(port),'--path',str(data),'--logpath',str(data/'server.log')],creationflags=subprocess.CREATE_NO_WINDOW,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
    time.sleep(1)
    assert server.poll() is None,'Test TorrServer failed to start'
    subprocess.run([str(installer),'/CURRENTUSER','/MODE=portable','/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/NOICONS','/TASKS=','/DIR='+str(dest),'/LOG='+str(work/'installer.log')],check=True,timeout=240)
    server.wait(timeout=10)
    assert (cfg/'input.conf').read_text(encoding='utf-8')==custom
    assert (cfg/'ui-theme.json').read_text(encoding='utf-8')==theme
    assert not (dest/'installation-mode.txt').exists()
    assert not (dest/'uninstall').exists()
    assert not list(dest.rglob('Lossless.dll'))
    assert not (dest/'Player.exe').exists()
    for f in payload.rglob('*'):
        if not f.is_file():continue
        rel=f.relative_to(payload)
        if rel.as_posix()=='portable_config/input.conf':continue
        assert (dest/rel).read_bytes()==f.read_bytes(),str(rel)
    print('PASS public installer: isolated portable upgrade, running bundled TorrServer stopped, user input/theme preserved, all payload bytes match',flush=True)
finally:
    if server.poll() is None:
        server.terminate();server.wait(timeout=10)

pipe=r'\\.\pipe\mpv-neon-public-'+str(os.getpid())
log=work/'mpv.log'
player=subprocess.Popen([str(dest/'mpv.com'),'--config-dir='+str(cfg),'--vo=null','--ao=null','--force-window=no','--idle=yes','--input-ipc-server='+pipe,'--log-file='+str(log)],creationflags=subprocess.CREATE_NO_WINDOW,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
def cmd(*args):
    with open(pipe,'r+b',buffering=0) as f:
        f.write((json.dumps({'command':args,'request_id':1})+'\n').encode())
        while True:
            line=f.readline()
            if not line:raise RuntimeError('IPC disconnected')
            result=json.loads(line)
            if result.get('request_id')==1:return result
try:
    for _ in range(150):
        try:
            assert cmd('get_property','idle-active')['error']=='success'
            break
        except (OSError,AssertionError):time.sleep(.1)
    else:raise AssertionError('Player IPC not ready')
    time.sleep(1)
    assert cmd('loadfile','av://lavfi:color=c=black:s=64x64:r=10:d=2')['error']=='success'
    for _ in range(80):
        r=cmd('get_property','time-pos')
        if r.get('error')=='success' and r.get('data',0)>0:break
        time.sleep(.05)
    else:raise AssertionError('Synthetic video did not play')
    print('PASS synthetic video playback with public configs/scripts and null audio/video output',flush=True)
    assert cmd('script-message','lsfg-native-probe')['error']=='success'
    for _ in range(100):
        r=cmd('get_property','user-data/lsfg/error')
        if 'Lossless.dll could not be loaded' in r.get('data',''):break
        time.sleep(.05)
    else:raise AssertionError('Missing DLL was not reported')
    assert cmd('get_property','mpv-version')['error']=='success'
    print('PASS missing Lossless.dll: native module reports unavailable, player remains responsive',flush=True)
finally:
    try:cmd('quit')
    except OSError:pass
    try:player.wait(timeout=10)
    except subprocess.TimeoutExpired:player.terminate();player.wait(timeout=10)
assert player.returncode==0,player.returncode
text=log.read_text(encoding='utf-8')
assert 'Lua error' not in text and 'stack traceback' not in text
print('PASS no Lua errors; player exit 0. UAC/GPU/real installation not tested.',flush=True)

# Exercise installed-mode profile migration without registering an installation.
(dest/'installation-mode.txt').write_text('user',encoding='ascii')
profile=work/'isolated-user-profile'
env=os.environ.copy();env['MPV_NEON_PROFILE_ROOT']=str(profile)
subprocess.run([str(dest/'mpv-neon.exe'),'--neon-prepare-only'],env=env,check=True,timeout=30)
assert (profile/'portable_config/input.conf').read_text(encoding='utf-8')==custom
assert (profile/'portable_config/ui-theme.json').read_text(encoding='utf-8')==theme
assert (profile/'build-id.txt').read_text().strip()=='mpv-neon-v12-public'
assert (profile/'runtime').resolve()==(dest/'runtime').resolve()
print('PASS compiled launcher: isolated installed-mode profile prepared, custom settings preserved',flush=True)
