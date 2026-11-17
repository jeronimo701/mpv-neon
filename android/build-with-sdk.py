from pathlib import Path
import os, subprocess, shutil, zipfile, sys
project=Path(__file__).resolve().parent
sdk=Path(os.environ.get('ANDROID_HOME') or Path(os.environ['LOCALAPPDATA'])/'Android/Sdk')
home=Path(os.environ['JAVA_HOME']) if os.environ.get('JAVA_HOME') else Path(shutil.which('javac')).resolve().parent.parent
bt=sdk/'build-tools/35.0.0'
platform=sdk/'platforms/android-35/android.jar'
build=project/'build/sdk-tools'
classes=build/'classes'
classes.mkdir(parents=True,exist_ok=True)
for old_class in classes.rglob('*.class'):
    old_class.unlink()
def run(*args):
    args=[str(a) for a in args]
    if args[0].lower().endswith('.bat'):
        subprocess.run(subprocess.list2cmdline(args),shell=True,check=True)
    else:
        subprocess.run(args,check=True)
coords=[
 ('com.hierynomus','smbj','0.14.0'),
 ('org.slf4j','slf4j-api','2.0.9'),
 ('org.bouncycastle','bcprov-jdk18on','1.79'),
 ('net.engio','mbassador','1.3.0'),
 ('com.hierynomus','asn-one','0.6.0'),
]
deps=[]
for group,artifact,version in coords:
    name=f'{artifact}-{version}.jar'
    path=build/name
    if not path.exists() or not zipfile.is_zipfile(path):
        tmp=path.with_suffix('.download')
        run('curl.exe','--fail','--location','--silent','--show-error','--max-time','45',
            f'https://repo.maven.apache.org/maven2/{group.replace(".","/")}/{artifact}/{version}/{name}', '-o',tmp)
        tmp.replace(path)
    # Android doesn't select multi-release JAR versions.
    cleaned=build/f'android-{name}'
    with zipfile.ZipFile(path) as src, zipfile.ZipFile(cleaned,'w',zipfile.ZIP_DEFLATED) as dst:
        for entry in src.infolist():
            if entry.filename.endswith('.class') and not entry.filename.startswith('META-INF/') and entry.filename != 'module-info.class':
                dst.writestr(entry,src.read(entry))
    deps.append(cleaned)
src=project/'app/src/main'
res=build/'resources.zip'
run(bt/'aapt2.exe','compile','--dir',src/'res','-o',res)
raw=build/'base.apk'
run(bt/'aapt2.exe','link','-I',platform,'--manifest',src/'AndroidManifest.xml','--min-sdk-version','24',
    '--target-sdk-version','35','--version-code','4','--version-name','0.4.0','-o',raw,res,'--java',build)
run(home/'bin/javac.exe','-encoding','UTF-8','-source','17','-target','17','-cp',
    os.pathsep.join(map(str,[platform,*deps])),'-d',classes,*sorted((src/'java').rglob('*.java')),*sorted(build.rglob('R.java')))
dex=build/'dex.zip'
licenses = [('META-INF/NEON-THIRD-PARTY.txt', (project/'THIRD-PARTY.txt').read_bytes())] if (project/'THIRD-PARTY.txt').exists() else []
for (_,artifact,_), cleaned in zip(coords,deps):
    with zipfile.ZipFile(build/cleaned.name.removeprefix('android-')) as z:
        for name in z.namelist():
            if Path(name).name.upper().startswith(('LICENSE','NOTICE')) and not name.endswith('/'):
                licenses.append((f'META-INF/licenses/{artifact}/{Path(name).name}',z.read(name)))
run(home/'bin/java.exe','-Xmx1536m','-cp',bt/'lib/d8.jar','com.android.tools.r8.D8','--min-api','24',
    '--lib',platform,'--release','--output',dex,*sorted(classes.rglob('*.class')),*deps)
with zipfile.ZipFile(raw,'a',zipfile.ZIP_DEFLATED) as apk, zipfile.ZipFile(dex) as z:
    for name in z.namelist():
        if name.endswith('.dex'): apk.writestr(name,z.read(name))
    for name,content in licenses: apk.writestr(name,content)
aligned=build/'aligned.apk'
run(bt/'zipalign.exe','-f','4',raw,aligned)
key=build/'debug.jks'
if not key.exists():
    run(home/'bin/keytool.exe','-genkeypair','-keystore',key,'-storepass','android','-keypass','android',
        '-alias','androiddebugkey','-keyalg','RSA','-keysize','2048','-validity','10000','-dname','CN=Android Debug,O=Neon Prototype,C=US')
out=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else build/'neon-android-debug.apk'
run(bt/'apksigner.bat','sign','--ks',key,'--ks-pass','pass:android','--key-pass','pass:android','--out',out,aligned)
run(bt/'apksigner.bat','verify','--verbose',out)
print(out, out.stat().st_size, 'bytes')
