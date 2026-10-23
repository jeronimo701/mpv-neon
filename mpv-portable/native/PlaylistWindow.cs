// .NET Framework 4, Windows Forms; no downloaded runtime or network access.
using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Collections;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Runtime.InteropServices;

class PlaylistWindow : Form {
    readonly string statePath, commandPath, closedPath;
    readonly JavaScriptSerializer json = new JavaScriptSerializer();
    readonly Queue<Dictionary<string,object>> pending = new Queue<Dictionary<string,object>>();
    readonly ListView list = new ListView();
    readonly Label status = new Label();
    readonly Button pause = new Button();
    readonly Timer timer = new Timer();
    readonly FlowLayoutPanel tabs = new FlowLayoutPanel();
    Color surface=Color.FromArgb(20,28,44), ink=Color.White, accent=Color.FromArgb(83,173,255), accentInk=Color.FromArgb(6,16,28);
    string themeKey="", libraryKey="", activeLibrary="", activeName="";
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd,int attribute,ref int value,int size);
    bool automaticClose;
    string previous = "";
    public PlaylistWindow(string state, string command, string closed) {
        statePath=state;commandPath=command;closedPath=closed;
        Text="mpv Neon — Плейлисты"; Size=new Size(580,640); MinimumSize=new Size(530,400);
        StartPosition=FormStartPosition.CenterScreen;
        BackColor=Color.FromArgb(20,28,44); ForeColor=Color.White;
        Font=new Font("Segoe UI",10); AutoScaleMode=AutoScaleMode.Dpi;
        var top=new FlowLayoutPanel { Dock=DockStyle.Top,Height=49,Padding=new Padding(8) };
        AddButton(top,"+ Файлы",delegate { AddFiles(); });
        AddButton(top,"Назад",delegate { Send("prev"); });
        pause.Text="Пауза"; Style(pause);pause.Click+=delegate { Send("pause"); };top.Controls.Add(pause);
        AddButton(top,"Далее",delegate { Send("next"); }); Controls.Add(top);
        tabs.Dock=DockStyle.Top;tabs.Height=44;tabs.Padding=new Padding(6);tabs.WrapContents=false;tabs.AutoScroll=true;
        Controls.Add(tabs);
        status.Dock=DockStyle.Bottom;status.Height=46;status.Padding=new Padding(12,6,8,4);
        status.ForeColor=Color.FromArgb(180,201,220); Controls.Add(status);
        var bottom=new FlowLayoutPanel { Dock=DockStyle.Bottom,Height=47,Padding=new Padding(8) };
        AddButton(bottom,"Играть",delegate { Selected("play",0); });
        AddButton(bottom,"↑",delegate { Selected("move",-1); });
        AddButton(bottom,"↓",delegate { Selected("move",1); });
        AddButton(bottom,"Убрать",delegate { Selected("remove",0); }); Controls.Add(bottom);
        AddButton(bottom,"Имя…",delegate { var name=Prompt("Переименовать список",activeName);if(name!=null)Enqueue(new Dictionary<string,object>{{"action","library-rename"},{"name",name}}); });
        AddButton(bottom,"Удалить список",delegate {
            if(MessageBox.Show(this,"Удалить только список «"+activeName+"»? Файлы на диске останутся.","Плейлисты",MessageBoxButtons.YesNo,MessageBoxIcon.Question)==DialogResult.Yes)
                Enqueue(new Dictionary<string,object>{{"action","library-delete"},{"library_id",activeLibrary}});
        });
        list.Dock=DockStyle.Fill;list.View=View.Details;list.FullRowSelect=true;list.HideSelection=false;
        list.MultiSelect=false;list.BorderStyle=BorderStyle.None;
        list.BackColor=Color.FromArgb(27,38,56);list.ForeColor=Color.FromArgb(241,247,255);
        list.Columns.Add("",35);list.Columns.Add("Видео / аудио",360);
        list.OwnerDraw=true;
        list.DrawColumnHeader+=delegate(object s,DrawListViewColumnHeaderEventArgs e) {
            using(var brush=new SolidBrush(surface))e.Graphics.FillRectangle(brush,e.Bounds);
            TextRenderer.DrawText(e.Graphics,e.Header.Text,Font,e.Bounds,ink,TextFormatFlags.Left|TextFormatFlags.VerticalCenter);
        };
        list.DrawItem+=delegate(object s,DrawListViewItemEventArgs e) {};
        list.DrawSubItem+=delegate(object s,DrawListViewSubItemEventArgs e) {
            Color bg=e.Item.Selected?accent:e.Item.BackColor;
            Color fg=e.Item.Selected?accentInk:e.Item.ForeColor;
            using(var brush=new SolidBrush(bg))e.Graphics.FillRectangle(brush,e.Bounds);
            TextRenderer.DrawText(e.Graphics,e.SubItem.Text,Font,e.Bounds,fg,TextFormatFlags.Left|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
        };
        list.DoubleClick+=delegate { Selected("play",0); };
        list.KeyDown+=delegate(object sender,KeyEventArgs e) {
            if(e.KeyCode==Keys.Enter) { Selected("play",0);e.Handled=true; }
            if(e.KeyCode==Keys.Delete) { Selected("remove",0);e.Handled=true; }
        };
        list.AllowDrop=true;
        list.DragEnter+=delegate(object s,DragEventArgs e) { if(e.Data.GetDataPresent(DataFormats.FileDrop)) e.Effect=DragDropEffects.Copy; };
        list.DragDrop+=delegate(object s,DragEventArgs e) { Enqueue(new Dictionary<string,object>{{"action","add"},{"paths",(string[])e.Data.GetData(DataFormats.FileDrop)}}); };
        Controls.Add(list);list.BringToFront();
        list.Resize+=delegate { list.Columns[1].Width=Math.Max(150,list.ClientSize.Width-35); };
        Shown+=delegate { list.Columns[1].Width=Math.Max(150,list.ClientSize.Width-35); };
        FormClosing+=delegate {
            timer.Stop();
            if(!automaticClose) try { File.WriteAllText(closedPath,"closed"); } catch {}
        };
        FormClosed+=delegate { try { File.Delete(statePath); } catch {} };
        timer.Interval=250;timer.Tick+=delegate { RefreshState();Flush(); };timer.Start();
        RefreshState();
    }
    void Style(Button b) { b.AutoSize=true;b.Height=30;b.FlatStyle=FlatStyle.Flat;b.FlatAppearance.BorderSize=0;b.BackColor=ControlPaint.Light(surface,.25f);b.ForeColor=ink;b.Margin=new Padding(3); }
    string Prompt(string title,string initial) {
        using(var dialog=new Form {Text=title,Width=420,Height=160,StartPosition=FormStartPosition.CenterParent,BackColor=surface,ForeColor=ink,Font=Font,FormBorderStyle=FormBorderStyle.FixedDialog,MinimizeBox=false,MaximizeBox=false}) {
            var edit=new TextBox {Left=16,Top=16,Width=370,Text=initial,BackColor=surface,ForeColor=ink,MaxLength=120};
            var ok=new Button {Text="Сохранить",Left=270,Top=60,DialogResult=DialogResult.OK};Style(ok);
            dialog.Controls.Add(edit);dialog.Controls.Add(ok);dialog.AcceptButton=ok;
            return dialog.ShowDialog(this)==DialogResult.OK && !String.IsNullOrWhiteSpace(edit.Text)?edit.Text.Trim():null;
        }
    }
    void ApplyColors(Control root) {
        root.BackColor=surface;root.ForeColor=ink;
        foreach(Control child in root.Controls) { ApplyColors(child);var button=child as Button;if(button!=null)Style(button); }
    }
    void UpdateTheme(Dictionary<string,object> state) {
        if(!state.ContainsKey("theme"))return;
        var theme=state["theme"] as Dictionary<string,object>;
        if(theme==null || !theme.ContainsKey("background"))return;
        string key=json.Serialize(theme);if(key==themeKey)return;themeKey=key;libraryKey="";
        surface=ColorTranslator.FromHtml("#"+Convert.ToString(theme["background"]));ink=ColorTranslator.FromHtml("#"+Convert.ToString(theme["foreground"]));
        accent=ColorTranslator.FromHtml("#"+Convert.ToString(theme["accent"]));accentInk=ColorTranslator.FromHtml("#"+Convert.ToString(theme["accent_text"]));
        float fontSize=theme.ContainsKey("size") && Convert.ToString(theme["size"])=="large"?12f:10.5f;
        Font=new Font("Segoe UI",fontSize);ApplyColors(this);list.BackColor=surface;list.ForeColor=ink;
        try {int dark=1;DwmSetWindowAttribute(Handle,20,ref dark,4);int color=surface.R|(surface.G<<8)|(surface.B<<16);DwmSetWindowAttribute(Handle,35,ref color,4);}catch{}
        Invalidate(true);
    }
    void UpdateLibrary(Dictionary<string,object> state) {
        if(!state.ContainsKey("library"))return;
        var library=state["library"] as Dictionary<string,object>;
        if(library==null || !library.ContainsKey("lists"))return;
        string key=json.Serialize(library);if(key==libraryKey)return;libraryKey=key;
        activeLibrary=Convert.ToString(library["active"]);tabs.Controls.Clear();
        foreach(Dictionary<string,object> entry in (ArrayList)library["lists"]) {
            string id=Convert.ToString(entry["id"]), name=Convert.ToString(entry["name"]);
            var tab=new Button {Text=name+" ("+Convert.ToString(entry["count"])+")"};Style(tab);
            if(id==activeLibrary) {tab.BackColor=accent;tab.ForeColor=accentInk;activeName=name;Text="mpv Neon — "+name;}
            tab.Click+=delegate {Enqueue(new Dictionary<string,object>{{"action","library-select"},{"library_id",id}});};tabs.Controls.Add(tab);
        }
        AddButton(tabs,"+",delegate {var name=Prompt("Новый плейлист","");if(name!=null)Enqueue(new Dictionary<string,object>{{"action","library-new"},{"name",name}});});
    }
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
            UpdateTheme(state);UpdateLibrary(state);
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
                row.ForeColor=i==pos?accent:ink;row.BackColor=surface;
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
