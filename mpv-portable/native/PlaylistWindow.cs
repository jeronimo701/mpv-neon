// .NET Framework 4, Windows Forms; no downloaded runtime or network access.
using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Collections;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using System.Windows.Forms;

class PlaylistWindow : Form {
    readonly string statePath, commandPath, closedPath;
    readonly JavaScriptSerializer json = new JavaScriptSerializer();
    readonly Queue<Dictionary<string,object>> pending = new Queue<Dictionary<string,object>>();
    readonly ListView list = new ListView();
    readonly Label status = new Label();
    readonly Button pause = new Button();
    readonly Timer timer = new Timer();
    bool automaticClose;
    string previous = "";
    public PlaylistWindow(string state, string command, string closed) {
        statePath=state;commandPath=command;closedPath=closed;
        Text="mpv Neon — Плейлист"; Size=new Size(500,590); MinimumSize=new Size(410,360);
        StartPosition=FormStartPosition.CenterScreen;
        BackColor=Color.FromArgb(20,28,44); ForeColor=Color.White;
        Font=new Font("Segoe UI",10); AutoScaleMode=AutoScaleMode.Dpi;
        var top=new FlowLayoutPanel { Dock=DockStyle.Top,Height=49,Padding=new Padding(8) };
        AddButton(top,"+ Файлы",delegate { AddFiles(); });
        AddButton(top,"Назад",delegate { Send("prev"); });
        pause.Text="Пауза"; Style(pause);pause.Click+=delegate { Send("pause"); };top.Controls.Add(pause);
        AddButton(top,"Далее",delegate { Send("next"); }); Controls.Add(top);
        status.Dock=DockStyle.Bottom;status.Height=46;status.Padding=new Padding(12,6,8,4);
        status.ForeColor=Color.FromArgb(180,201,220); Controls.Add(status);
        var bottom=new FlowLayoutPanel { Dock=DockStyle.Bottom,Height=47,Padding=new Padding(8) };
        AddButton(bottom,"Играть",delegate { Selected("play",0); });
        AddButton(bottom,"↑",delegate { Selected("move",-1); });
        AddButton(bottom,"↓",delegate { Selected("move",1); });
        AddButton(bottom,"Убрать",delegate { Selected("remove",0); }); Controls.Add(bottom);
        list.Dock=DockStyle.Fill;list.View=View.Details;list.FullRowSelect=true;list.HideSelection=false;
        list.MultiSelect=false;list.BorderStyle=BorderStyle.None;
        list.BackColor=Color.FromArgb(27,38,56);list.ForeColor=Color.FromArgb(241,247,255);
        list.Columns.Add("",35);list.Columns.Add("Видео / аудио",360);
        list.DoubleClick+=delegate { Selected("play",0); };
        list.KeyDown+=delegate(object sender,KeyEventArgs e) {
            if(e.KeyCode==Keys.Enter) { Selected("play",0);e.Handled=true; }
            if(e.KeyCode==Keys.Delete) { Selected("remove",0);e.Handled=true; }
        };
        list.AllowDrop=true;
        list.DragEnter+=delegate(object s,DragEventArgs e) { if(e.Data.GetDataPresent(DataFormats.FileDrop)) e.Effect=DragDropEffects.Copy; };
        list.DragDrop+=delegate(object s,DragEventArgs e) { Enqueue(new Dictionary<string,object>{{"action","add"},{"paths",(string[])e.Data.GetData(DataFormats.FileDrop)}}); };
        Controls.Add(list);list.BringToFront();
        list.Resize+=delegate { list.Columns[1].Width=Math.Max(150,list.ClientSize.Width-42); };
        FormClosing+=delegate {
            timer.Stop();
            if(!automaticClose) try { File.WriteAllText(closedPath,"closed"); } catch {}
        };
        FormClosed+=delegate { try { File.Delete(statePath); } catch {} };
        timer.Interval=250;timer.Tick+=delegate { RefreshState();Flush(); };timer.Start();
        RefreshState();
    }
    void Style(Button b) { b.AutoSize=true;b.Height=30;b.FlatStyle=FlatStyle.Flat;b.FlatAppearance.BorderSize=0;b.BackColor=Color.FromArgb(48,67,89);b.ForeColor=Color.White;b.Margin=new Padding(3); }
    void AddButton(Control parent,string text,EventHandler handler) { var b=new Button {Text=text};Style(b);b.Click+=handler;parent.Controls.Add(b); }
    void AddFiles() {
        using(var d=new OpenFileDialog { Multiselect=true,Title="Добавить в плейлист",Filter="Медиа и плейлисты|*.mp4;*.mkv;*.avi;*.mov;*.webm;*.mp3;*.flac;*.wav;*.m3u;*.m3u8;*.pls|Все файлы|*.*" }) {
            if(d.ShowDialog(this)==DialogResult.OK) Enqueue(new Dictionary<string,object>{{"action","add"},{"paths",d.FileNames}});
        }
    }
    void Send(string action) { Enqueue(new Dictionary<string,object>{{"action",action}}); }
    void Selected(string action,int delta) {
        if(list.SelectedItems.Count==0)return;
        Enqueue(new Dictionary<string,object>{{"action",action},{"id",list.SelectedItems[0].Tag},{"delta",delta}});
    }
    void Enqueue(Dictionary<string,object> command) { pending.Enqueue(command);Flush(); }
    void Flush() {
        if(pending.Count==0 || File.Exists(commandPath))return;
        try { File.WriteAllText(commandPath+".tmp",json.Serialize(pending.Peek()),new UTF8Encoding(false));File.Move(commandPath+".tmp",commandPath);pending.Dequeue(); } catch {}
    }
    void RefreshState() {
        try {
            if(!File.Exists(statePath) || DateTime.UtcNow-File.GetLastWriteTimeUtc(statePath)>TimeSpan.FromSeconds(8)) { automaticClose=true;Close();return; }
            string raw;
            using(var fs=new FileStream(statePath,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))
            using(var reader=new StreamReader(fs))raw=reader.ReadToEnd();
            var state=json.Deserialize<Dictionary<string,object>>(raw);
            if(!(bool)state["enabled"]) { automaticClose=true;Close();return; }
            pause.Text=(bool)state["pause"]?"Продолжить":"Пауза";
            if(raw==previous)return;previous=raw;
            object selected=list.SelectedItems.Count>0?list.SelectedItems[0].Tag:null;
            var items=(ArrayList)state["playlist"];
            int pos=Convert.ToInt32(state["position"]);
            list.BeginUpdate();list.Items.Clear();int i=0;
            foreach(Dictionary<string,object> item in items) {
                string path=Convert.ToString(item["filename"]);
                string title=item.ContainsKey("title")?Convert.ToString(item["title"]):"";
                if(String.IsNullOrEmpty(title))title=path.Contains("://")?path:Path.GetFileName(path);
                var row=new ListViewItem(i==pos?"▶":(i+1).ToString());row.SubItems.Add(title);row.Tag=item["id"];row.ToolTipText=path;
                if(i==pos) { row.ForeColor=Color.FromArgb(124,231,255);row.BackColor=Color.FromArgb(39,59,79); }
                list.Items.Add(row);if(selected!=null && Convert.ToString(selected)==Convert.ToString(row.Tag))row.Selected=true;
                i++;
            }
            list.EndUpdate();list.ShowItemToolTips=true;
            status.Text=items.Count==0?"Плейлист пуст. Добавьте файлы или перетащите их сюда.":items.Count+" файлов · Двойной клик — воспроизвести\n«Убрать» меняет только список, файлы остаются на диске.";
        } catch(IOException) {} catch(ArgumentException) {} catch(InvalidOperationException) {}
    }
    [STAThread] static void Main(string[] args) {
        if(args.Length!=3)return;
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new PlaylistWindow(args[0],args[1],args[2]));
    }
}
