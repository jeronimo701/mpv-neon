using System;
using System.IO;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Text;
using System.Windows.Forms;
using System.Threading;

static class Launcher {
    public static string Quote(string s) {
        var b=new StringBuilder("\""); int slashes=0;
        foreach(char c in s) {
            if(c=='\\') { slashes++; continue; }
            if(c=='"') b.Append('\\',slashes*2+1).Append(c);
            else b.Append('\\',slashes).Append(c);
            slashes=0;
        }
        return b.Append('\\',slashes*2).Append('"').ToString();
    }
    static string Hash(string p) { using(var h=SHA256.Create()) using(var f=File.OpenRead(p)) return BitConverter.ToString(h.ComputeHash(f)).Replace("-",""); }
    static void CopyTree(string src,string dst) {
        if(!Directory.Exists(src)) return;
        foreach(string p in Directory.GetFiles(src,"*",SearchOption.AllDirectories)) {
            string rel=p.Substring(src.Length+1);
            if(rel.StartsWith("cache\\",StringComparison.OrdinalIgnoreCase)) continue;
            string t=Path.Combine(dst,rel); Directory.CreateDirectory(Path.GetDirectoryName(t)); File.Copy(p,t,true);
        }
    }
    static void Link(string path,string target) {
        if(Directory.Exists(path)) {
            if((File.GetAttributes(path)&FileAttributes.ReparsePoint)==0) throw new IOException("Expected a junction: "+path);
            Directory.Delete(path);
        }
        var pi=new ProcessStartInfo(Environment.GetEnvironmentVariable("ComSpec"),"/d /c mklink /J "+Quote(path)+" "+Quote(target));
        pi.UseShellExecute=false; pi.CreateNoWindow=true; pi.RedirectStandardOutput=true; pi.RedirectStandardError=true;
        using(var p=Process.Start(pi)) { string output=p.StandardOutput.ReadToEnd()+p.StandardError.ReadToEnd(); p.WaitForExit(); if(p.ExitCode!=0) throw new IOException(output); }
    }
    static string Prepare(string root,string mode) {
        string profile=Environment.GetEnvironmentVariable("MPV_NEON_PROFILE_ROOT");
        if(String.IsNullOrEmpty(profile)) profile=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"mpv Neon","Profiles",mode.Trim());
        profile=Path.GetFullPath(profile);
        string dst=Path.Combine(profile,"portable_config"), src=Path.Combine(root,"portable_config");
        Directory.CreateDirectory(dst);
        string marker=Path.Combine(profile,"defaults.sha256"), stamp=Path.Combine(root,"build-id.txt");
        string build=File.ReadAllText(stamp).Trim();
        string applied=Path.Combine(profile,"build-id.txt");
        if(!File.Exists(applied)||File.ReadAllText(applied).Trim()!=build) {
            bool first=!File.Exists(marker);
            if(first) CopyTree(src,dst); // Includes old installation's personal state, never its cache.
            var old=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            string previous=first ? Path.Combine(root,"legacy-defaults.sha256") : marker;
            if(File.Exists(previous)) foreach(string line in File.ReadAllLines(previous)) { int tab=line.IndexOf('\t'); if(tab>0) old[line.Substring(tab+1)]=line.Substring(0,tab); }
            string backup=Path.Combine(profile,"config-backups",DateTime.Now.ToString("yyyyMMdd-HHmmss-fff"));
            var manifest=new List<string>();
            foreach(string line in File.ReadAllLines(Path.Combine(root,"defaults.sha256"))) {
                int tab=line.IndexOf('\t'); if(tab<1) continue;
                string rel=line.Substring(tab+1), hash=line.Substring(0,tab), t=Path.Combine(dst,rel), s=Path.Combine(root,"defaults",rel);
                manifest.Add(line);
                if(File.Exists(t)&&Hash(t)==hash) continue;
                bool config=rel.EndsWith(".conf",StringComparison.OrdinalIgnoreCase)||rel.StartsWith("script-opts\\",StringComparison.OrdinalIgnoreCase)&&rel.EndsWith(".json",StringComparison.OrdinalIgnoreCase);
                string prev;
                if(config&&File.Exists(t)&&(!old.TryGetValue(rel,out prev)||Hash(t)!=prev)) {
                    string candidate=Path.Combine(profile,"new-defaults",rel); Directory.CreateDirectory(Path.GetDirectoryName(candidate)); File.Copy(s,candidate,true); continue;
                }
                if(File.Exists(t)) { string b=Path.Combine(backup,rel); Directory.CreateDirectory(Path.GetDirectoryName(b)); File.Copy(t,b,true); }
                Directory.CreateDirectory(Path.GetDirectoryName(t)); File.Copy(s,t,true);
            }
            File.WriteAllLines(marker,manifest.ToArray()); File.WriteAllText(applied,build);
        }
        string origin=Path.Combine(profile,"app-root.txt");
        bool same=File.Exists(origin)&&String.Equals(File.ReadAllText(origin),root,StringComparison.OrdinalIgnoreCase);
        foreach(string name in new[]{"assets","native","runtime"}) if(!same||!Directory.Exists(Path.Combine(profile,name))) Link(Path.Combine(profile,name),Path.Combine(root,name));
        File.WriteAllText(origin,root);
        return dst;
    }
    static void UpdatePortable(string root) {
        string marker=Path.Combine(root,"portable-defaults.sha256");
        string previous=File.Exists(marker)?marker:Path.Combine(root,"legacy-defaults.sha256");
        var old=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        if(File.Exists(previous)) foreach(string line in File.ReadAllLines(previous)) {int tab=line.IndexOf('\t'); if(tab>0)old[line.Substring(tab+1)]=line.Substring(0,tab);}
        foreach(string line in File.ReadAllLines(Path.Combine(root,"defaults.sha256"))) {
            int tab=line.IndexOf('\t');if(tab<1)continue;string rel=line.Substring(tab+1);
            if(!rel.EndsWith(".conf",StringComparison.OrdinalIgnoreCase)&&!(rel.StartsWith("script-opts\\",StringComparison.OrdinalIgnoreCase)&&rel.EndsWith(".json",StringComparison.OrdinalIgnoreCase)))continue;
            string t=Path.Combine(root,"portable_config",rel),s=Path.Combine(root,"defaults",rel),prev;
            if(File.Exists(t)&&Hash(t)==line.Substring(0,tab))continue;
            if(File.Exists(t)&&(!old.TryGetValue(rel,out prev)||Hash(t)!=prev)) {
                string n=Path.Combine(root,"new-defaults",rel);Directory.CreateDirectory(Path.GetDirectoryName(n));File.Copy(s,n,true);continue;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(t));File.Copy(s,t,true);
        }
        File.Copy(Path.Combine(root,"defaults.sha256"),marker,true);
    }
    [STAThread] static int Main(string[] args) {
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            if(Array.IndexOf(args,"--neon-update-portable")>=0) {UpdatePortable(root);return 0;}
            string config=null, modeFile=Path.Combine(root,"installation-mode.txt");
            using(var mutex=new Mutex(false,"Local\\mpvNeonProfile-"+Hash(System.Reflection.Assembly.GetExecutingAssembly().Location).Substring(0,16))) {
                bool locked=false;
                try { try {locked=mutex.WaitOne(60000);} catch(AbandonedMutexException){locked=true;} if(!locked) throw new IOException("Profile is busy");
                    if(File.Exists(modeFile)) config=Prepare(root,File.ReadAllText(modeFile));
                } finally {if(locked) mutex.ReleaseMutex();}
            }
            if(Array.IndexOf(args,"--neon-prepare-only")>=0) return 0;
            var command=new StringBuilder(); if(config!=null) command.Append(Quote("--config-dir="+config)).Append(' ');
            foreach(string arg in args) command.Append(Quote(arg)).Append(' ');
            var start=new ProcessStartInfo(Path.Combine(root,"mpv.exe"),command.ToString());
            start.UseShellExecute=false; Process.Start(start); return 0;
        } catch(Exception ex) {
            if(Array.IndexOf(args,"--neon-prepare-only")>=0||Array.IndexOf(args,"--neon-update-portable")>=0) File.WriteAllText(Path.Combine(Path.GetTempPath(),"mpv-neon-launcher-error.txt"),ex.ToString());
            else MessageBox.Show("Не удалось запустить mpv Neon.\n"+ex.Message,"mpv Neon",MessageBoxButtons.OK,MessageBoxIcon.Error);
            return 1;
        }
    }
}
