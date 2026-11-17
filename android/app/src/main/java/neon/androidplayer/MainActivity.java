package neon.androidplayer;

import android.app.UiModeManager;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.Presentation;
import android.content.*;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.hardware.display.DisplayManager;
import android.media.MediaDataSource;
import android.media.MediaPlayer;
import android.net.*;
import android.os.*;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import java.net.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

public final class MainActivity extends Activity {
    private final ExecutorService io = Executors.newFixedThreadPool(2);
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Deque<Runnable> history = new ArrayDeque<>();
    private Library library;
    private Library.Ref playingRef;
    private List<Library.Item> queue=Collections.emptyList();
    private int queueIndex, lastSavedSecond=-1, extraPanel;
    private boolean repeatItem, resumeEnabled, resumePending;
    private TextView[] captions=new TextView[0];
    private FrameLayout captionHost;
    private View.OnLayoutChangeListener captionLayout;
    private String caption="";
    private int subtitleTrack=-1, subtitlePickerRevision;
    private List<SubRip.Cue> externalSubtitles=Collections.emptyList();
    private SubRip.Cue embeddedSubtitle;
    private LinearLayout body;
    private int revision;
    private volatile boolean destroyed;
    private int mode;
    private boolean tv;
    private MediaPlayer player;
    private boolean prepared;
    private boolean wantPlay;
    private SurfaceView video;
    private int videoWidth, videoHeight;
    private record Controls(TextView status, SeekBar seek, Button toggle) {}
    private final List<Controls> playControls = new ArrayList<>();
    private record EdgeControls(TextView label, SeekBar slider) {}
    private final List<EdgeControls> edgeControls = new ArrayList<>();
    private static final String[] VIDEO_MODES = {"2D", "2D → SBS", "SBS Half", "SBS Full"};
    private static final String[] EDGE_MODES = {"Выключены", "Виньетка", "Мягкие края + перспектива"};
    private static final String[] INTERFACES = {"Авто", "Android TV", "Телефон / планшет"};
    private static final String[] THEMES = {"YouTube", "Neon"};
    private static final String[] INITIAL_SBS = {"2D", "2D → SBS", "SBS Half", "SBS Full", "Авто: SBS на 3840 × 1080"};
    private static final String[] HIDE_LABELS = {"3 секунды", "5 секунд", "8 секунд", "Только вручную"};
    private static final int[] HIDE_MS = {3000,5000,8000,0};
    private static final String[] SPEED_LABELS = {"0,75×", "1×", "1,25×", "1,5×", "2×"};
    private static final float[] SPEEDS = {.75f,1f,1.25f,1.5f,2f};
    private static final String[] FIT_MODES = {"Вписать","По ширине","По высоте","Заполнить с обрезкой","Растянуть"};
    private FrameLayout playFrame;
    private FrameLayout playbackRoot;
    private FrameLayout playbackScreen;
    private View tapArea;
    private View phoneBlack;
    private int beforeBlackBars;
    private LinearLayout playbackBars;
    private StereoView stereo;
    private Presentation glasses;
    private Surface activeSurface;
    private DisplayManager displays;
    private int outputGeneration, stereoMode, edgeEffect, edgeStrength, selectedDisplayId = -1;
    private int lastHintId=-1;
    private boolean lastWideHint;
    private boolean showStereoSettings, visible, mirroredBars, useExternal;
    private boolean controlsVisible, stereoOverridden;
    private int homeTheme, hideIndex, startStereo, defaultSpeed, playbackSpeed, wakeKey;
    private int defaultFit, playbackFit;
    private int beforePlayerBars;
    private String playingTitle, currentStatus;
    private int beforeStereoOrientation = Integer.MIN_VALUE;
    private static final int IMMERSIVE = View.SYSTEM_UI_FLAG_FULLSCREEN
        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY;
    private boolean dragging;
    private int bg, accent;
    private final int textColor = 0xfff5f5f5;

    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        library=new Library(getPreferences(0));
        resumeEnabled=getPreferences(0).getBoolean("rememberPosition",true);
        setThemePalette(prefIndex("theme",0,THEMES.length));
        mode = getPreferences(0).getInt("interface", 0);
        edgeEffect = getPreferences(0).getInt("stereoEdges", StereoView.CLEAN);
        edgeStrength = getPreferences(0).getInt("stereoStrength", 45);
        useExternal = getPreferences(0).getBoolean("stereoExternal", true);
        hideIndex = prefIndex("hideControls",0,HIDE_MS.length);
        startStereo = prefIndex("startStereo",0,INITIAL_SBS.length);
        defaultSpeed = prefIndex("defaultSpeed",1,SPEEDS.length);
        defaultFit = prefIndex("fitMode",0,FIT_MODES.length);
        displays = (DisplayManager)getSystemService(DISPLAY_SERVICE);
        displays.registerDisplayListener(displayListener, ui);
        setMode(mode);
        home();
    }
    private int prefIndex(String key, int defaultValue, int max) {
        int value=getPreferences(0).getInt(key,defaultValue);
        return value>=0 && value<max ? value : defaultValue;
    }
    private void save(String key,int value) { getPreferences(0).edit().putInt(key,value).apply(); }
    private void setThemePalette(int theme) {
        homeTheme=theme;
        bg=theme==0 ? 0xff0f0f0f : 0xff101522;
        accent=theme==0 ? 0xffff0033 : 0xff61cdff;
        getWindow().setStatusBarColor(bg);
        getWindow().setNavigationBarColor(bg);
        save("theme",theme);
    }
    private void setMode(int option) {
        mode = option;
        tv = mode == 1 || (mode == 0 && ((UiModeManager)getSystemService(UI_MODE_SERVICE))
            .getCurrentModeType() == Configuration.UI_MODE_TYPE_TELEVISION);
        getPreferences(0).edit().putInt("interface", mode).apply();
    }
    private int dp(float n) { return Math.round(n * getResources().getDisplayMetrics().density); }
    private LinearLayout column() {
        LinearLayout c = new LinearLayout(this); c.setOrientation(LinearLayout.VERTICAL); return c;
    }
    private TextView text(String value, int size) {
        TextView t = new TextView(this); t.setText(value); t.setTextSize(size); t.setTextColor(textColor);
        t.setPadding(0, dp(7), 0, dp(7)); return t;
    }
    private GradientDrawable shape(int fill, boolean focused) {
        GradientDrawable d = new GradientDrawable(); d.setColor(fill); d.setCornerRadius(dp(9));
        if (focused) d.setStroke(dp(3), homeTheme==0 ? Color.WHITE : accent);
        return d;
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setText(label); b.setTextColor(textColor); b.setAllCaps(false);
        b.setTextSize(tv ? 20 : 16); b.setFocusable(true); b.setMinHeight(dp(tv ? 60 : 48));
        StateListDrawable style = new StateListDrawable();
        style.addState(new int[]{android.R.attr.state_focused}, shape(homeTheme==0 ? 0xff3d3d3d : 0xff18456a, true));
        style.addState(new int[]{android.R.attr.state_pressed}, shape(homeTheme==0 ? 0xff3d3d3d : 0xff20577d, false));
        style.addState(new int[0], shape(homeTheme==0 ? 0xff232323 : 0xff222e45, false));
        b.setBackground(style); b.setPadding(dp(14), dp(8), dp(14), dp(8));
        b.setOnClickListener(v -> action.run());
        return b;
    }
    private void add(String label, Runnable action) {
        Button b = button(label, action);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.topMargin = dp(7); body.addView(b, lp);
        if (tv && (getCurrentFocus() == null || getCurrentFocus() instanceof ScrollView)) b.requestFocus();
    }
    private void page(String title, String description) {
        revision++;
        releasePlayer();
        ScrollView sc = new ScrollView(this); sc.setFillViewport(true); sc.setBackgroundColor(bg);
        body = column(); body.setPadding(dp(tv ? 38 : 18), dp(tv ? 26 : 12), dp(tv ? 38 : 18), dp(22));
        body.setDescendantFocusability(ViewGroup.FOCUS_AFTER_DESCENDANTS);
        sc.addView(body, new ScrollView.LayoutParams(-1, -2)); setContentView(sc);
        TextView name = text(title, tv ? 32 : 27); name.setTypeface(null,android.graphics.Typeface.BOLD);
        body.addView(name);
        View rule=new View(this); rule.setBackgroundColor(accent);
        body.addView(rule,new LinearLayout.LayoutParams(dp(tv ? 60 : 42),dp(3)));
        if (!description.isEmpty()) body.addView(text(description, tv ? 19 : 15));
    }
    private void home() {
        history.clear();
        page("Neon Player", tv ? "Режим Android TV · пульт и кнопки направления" : "Режим телефона и планшета · сенсорное управление");
        Library.Recent recent=resumeEnabled?library.recent():null;
        if (recent!=null) add("Продолжить: "+recent.ref().title()+" · "+time(recent.position()),
            () -> openSaved(Collections.singletonList(recent.ref()),0,this::home));
        add("Найти в локальной сети", () -> go(this::home, this::discover));
        add("Добавить SMB", () -> form(false, ""));
        add("Подключить TorrServer", () -> form(true, ""));
        add("Открыть файл на устройстве", () -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("video/*").addCategory(Intent.CATEGORY_OPENABLE);
            try { startActivityForResult(intent, 10); }
            catch (ActivityNotFoundException e) { toast("На устройстве нет приложения для выбора файлов."); }
        });
        add("Мои плейлисты",() -> go(this::home,this::playlistLibrary));
        add("Настройки", () -> go(this::home,this::settings));
    }
    private void choose(String title,String[] options,int selected,java.util.function.IntConsumer apply) {
        new AlertDialog.Builder(this).setTitle(title).setSingleChoiceItems(options,selected,(dialog,n)->{
            dialog.dismiss(); apply.accept(n);
        }).setNegativeButton("Отмена",null).show();
    }
    private void settings() {
        page("Настройки","Интерфейс, воспроизведение и вывод в очки");
        add("Интерфейс: "+INTERFACES[mode], () -> choose("Интерфейс и управление",INTERFACES,mode,n -> {setMode(n);settings();}));
        add("Тема: "+THEMES[homeTheme], () -> choose("Тема оформления",THEMES,homeTheme,n -> {setThemePalette(n);settings();}));
        add("Скрывать панель: "+HIDE_LABELS[hideIndex], () -> choose("Скрывать панель при просмотре",HIDE_LABELS,hideIndex,n -> {
            hideIndex=n; save("hideControls",n); settings();
        }));
        add("Скорость по умолчанию: "+SPEED_LABELS[defaultSpeed], () -> choose("Скорость воспроизведения",SPEED_LABELS,defaultSpeed,n -> {
            defaultSpeed=n; save("defaultSpeed",n); settings();
        }));
        add("Размер кадра: "+FIT_MODES[defaultFit],() -> choose("Размер кадра",FIT_MODES,defaultFit,n -> {
            defaultFit=n;save("fitMode",n);settings();
        }));
        add("Запоминать позицию: "+(resumeEnabled?"да":"нет"),() -> {
            resumeEnabled=!resumeEnabled;
            getPreferences(0).edit().putBoolean("rememberPosition",resumeEnabled).apply(); settings();
        });
        add("Очистить позиции просмотра",() -> new AlertDialog.Builder(this)
            .setMessage("Удалить сохранённые позиции просмотра? Плейлисты останутся.")
            .setNegativeButton("Отмена",null).setPositiveButton("Очистить",(d,n) -> {library.clearHistory();settings();}).show());
        add("SBS и очки", () -> go(this::settings,this::stereoSettings));
        add("‹ Назад",this::onBackPressed);
    }
    private void stereoSettings() {
        page("SBS и очки","Настройки применяются при следующем открытии видео. Меню ⚙ в плеере меняет режим на лету.");
        add("Режим при запуске: "+INITIAL_SBS[startStereo], () -> choose("Режим при запуске",INITIAL_SBS,startStereo,n -> {
            startStereo=n; save("startStereo",n); stereoSettings();
        }));
        String[] routes={"Внешний экран, если доступен","Встроенный экран / зеркало"};
        add("Вывод: "+routes[useExternal?0:1], () -> choose("Вывод SBS",routes,useExternal?0:1,n -> {
            setExternal(n==0); stereoSettings();
        }));
        add("Края: "+EDGE_MODES[edgeEffect], () -> choose("Эффект краёв",EDGE_MODES,edgeEffect,n -> {
            edgeEffect=n; save("stereoEdges",n); stereoSettings();
        }));
        TextView percent=text("Сила сглаживания: "+edgeStrength+"%",tv?19:15); body.addView(percent);
        SeekBar strength=new SeekBar(this); tintSeek(strength); strength.setMax(100); strength.setProgress(edgeStrength);
        strength.setContentDescription("Сила сглаживания"); body.addView(strength);
        strength.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onStartTrackingTouch(SeekBar b) {}
            public void onStopTrackingTouch(SeekBar b) {}
            public void onProgressChanged(SeekBar b,int p,boolean user) {
                if (!user) return;
                edgeStrength=p; save("stereoStrength",p); percent.setText("Сила сглаживания: "+p+"%");
            }
        });
        add("‹ Назад",this::onBackPressed);
    }
    private void setExternal(boolean value) {
        useExternal=value; getPreferences(0).edit().putBoolean("stereoExternal",value).apply();
    }
    private void tintSeek(SeekBar seek) {
        ColorStateList tint=ColorStateList.valueOf(accent);
        seek.setProgressTintList(tint); seek.setThumbTintList(tint);
    }
    private void go(Runnable previous, Runnable next) { history.push(previous); next.run(); }
    @Override public void onBackPressed() {
        if (phoneBlack!=null) { setPhoneBlack(false); return; }
        if (playFrame!=null && extraPanel!=0) { extraPanel=0; buildPlaybackBars(); return; }
        if (playFrame!=null && showStereoSettings) { showStereoSettings=false; buildPlaybackBars(); return; }
        if (tv && playFrame!=null && glasses==null && controlsVisible && prepared) { showControls(false); return; }
        if (!history.isEmpty()) history.pop().run(); else super.onBackPressed();
    }
    @Override protected void onActivityResult(int code, int result, Intent data) {
        super.onActivityResult(code, result, data);
        if (result!=RESULT_OK || data==null || data.getData()==null) return;
        Uri uri=data.getData();
        if (code == 10) {
            try { getContentResolver().takePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION); }
            catch (SecurityException ignored) {}
            String title="Файл на устройстве";
            try (android.database.Cursor c=getContentResolver().query(uri,
                    new String[]{android.provider.OpenableColumns.DISPLAY_NAME},null,null,null)) {
                if (c!=null && c.moveToFirst() && c.getString(0)!=null) title=c.getString(0);
            } catch (RuntimeException ignored) {}
            Library.Ref ref=new Library.Ref("local",title,uri.toString(),0,"","",false);
            go(this::home,() -> playItem(Collections.singletonList(new Library.Item(ref,null)),0));
        } else if (code==11 && subtitlePickerRevision==revision && playFrame!=null) {
            async(() -> {
                try (java.io.InputStream in=getContentResolver().openInputStream(uri)) {
                    if (in==null) throw new java.io.IOException();
                    java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();
                    byte[] buffer=new byte[8192];
                    int n;
                    while ((n=in.read(buffer))!=-1) {
                        if (out.size()+n>1024*1024) throw new java.io.IOException("SRT exceeds limit");
                        out.write(buffer,0,n);
                    }
                    return SubRip.parse(out.toByteArray());
                }
            }, cues -> {
                if (cues.isEmpty()) {toast("В файле не найдено строк SRT.");return;}
                selectSubtitle(-1);
                externalSubtitles=cues;
                extraPanel=0; showStereoSettings=false; buildPlaybackBars(); updateCaption();
            }, e -> toast("Не удалось прочитать SRT. Выберите текстовый файл размером до 1 МБ."));
        }
    }
    private void playlistLibrary() {
        page("Мои плейлисты","");
        add("Создать плейлист",() -> {
            EditText input=new EditText(this); input.setSingleLine(true); input.setHint("Название");
            new AlertDialog.Builder(this).setTitle("Новый плейлист").setView(input)
                .setNegativeButton("Отмена",null).setPositiveButton("Создать",(d,n) -> {
                    String name=input.getText().toString().trim();
                    if (!name.isEmpty() && name.length()<=60) { library.create(name); playlistLibrary(); }
                    else toast("Введите название до 60 символов.");
                }).show();
        });
        for (String name:library.names()) add(name,() -> go(this::playlistLibrary,() -> savedPlaylist(name)));
        add("‹ Назад",this::onBackPressed);
    }
    private void savedPlaylist(String name) {
        List<Library.Ref> entries=library.entries(name);
        page(name,entries.isEmpty()?"Добавляйте файлы из меню ⚙ → Плейлист во время просмотра.":"Выберите файл");
        add("‹ Назад",this::onBackPressed);
        for (int i=0;i<entries.size();i++) {
            int index=i;
            add(entries.get(i).title(),() -> openSaved(entries,index,() -> savedPlaylist(name)));
        }
        if (!entries.isEmpty()) add("Убрать файл…",() -> choose("Убрать из плейлиста",
            entries.stream().map(Library.Ref::title).toArray(String[]::new),-1,i -> {
                library.remove(name,i);savedPlaylist(name);
            }));
        add("Удалить плейлист…",() -> new AlertDialog.Builder(this).setMessage("Удалить плейлист «"+name+"»?")
            .setNegativeButton("Отмена",null).setPositiveButton("Удалить",(d,n)-> {
                library.delete(name); onBackPressed();
            }).show());
    }
    private void openSaved(List<Library.Ref> refs,int index,Runnable back) {
        Library.Ref target=refs.get(index);
        Use<Sources.Login> start=login -> {
            List<Library.Item> items=new ArrayList<>();
            for (Library.Ref ref:refs) items.add(new Library.Item(ref,sameServer(target,ref)?login:null));
            go(back,() -> playItem(items,index));
        };
        if (target.auth()) askLogin(target,start);
        else start.accept(null);
    }
    private boolean sameServer(Library.Ref a,Library.Ref b) {
        return a.auth()==b.auth() && a.kind().equals(b.kind()) && a.address().equals(b.address()) && a.port()==b.port();
    }
    private void askLogin(Library.Ref ref,Use<Sources.Login> use) {
        LinearLayout form=column(); form.setPadding(dp(18),0,dp(18),dp(8));
        EditText user=field(form,"Логин","",false),pass=field(form,"Пароль","",true);
        EditText domain=ref.kind().equals("smb")?field(form,"Домен (необязательно)","",false):null;
        AlertDialog d=new AlertDialog.Builder(this).setTitle("Вход · "+ref.address()).setView(form)
            .setNegativeButton("Отмена",null).setPositiveButton("Подключить",null).create();
        d.setOnShowListener(v -> d.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(b -> {
            String name=user.getText().toString().trim();
            if (name.isEmpty()) {user.setError("Введите логин");return;}
            d.dismiss();
            use.accept(new Sources.Login(name,pass.getText().toString(),domain==null?"":domain.getText().toString().trim()));
        }));
        d.show();
    }
    private void playItem(List<Library.Item> items,int index) {
        Library.Item item=items.get(index);
        Library.Ref ref=item.ref();
        if (ref.auth() && item.login()==null) {
            askLogin(ref,login -> {
                ArrayList<Library.Item> authenticated=new ArrayList<>(items);
                for (int i=0;i<items.size();i++) if (sameServer(ref,items.get(i).ref()))
                    authenticated.set(i,new Library.Item(items.get(i).ref(),login));
                playItem(authenticated,index);
            });
            return;
        }
        Sources.Login login=item.login()==null ? new Sources.Login("","","") : item.login();
        if (ref.kind().equals("smb")) {
            Sources.Smb source=new Sources.Smb(ref.address(),ref.port(),ref.share(),login);
            playback(items,index,null,Collections.emptyMap(),() -> source.file(ref.path()));
        } else if (ref.kind().equals("torr")) {
            Sources.Torr source=new Sources.Torr(ref.address(),login);
            playback(items,index,Uri.parse(ref.path()),source.headers(),null);
        } else playback(items,index,Uri.parse(ref.address()),Collections.emptyMap(),null);
    }
    private void toast(String message) { Toast.makeText(this, message, Toast.LENGTH_LONG).show(); }
    private EditText field(LinearLayout form, String hint, String value, boolean password) {
        EditText e = new EditText(this); e.setSingleLine(); e.setHint(hint); e.setText(value);
        e.setInputType(password ? InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD
            : InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        e.setSaveEnabled(!password); form.addView(e, new LinearLayout.LayoutParams(-1, -2)); return e;
    }
    private void form(boolean torr, String endpoint) {
        LinearLayout inputs = column(); inputs.setPadding(dp(18), 0, dp(18), dp(8));
        ScrollView scroll = new ScrollView(this); scroll.addView(inputs);
        EditText host = field(inputs, torr ? "http://сервер:8090" : "Адрес сервера или smb://сервер/папка", endpoint, false);
        EditText share = torr ? null : field(inputs,"Имя общей папки (например, Video)","",false);
        Spinner auth = new Spinner(this);
        ArrayAdapter<String> adapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item,
            new String[]{"Гость / без входа", "Логин и пароль"});
        auth.setAdapter(adapter); inputs.addView(auth);
        LinearLayout credentials = column(); inputs.addView(credentials);
        EditText user = field(credentials, "Логин", "", false);
        EditText pass = field(credentials, "Пароль", "", true);
        EditText domain = torr ? null : field(credentials, "Домен / рабочая группа (необязательно)", "", false);
        credentials.setVisibility(View.GONE);
        auth.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
            public void onItemSelected(android.widget.AdapterView<?> p, View v, int pos, long id) { credentials.setVisibility(pos == 0 ? View.GONE : View.VISIBLE); }
            public void onNothingSelected(android.widget.AdapterView<?> p) {}
        });
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle(torr ? "TorrServer" : "Общая папка SMB2/3")
            .setView(scroll).setNegativeButton("Отмена", null).setPositiveButton("Подключить", null).create();
        dialog.setOnShowListener(ignored -> dialog.getButton(-1).setOnClickListener(v -> {
            try {
                boolean guest = auth.getSelectedItemPosition() == 0;
                String login = guest ? "" : user.getText().toString().trim();
                if (!guest && login.isEmpty()) throw new IllegalArgumentException("Введите логин.");
                Sources.Login key = new Sources.Login(login, guest ? "" : pass.getText().toString(),
                    guest || torr ? "" : domain.getText().toString().trim());
                String address = host.getText().toString().trim();
                Runnable previous = pageBack();
                if (torr) {
                    if (!address.contains("://")) address = "http://" + address;
                    URI url = new URI(address);
                    if (!("http".equals(url.getScheme()) || "https".equals(url.getScheme())) || url.getHost() == null ||
                        url.getRawUserInfo() != null || url.getRawQuery() != null || url.getRawFragment() != null)
                        throw new IllegalArgumentException("Укажите адрес TorrServer, например http://192.168.1.20:8090.");
                    if (url.getPort() == -1 && url.getScheme().equals("http"))
                        url = new URI(url.getScheme(), null, url.getHost(), 8090, url.getPath(), null, null);
                    Sources.Torr source = new Sources.Torr(url.toASCIIString().replaceAll("/+$", ""), key);
                    dialog.dismiss(); go(previous, () -> torrents(source));
                } else {
                    if (address.startsWith("\\\\")) address = address.substring(2).replace('\\','/');
                    if (!address.startsWith("smb://")) address = "smb://" + address;
                    URI uri = new URI(address.replace(" ", "%20"));
                    String sub = uri.getPath() == null ? "" : uri.getPath().replaceFirst("^/+", "");
                    String[] parts = sub.split("/", 2);
                    String name = share.getText().toString().trim();
                    if (name.isEmpty()) name = parts[0];
                    if (uri.getHost() == null || uri.getUserInfo() != null || uri.getQuery() != null || uri.getFragment() != null || uri.getPort() == 0 || uri.getPort() > 65535)
                        throw new IllegalArgumentException("Проверьте адрес SMB.");
                    if (name.isEmpty() || name.contains("/") || name.contains("\\"))
                        throw new IllegalArgumentException("Введите имя общей папки. Оно указано после имени сервера.");
                    String path = parts.length == 2 ? parts[1].replace('/','\\') : "";
                    Sources.Smb source = new Sources.Smb(uri.getHost(), uri.getPort() < 0 ? 445 : uri.getPort(), name, key);
                    dialog.dismiss(); go(previous, () -> smb(source, path));
                }
            } catch (Exception e) { toast(e instanceof IllegalArgumentException ? e.getMessage() : "Проверьте адрес сервера."); }
        }));
        dialog.show();
        dialog.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE | WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
    }
    private Runnable pageBack() { return history.isEmpty() ? this::home : this::discover; }
    private void smb(Sources.Smb source, String folder) {
        String title = "SMB · " + source.share();
        page(title, (folder.isEmpty() ? source.host() : folder) + "\nЧитаю папку…");
        add("‹ Назад", this::onBackPressed);
        async(() -> source.list(folder), entries -> {
            page(title, folder.isEmpty() ? source.host() : folder);
            add("‹ Назад", this::onBackPressed);
            showEntries(entries, e -> {
                if (e.folder()) go(() -> smb(source, folder), () -> smb(source, e.path()));
                else {
                    ArrayList<Library.Item> items=new ArrayList<>(); int selected=0;
                    for (Sources.Entry entry:entries) if (!entry.folder()) {
                        if (entry.path().equals(e.path())) selected=items.size();
                        Library.Ref ref=new Library.Ref("smb",entry.label(),source.host(),source.port(),
                            source.share(),entry.path(),!source.login().guest());
                        items.add(new Library.Item(ref,source.login()));
                    }
                    int index=selected;
                    go(() -> smb(source,folder),() -> playItem(items,index));
                }
            });
        }, e -> showError(title, smbError(e), () -> smb(source, folder)));
    }
    private String smbError(Exception e) {
        if (e instanceof UnknownHostException) return "Имя сервера не найдено. Попробуйте его IP-адрес.";
        if (e instanceof com.hierynomus.mssmb2.SMBApiException) {
            var status = ((com.hierynomus.mssmb2.SMBApiException)e).getStatus();
            if (status != null) return "SMB: " + status + ". Проверьте имя папки и права на чтение.";
        }
        return "Не удалось подключиться к SMB2/3. Проверьте адрес, имя папки и доступ в локальной сети.";
    }
    private void torrents(Sources.Torr source) {
        page("TorrServer", "Загружаю список…"); add("‹ Назад", this::onBackPressed);
        async(source::torrents, array -> {
            page("TorrServer", source.base()); add("‹ Назад", this::onBackPressed);
            if (array.length() == 0) body.addView(text("На сервере пока нет торрентов.", 17));
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.optJSONObject(i);
                if (item == null || item.optString("hash").isEmpty()) continue;
                String name = item.optString("title", item.optString("hash"));
                add(name, () -> go(() -> torrents(source), () -> torrentFiles(source, item, name)));
            }
        }, e -> showError("TorrServer", torrError(e), () -> torrents(source)));
    }
    private void torrentFiles(Sources.Torr source, JSONObject item, String name) {
        String hash = item.optString("hash");
        page(name, "Загружаю список файлов…"); add("‹ Назад", this::onBackPressed);
        async(() -> source.files(hash, item), files -> {
            page(name, "Файлы для воспроизведения"); add("‹ Назад", this::onBackPressed);
            showEntries(files, f -> {
                ArrayList<Library.Item> items=new ArrayList<>(); int selected=0;
                for (Sources.Entry entry:files) {
                    if (entry.index()==f.index()) selected=items.size();
                    Library.Ref ref=new Library.Ref("torr",entry.label(),source.base(),0,"",
                        source.stream(hash,entry),!source.login().guest());
                    items.add(new Library.Item(ref,source.login()));
                }
                int index=selected;
                go(() -> torrentFiles(source,item,name),() -> playItem(items,index));
            });
        }, e -> showError(name, torrError(e), () -> torrentFiles(source, item, name)));
    }
    private String torrError(Exception e) {
        return e.getMessage() != null && e.getMessage().startsWith("TorrServer")
            ? e.getMessage() : "Нет ответа от TorrServer или сервер вернул неподдерживаемые данные.";
    }
    interface Use<T> { void accept(T value); }
    private void showEntries(List<Sources.Entry> entries, Use<Sources.Entry> click) {
        if (entries.isEmpty()) body.addView(text("Нет папок или поддерживаемых медиафайлов.", 17));
        // Recycle rows even on very large shares.
        if (entries.size() <= 100) {
            for (Sources.Entry e : entries) add(e.folder() ? "▸  " + e.label() : e.label(), () -> click.accept(e));
        } else {
            // Keep the simple focus order without creating thousands of views at once.
            showBatch(entries, click, 0);
        }
    }
    private void showBatch(List<Sources.Entry> entries, Use<Sources.Entry> click, int from) {
        int start = body.getChildCount();
        int end = Math.min(entries.size(), from + 80);
        if (from > 0) add("‹ Предыдущие", () -> { body.removeViews(start, body.getChildCount()-start); showBatch(entries, click, from-80); body.getChildAt(start).requestFocus(); });
        for (int i = from; i < end; i++) {
            Sources.Entry e = entries.get(i); add(e.folder() ? "▸  " + e.label() : e.label(), () -> click.accept(e));
        }
        if (end < entries.size()) add("Следующие ›", () -> { body.removeViews(start, body.getChildCount()-start); showBatch(entries, click, end); body.getChildAt(start).requestFocus(); });
    }
    private void showError(String title, String message, Runnable retry) {
        page(title, message); add("Повторить", retry); add("‹ Назад", this::onBackPressed);
    }
    private <T> void async(Callable<T> work, Use<T> success, Use<Exception> error) {
        int token = revision;
        io.submit(() -> {
            try {
                T value = work.call();
                ui.post(() -> {
                    if (!destroyed && token == revision) success.accept(value);
                    else if (value instanceof MediaDataSource) try { ((MediaDataSource)value).close(); } catch (Exception ignored) {}
                });
            } catch (Exception e) { ui.post(() -> { if (!destroyed && token == revision) error.accept(e); }); }
        });
    }

    private void discover() {
        page("Поиск в локальной сети", "Ищу SMB и TorrServer…");
        add("‹ Назад", this::onBackPressed);
        ConnectivityManager cm = (ConnectivityManager)getSystemService(CONNECTIVITY_SERVICE);
        Network net = cm.getActiveNetwork();
        LinkProperties link = net == null ? null : cm.getLinkProperties(net);
        async(() -> Discovery.search(net, link), found -> {
            page("Серверы в локальной сети", found.isEmpty()
                ? "На проверенных адресах ничего не найдено. Можно подключиться вручную."
                : "Выберите сервер. Для SMB укажите имя общей папки. Порт SMB проверяется без входа.");
            add("‹ Назад", this::onBackPressed);
            for (Discovery.Result r : found) add(r.label(), () -> form(r.torr(), r.address()));
            add("Ввести адрес SMB", () -> form(false, ""));
            add("Ввести адрес TorrServer", () -> form(true, ""));
        }, e -> {
            page("Поиск в локальной сети", "Подключитесь к домашнему Wi-Fi или Ethernet либо введите адрес.");
            add("‹ Назад", this::onBackPressed);
            add("Ввести адрес SMB", () -> form(false, ""));
            add("Ввести адрес TorrServer", () -> form(true, ""));
        });
    }
    private void playback(List<Library.Item> items,int index,Uri uri,Map<String,String> headers,Callable<MediaDataSource> factory) {
        revision++; releasePlayer();
        queue=items; queueIndex=index; playingRef=items.get(index).ref();
        playbackRoot=new FrameLayout(this); playbackRoot.setBackgroundColor(Color.BLACK);
        playbackScreen=new FrameLayout(this); playbackRoot.addView(playbackScreen,new FrameLayout.LayoutParams(-1,-1));
        setContentView(playbackRoot);
        beforePlayerBars=getWindow().getDecorView().getSystemUiVisibility();
        getWindow().getDecorView().setSystemUiVisibility(IMMERSIVE);
        playingTitle = playingRef.title();
        currentStatus = "Подготовка…";
        playFrame = new FrameLayout(this);
        playbackScreen.addView(playFrame, new FrameLayout.LayoutParams(-1,-1));
        tapArea=new View(this);
        tapArea.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        tapArea.setOnClickListener(v -> {
            if (glasses!=null) return; // The phone keeps its own controls.
            if (showStereoSettings) { showStereoSettings=false; buildPlaybackBars(); }
            showControls(!controlsVisible);
        });
        playbackScreen.addView(tapArea,new FrameLayout.LayoutParams(-1,-1));
        playFrame.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob) -> fitVideo());
        playbackBars = new LinearLayout(this);
        playbackBars.setClickable(true);
        playbackScreen.addView(playbackBars,new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM));
        controlsVisible=true; stereoOverridden=false;
        playbackSpeed=defaultSpeed;
        playbackFit=defaultFit;
        stereoMode=initialStereoMode();
        wantPlay = true;
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        switchOutput();
        if (factory == null) prepare(uri, headers, null);
        else async(factory, source -> prepare(null, headers, source), e -> playbackStatus(smbError(e)));
    }
    private final Runnable hideControls = () -> {
        if (playbackBars!=null && !showStereoSettings && !dragging && glasses==null && prepared && player.isPlaying())
            showControls(false);
    };
    private void scheduleHide() {
        ui.removeCallbacks(hideControls);
        if (playbackBars!=null && controlsVisible && !showStereoSettings && !dragging &&
            glasses==null && prepared && player.isPlaying() && HIDE_MS[hideIndex]>0)
            ui.postDelayed(hideControls,HIDE_MS[hideIndex]);
    }
    private void showControls(boolean show) {
        if (playbackBars==null) return;
        controlsVisible=show || glasses!=null;
        playbackBars.setVisibility(controlsVisible?View.VISIBLE:View.INVISIBLE);
        if (controlsVisible && tv && !playControls.isEmpty()) playControls.get(0).toggle().requestFocus();
        scheduleHide();
    }
    private int initialStereoMode() {
        if (startStereo!=4) return startStereo;
        return looksLikeXreal(externalDisplay()) || looksLikeXreal(getWindowManager().getDefaultDisplay()) ?
            StereoView.DUPLICATE : 0;
    }
    private void buildPlaybackBars() {
        if (playbackBars == null) return;
        Display hint=externalDisplay();
        lastHintId=hint==null?-1:hint.getDisplayId();
        lastWideHint=looksLikeXreal(hint) || looksLikeXreal(getWindowManager().getDefaultDisplay());
        playbackBars.removeAllViews(); playControls.clear(); edgeControls.clear();
        int copies = mirroredBars ? 2 : 1;
        for (int eye=0;eye<copies;eye++) {
            LinearLayout strip = column();
            int side=dp(tv?(mirroredBars?20:36):(mirroredBars?8:16));
            strip.setPadding(side,dp(10),side,dp(tv?16:8));
            strip.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                new int[]{0x18000000,homeTheme==0 ? 0xf00f0f0f : 0xf0101522}));
            playbackBars.addView(strip,new LinearLayout.LayoutParams(0,-2,1));
            buildControls(strip);
        }
        playbackBars.setVisibility(controlsVisible?View.VISIBLE:View.INVISIBLE);
        if (tv && controlsVisible && !playControls.isEmpty() && !showStereoSettings) playControls.get(0).toggle().requestFocus();
        scheduleHide();
    }
    private void buildControls(LinearLayout strip) {
        TextView name = text(playingTitle, tv ? 19 : 15); name.setSingleLine(true); strip.addView(name);
        Display hint = externalDisplay();
        boolean detected = looksLikeXreal(hint) || looksLikeXreal(getWindowManager().getDefaultDisplay());
        if (detected && (stereoMode == 0 || showStereoSettings))
            strip.addView(text("Обнаружен режим 3840 × 1080 · XREAL / SBS",14));
        TextView status = text(currentStatus, 14); strip.addView(status);
        SeekBar seek = new SeekBar(this); seek.setMax(1000); seek.setEnabled(prepared && player.getDuration()>0);
        tintSeek(seek);
        strip.addView(seek);
        seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onStartTrackingTouch(SeekBar b) { dragging = true; scheduleHide(); }
            public void onStopTrackingTouch(SeekBar b) { seekToRatio(b.getProgress()); dragging = false; scheduleHide(); }
            public void onProgressChanged(SeekBar b, int p, boolean user) { if (user && !dragging) seekToRatio(p); }
        });
        LinearLayout controls = new LinearLayout(this); strip.addView(controls);
        rowButton(controls, "‹", this::exitPlayback).setContentDescription("Назад");
        rowButton(controls, "−10 с", () -> jump(-10000));
        Button toggle = rowButton(controls, "", this::togglePlayback);
        updatePlayButton(toggle,prepared && player.isPlaying());
        rowButton(controls, "+10 с", () -> jump(10000));
        Button gear=rowButton(controls, "⚙", () -> {
            showStereoSettings=!showStereoSettings; extraPanel=0; buildPlaybackBars();
        });
        gear.setContentDescription("Настройки плеера");
        playControls.add(new Controls(status,seek,toggle));
        if (showStereoSettings) {
            if (extraPanel!=0) { buildExtraPanel(strip); return; }
            LinearLayout features=new LinearLayout(this); strip.addView(features);
            rowButton(features,"Дорожки",() -> {extraPanel=1;buildPlaybackBars();});
            rowButton(features,"Плейлист",() -> {extraPanel=3;buildPlaybackBars();});
            rowButton(features,"Кадр",() -> {extraPanel=7;buildPlaybackBars();});
            LinearLayout choices = new LinearLayout(this); strip.addView(choices);
            Button modeButton=rowButton(choices,"Режим: " + VIDEO_MODES[stereoMode] + " ›", () -> {
                setStereoMode((stereoMode+1)%VIDEO_MODES.length);
            });
            if (tv && controlsVisible && playControls.size()==1) modeButton.requestFocus();
            rowButton(choices,"Скорость: "+SPEED_LABELS[playbackSpeed],() -> {
                playbackSpeed=(playbackSpeed+1)%SPEEDS.length; applySpeed(); buildPlaybackBars();
            });
            if (stereoMode != 0) {
                rowButton(choices,"2D", () -> setStereoMode(0));
                strip.addView(button("Края: " + EDGE_MODES[edgeEffect] + " ›", () -> {
                    edgeEffect=(edgeEffect+1)%EDGE_MODES.length;
                    getPreferences(0).edit().putInt("stereoEdges",edgeEffect).apply();
                    updateStereo(); buildPlaybackBars();
                }));
                if (edgeEffect != 0) {
                    TextView strength = text("Сила сглаживания: " + edgeStrength + "%", 13);
                    strip.addView(strength);
                    SeekBar edges=new SeekBar(this); tintSeek(edges); edges.setMax(100); edges.setProgress(edgeStrength);
                    edges.setContentDescription("Сила сглаживания"); strip.addView(edges);
                    edgeControls.add(new EdgeControls(strength,edges));
                    edges.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
                        public void onStartTrackingTouch(SeekBar b) {}
                        public void onStopTrackingTouch(SeekBar b) {}
                        public void onProgressChanged(SeekBar b, int p, boolean user) {
                            if (!user) return;
                            edgeStrength=p;
                            for (EdgeControls c:edgeControls) {
                                c.label().setText("Сила сглаживания: "+p+"%");
                                if (c.slider()!=b) c.slider().setProgress(p);
                            }
                            getPreferences(0).edit().putInt("stereoStrength",p).apply();
                            updateStereo();
                        }
                    });
                }
            }
            if (hint != null) strip.addView(button(useExternal ? "Вывод: внешние очки ›" : "Вывод: экран телефона ›", () -> {
                setExternal(!useExternal);
                switchOutput();
            }));
        }
    }
    private void buildExtraPanel(LinearLayout strip) {
        LinearLayout panel=column();
        ScrollView scroll=new ScrollView(this); scroll.addView(panel);
        strip.addView(scroll,new LinearLayout.LayoutParams(-1,dp(tv?176:155)));
        Button back=button("‹ "+(extraPanel==4 || extraPanel==5 ? "Плейлист" : "Настройки"),() -> {
            extraPanel=(extraPanel==4 || extraPanel==5)?3:0; buildPlaybackBars();
        });
        panel.addView(back);
        if (tv && playControls.size()==1) back.requestFocus();
        switch (extraPanel) {
            case 1 -> {
                panel.addView(button("Аудиодорожка",() -> {extraPanel=2;buildPlaybackBars();}));
                panel.addView(button("Субтитры",() -> {extraPanel=6;buildPlaybackBars();}));
            }
            case 2 -> addTracks(panel,true);
            case 6 -> {
                panel.addView(button("Выключить субтитры",() -> {selectSubtitle(-1);buildPlaybackBars();}));
                panel.addView(button((externalSubtitles.isEmpty()?"":"✓ ")+"Открыть внешний SRT…",this::pickSrt));
                addTracks(panel,false);
            }
            case 3 -> {
                if (queue.size()>1) {
                    if (queueIndex>0) panel.addView(button("Предыдущее видео",() -> nextItem(-1)));
                    if (queueIndex+1<queue.size()) panel.addView(button("Следующее видео",() -> nextItem(1)));
                    panel.addView(button("Очередь · "+(queueIndex+1)+"/"+queue.size(),() -> {extraPanel=4;buildPlaybackBars();}));
                }
                panel.addView(button("Добавить в плейлист…",() -> {extraPanel=5;buildPlaybackBars();}));
                panel.addView(button("Повтор видео: "+(repeatItem?"вкл.":"выкл."),() -> {
                    repeatItem=!repeatItem;
                    if (player!=null && prepared) player.setLooping(repeatItem);
                    buildPlaybackBars();
                }));
            }
            case 4 -> {
                for (int i=0;i<queue.size();i++) {
                    int index=i;
                    panel.addView(button((i==queueIndex?"▶ ":"")+queue.get(i).ref().title(),() -> playItem(queue,index)));
                }
            }
            case 5 -> {
                ArrayList<String> names=new ArrayList<>(library.names());
                if (names.isEmpty()) names.add("Избранное");
                for (String name:names) panel.addView(button(name,() -> {
                    if (playingRef!=null) library.add(name,playingRef);
                    extraPanel=3; buildPlaybackBars();toast("Добавлено в «"+name+"»");
                }));
            }
            case 7 -> {
                for (int i=0;i<FIT_MODES.length;i++) {
                    int choice=i;
                    panel.addView(button((i==playbackFit?"✓ ":"")+FIT_MODES[i],() -> {
                        playbackFit=choice;
                        fitVideo(); updateStereo(); buildPlaybackBars();
                    }));
                }
            }
        }
    }
    private void nextItem(int step) {
        int index=queueIndex+step;
        if (index>=0 && index<queue.size()) playItem(queue,index);
    }
    private void addTracks(LinearLayout panel,boolean audio) {
        if (!prepared || player==null) {panel.addView(text("Видео ещё не готово.",14));return;}
        try {
            MediaPlayer.TrackInfo[] tracks=player.getTrackInfo();
            int selected=audio?player.getSelectedTrack(MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_AUDIO):subtitleTrack;
            int matched=0;
            for (int i=0;i<tracks.length;i++) {
                MediaPlayer.TrackInfo track=tracks[i]; int type=track.getTrackType();
                boolean relevant=audio?type==MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_AUDIO:
                    type==MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_TIMEDTEXT ||
                    (Build.VERSION.SDK_INT>=28 && type==MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_SUBTITLE && textual(track));
                if (!relevant) continue;
                matched++; int index=i;
                String lang=track.getLanguage();
                String label=(selected==i?"✓ ":"")+(audio?"Звук ":"Субтитры ")+matched+
                    (lang==null || lang.equals("und")?"":" · "+lang);
                panel.addView(button(label,() -> {
                    if (audio) {
                        try { player.selectTrack(index); }
                        catch (RuntimeException e) {toast("Android не смог переключить аудиодорожку.");}
                    } else selectSubtitle(index);
                    buildPlaybackBars();
                }));
            }
            if (matched==0) panel.addView(text("Нет поддерживаемых встроенных дорожек.",14));
        } catch (RuntimeException e) {panel.addView(text("Не удалось получить список дорожек.",14));}
    }
    private boolean textual(MediaPlayer.TrackInfo track) {
        android.media.MediaFormat format=track.getFormat();
        String mime=format==null?null:format.getString(android.media.MediaFormat.KEY_MIME);
        return "text/vtt".equals(mime) || "application/x-subrip".equals(mime) || "text/plain".equals(mime);
    }
    private void selectSubtitle(int index) {
        externalSubtitles=Collections.emptyList(); embeddedSubtitle=null;
        if (prepared && player!=null) {
            if (subtitleTrack>=0) try { player.deselectTrack(subtitleTrack); } catch (RuntimeException ignored) {}
            subtitleTrack=-1;
            if (index>=0) try { player.selectTrack(index); subtitleTrack=index; }
            catch (RuntimeException e) {toast("Эта дорожка субтитров не поддерживается устройством.");}
        }
        updateCaption();
    }
    private void pickSrt() {
        subtitlePickerRevision=revision;
        Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE);
        try {startActivityForResult(intent,11);}
        catch (ActivityNotFoundException e) {toast("На устройстве нет приложения для выбора SRT.");}
    }
    private void updatePlayButton(Button b,boolean playing) {
        String glyph=playing ? "Ⅱ" : "▶";
        if (!glyph.contentEquals(b.getText())) b.setText(glyph);
        String label=playing ? "Пауза" : "Воспроизвести";
        if (!label.contentEquals(b.getContentDescription()==null ? "" : b.getContentDescription())) b.setContentDescription(label);
    }
    private void exitPlayback() {
        if (!history.isEmpty()) history.pop().run(); else home();
    }
    private void playbackStatus(String value) {
        currentStatus=value;
        for (Controls group:playControls) {
            if (!value.contentEquals(group.status().getText())) group.status().setText(value);
        }
    }
    static boolean xrealResolution(int width,int height) {
        return width==3840 && height==1080;
    }
    private boolean looksLikeXreal(Display display) {
        if (display == null) return false;
        Display.Mode mode=display.getMode();
        return mode != null && xrealResolution(mode.getPhysicalWidth(),mode.getPhysicalHeight());
    }
    private Display externalDisplay() {
        if (displays == null) return null;
        Display candidate = null;
        int current = getWindowManager().getDefaultDisplay().getDisplayId();
        for (Display d : displays.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)) {
            if (!d.isValid() || d.getDisplayId()==current) continue;
            if (looksLikeXreal(d)) return d;
            if (candidate==null) candidate=d;
        }
        return candidate;
    }
    private final DisplayManager.DisplayListener displayListener = new DisplayManager.DisplayListener() {
        public void onDisplayAdded(int id) { changed(); }
        public void onDisplayChanged(int id) { changed(); }
        public void onDisplayRemoved(int id) { changed(); }
        void changed() {
            if (playFrame == null) return;
            if (startStereo==4 && !stereoOverridden && initialStereoMode()!=stereoMode) {
                stereoMode=initialStereoMode(); switchOutput(); return;
            }
            Display d=stereoMode!=0 && useExternal ? externalDisplay() : null;
            int next=d==null ? -1 : d.getDisplayId();
            if (next!=selectedDisplayId || (glasses!=null && !glasses.isShowing())) switchOutput();
            else {
                Display hint=externalDisplay();
                int hintId=hint==null?-1:hint.getDisplayId();
                boolean wide=looksLikeXreal(hint) || looksLikeXreal(getWindowManager().getDefaultDisplay());
                if (hintId!=lastHintId || wide!=lastWideHint) buildPlaybackBars();
            }
        }
    };
    private void switchOutput() {
        if (playFrame==null) return;
        int token=++outputGeneration;
        detachOutput();
        if (stereoMode==0) {
            restoreOrientation();
            mirroredBars=false;
            video = new SurfaceView(this);
            playFrame.addView(video,new FrameLayout.LayoutParams(-1,-1,Gravity.CENTER));
            fitVideo();
            video.getHolder().addCallback(new SurfaceHolder.Callback() {
                public void surfaceCreated(SurfaceHolder h) { connectSurface(token,h.getSurface()); }
                public void surfaceChanged(SurfaceHolder h,int format,int w,int height) {}
                public void surfaceDestroyed(SurfaceHolder h) { connectSurface(token,null); }
            });
            attachCaptions(playFrame,false);
        } else {
            Display target=useExternal ? externalDisplay() : null;
            if (target!=null) {
                try {
                    Presentation panel = new Presentation(this,target);
                    panel.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE);
                    stereo=newStereo(panel.getContext(),token);
                    FrameLayout external=new FrameLayout(panel.getContext());
                    external.addView(stereo,new FrameLayout.LayoutParams(-1,-1));
                    panel.setContentView(external);
                    panel.show();
                    panel.getWindow().setLayout(-1,-1);
                    panel.getWindow().getDecorView().setSystemUiVisibility(IMMERSIVE);
                    selectedDisplayId=target.getDisplayId();
                    glasses=panel;
                    attachCaptions(external,true);
                } catch (WindowManager.InvalidDisplayException | SecurityException e) {
                    if (stereo!=null) { stereo.dispose(); stereo=null; }
                }
            }
            mirroredBars=glasses==null;
            if (mirroredBars) {
                if (!tv && beforeStereoOrientation==Integer.MIN_VALUE) {
                    beforeStereoOrientation=getRequestedOrientation();
                    setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
                }
                stereo=newStereo(this,token);
                playFrame.addView(stereo,new FrameLayout.LayoutParams(-1,-1));
                attachCaptions(playFrame,true);
            } else {
                restoreOrientation();
                LinearLayout remote=column();
                remote.setGravity(Gravity.CENTER);
                TextView message=text("Видео на внешнем экране",19);
                remote.addView(message);
                remote.addView(button(tv ? "Затемнить основной экран" : "Чёрный экран телефона", () -> setPhoneBlack(true)));
                playFrame.addView(remote,new FrameLayout.LayoutParams(-1,-1));
                controlsVisible=true;
            }
            updateStereo();
        }
        tapArea.setVisibility(glasses==null?View.VISIBLE:View.GONE);
        buildPlaybackBars();
    }
    private void setStereoMode(int next) {
        stereoOverridden=true;
        boolean sameSurface=stereoMode!=0 && next!=0 && stereo!=null;
        stereoMode=next;
        if (sameSurface) { updateStereo(); buildPlaybackBars(); }
        else switchOutput();
    }
    private StereoView newStereo(Context context, int token) {
        return new StereoView(context, new StereoView.Output() {
            public void ready(Surface surface) { connectSurface(token,surface); }
            public void failed() {
                if (token!=outputGeneration || playFrame==null) return;
                stereoMode=0;
                switchOutput();
                toast("Не удалось запустить SBS на этом экране. Включён режим 2D.");
            }
        });
    }
    private void connectSurface(int token, Surface surface) {
        if (token != outputGeneration || playFrame==null) return;
        activeSurface=surface;
        if (player==null) return;
        try {
            player.setSurface(surface);
            if (surface!=null && prepared && !player.isPlaying() && videoWidth>0
                && player.getDuration()>0 && Build.VERSION.SDK_INT>=26)
                player.seekTo(player.getCurrentPosition(),MediaPlayer.SEEK_CLOSEST);
        } catch (IllegalStateException ignored) {}
    }
    private void updateStereo() {
        if (stereo!=null) stereo.configure(stereoMode,edgeEffect,edgeStrength,videoWidth,videoHeight,playbackFit);
    }
    private void restoreOrientation() {
        if (beforeStereoOrientation==Integer.MIN_VALUE) return;
        int orientation=beforeStereoOrientation;
        beforeStereoOrientation=Integer.MIN_VALUE;
        setRequestedOrientation(orientation);
    }
    private void setPhoneBlack(boolean black) {
        if (black) {
            if (phoneBlack!=null || glasses==null || playbackRoot==null) return;
            beforeBlackBars=getWindow().getDecorView().getSystemUiVisibility();
            getWindow().getDecorView().setSystemUiVisibility(IMMERSIVE);
            playbackScreen.setVisibility(View.INVISIBLE);
            View shade=new View(this);
            shade.setBackgroundColor(Color.BLACK);
            shade.setContentDescription("Чёрный экран. Коснитесь, чтобы вернуть управление");
            shade.setFocusableInTouchMode(true);
            shade.setOnClickListener(v -> setPhoneBlack(false));
            playbackRoot.addView(shade,new FrameLayout.LayoutParams(-1,-1));
            phoneBlack=shade;
            shade.requestFocus();
        } else if (phoneBlack!=null) {
            playbackRoot.removeView(phoneBlack);
            phoneBlack=null;
            playbackScreen.setVisibility(View.VISIBLE);
            getWindow().getDecorView().setSystemUiVisibility(beforeBlackBars);
            if (glasses!=null && tv && !playControls.isEmpty()) playControls.get(0).toggle().requestFocus();
        }
    }
    private void detachOutput() {
        setPhoneBlack(false);
        activeSurface=null;
        if (player!=null) try { player.setSurface(null); } catch (IllegalStateException ignored) {}
        if (stereo!=null) { stereo.dispose(); stereo=null; }
        if (glasses!=null) { glasses.dismiss(); glasses=null; }
        if (captionHost!=null && captionLayout!=null) captionHost.removeOnLayoutChangeListener(captionLayout);
        captions=new TextView[0]; captionHost=null; captionLayout=null;
        selectedDisplayId=-1;
        if (playFrame!=null) playFrame.removeAllViews();
        video=null;
    }
    private void attachCaptions(FrameLayout host,boolean doubleEyes) {
        captionHost=host;
        LinearLayout line=new LinearLayout(host.getContext());
        captions=new TextView[doubleEyes?2:1];
        for (int i=0;i<captions.length;i++) {
            TextView t=new TextView(host.getContext()); captions[i]=t;
            t.setTextColor(Color.WHITE); t.setTextSize(tv?23:19); t.setGravity(Gravity.CENTER);
            t.setTypeface(null,android.graphics.Typeface.BOLD);
            t.setPadding(dp(14),dp(8),dp(14),dp(8));
            t.setShadowLayer(dp(4),0,0,Color.BLACK);
            t.setMaxLines(4);
            t.setText(caption);
            t.setVisibility(caption.isEmpty()?View.INVISIBLE:View.VISIBLE);
            line.addView(t,new LinearLayout.LayoutParams(0,-2,1));
        }
        host.addView(line,new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM));
        captionLayout=(v,l,t,r,b,ol,ot,or,ob) -> {
            if (captionHost==host) line.setTranslationY(-host.getHeight()*.12f);
        };
        host.addOnLayoutChangeListener(captionLayout);
        line.setTranslationY(-host.getHeight()*.12f);
    }
    private void updateCaption() {
        String value="";
        if (prepared && player!=null) {
            long pos=player.getCurrentPosition();
            SubRip.Cue cue=externalSubtitles.isEmpty()?embeddedSubtitle:SubRip.at(externalSubtitles,pos);
            if (cue!=null && pos>=cue.start() && pos<cue.end()) value=cue.line();
        }
        if (value.equals(caption)) return;
        caption=value;
        for (TextView t:captions) {
            t.setText(value); t.setVisibility(value.isEmpty()?View.INVISIBLE:View.VISIBLE);
        }
    }
    private Button rowButton(LinearLayout row, String label, Runnable action) {
        Button b = button(label, () -> { action.run(); scheduleHide(); }); b.setPadding(dp(4), dp(4), dp(4), dp(4));
        b.setMinHeight(dp(tv ? 48 : 42)); b.setTextSize(tv?17:14);
        row.addView(b, new LinearLayout.LayoutParams(0, -2, 1)); return b;
    }
    private void fitVideo() {
        FrameLayout frame=playFrame;
        if (frame==null) return;
        if (video == null || videoWidth <= 0 || videoHeight <= 0 || frame.getWidth() == 0 || frame.getHeight() == 0) return;
        float sx=(float)frame.getWidth()/videoWidth,sy=(float)frame.getHeight()/videoHeight;
        float scale=switch(playbackFit) {
            case 1 -> sx; case 2 -> sy; case 3 -> Math.max(sx,sy); default -> Math.min(sx,sy);
        };
        int w=playbackFit==4?frame.getWidth():Math.round(scale*videoWidth);
        int h=playbackFit==4?frame.getHeight():Math.round(scale*videoHeight);
        ViewGroup.LayoutParams lp = video.getLayoutParams();
        if (lp.width != w || lp.height != h) { lp.width=w; lp.height=h; video.setLayoutParams(lp); }
    }
    private void prepare(Uri uri, Map<String,String> headers, MediaDataSource source) {
        MediaPlayer p = new MediaPlayer(); player = p;
        try {
            if (activeSurface!=null) p.setSurface(activeSurface);
            p.setOnVideoSizeChangedListener((mp, w, h) -> {
                if (player == mp) { videoWidth=w; videoHeight=h; fitVideo(); updateStereo(); }
            });
            p.setOnPreparedListener(mp -> {
                if (player != mp) return;
                prepared = true;
                mp.setLooping(repeatItem);
                int saved=resumeEnabled && playingRef!=null?library.position(playingRef):0;
                if (saved>=3000 && saved<mp.getDuration()-5000) {
                    resumePending=true; seekToMs(saved);
                }
                for (Controls group:playControls) group.seek().setEnabled(mp.getDuration()>0);
                if (wantPlay && visible) mp.start();
                if (playbackSpeed!=1) applySpeed();
                scheduleHide();
                updatePosition.run();
            });
            p.setOnSeekCompleteListener(mp -> {
                if (player==mp) { resumePending=false; updateCaption(); }
            });
            p.setOnTimedTextListener((mp,value) -> {
                if (mp!=player || subtitleTrack<0) return;
                embeddedSubtitle=value==null?null:new SubRip.Cue(0,Long.MAX_VALUE,SubRip.clean(value.getText()==null?"":value.getText()));
                updateCaption();
            });
            if (Build.VERSION.SDK_INT>=28) p.setOnSubtitleDataListener((mp,data) -> {
                if (mp!=player || subtitleTrack!=data.getTrackIndex()) return;
                long start=data.getStartTimeUs()/1000,end=start+data.getDurationUs()/1000;
                byte[] bytes=data.getData();
                if (bytes.length>32768) return;
                String line=SubRip.clean(new String(bytes,java.nio.charset.StandardCharsets.UTF_8));
                embeddedSubtitle=line.isEmpty()?null:new SubRip.Cue(start,end,line); updateCaption();
            });
            p.setOnErrorListener((mp, what, extra) -> {
                if (player == mp) {
                    prepared = false;
                    showControls(true);
                    for (Controls group:playControls) group.seek().setEnabled(false);
                    playbackStatus("Не удалось воспроизвести: сеть, формат или кодек устройства (" + what + "/" + extra + ").");
                }
                return true;
            });
            p.setOnCompletionListener(mp -> {
                if (player==mp) {
                    if (resumeEnabled && playingRef!=null) library.remember(playingRef,mp.getDuration(),mp.getDuration());
                    wantPlay=false;
                    if (queueIndex+1<queue.size()) nextItem(1); else showControls(true);
                }
            });
            if (source != null) p.setDataSource(source);
            else if ("content".equals(uri.getScheme())) p.setDataSource(this, uri);
            else {
                Map<String,String> safe = new HashMap<>(headers);
                safe.put("android-allow-cross-domain-redirect", "0");
                p.setDataSource(this, uri, safe);
            }
            p.prepareAsync();
        } catch (Exception e) {
            if (source != null) try { source.close(); } catch (Exception ignored) {}
            p.release(); player = null; playbackStatus("Не удалось открыть источник видео.");
        }
    }
    private void togglePlayback() {
        if (!prepared || player == null) return;
        if (player.isPlaying()) { wantPlay = false; player.pause(); }
        else { wantPlay = true; player.start(); }
        showControls(true);
    }
    private void applySpeed() {
        if (!prepared || player==null) return;
        boolean wasPlaying=player.isPlaying();
        try {
            player.setPlaybackParams(player.getPlaybackParams().setSpeed(SPEEDS[playbackSpeed]));
            if (!wasPlaying) player.pause();
        } catch (IllegalArgumentException | IllegalStateException e) {
            playbackSpeed=1; toast("Устройство не приняло выбранную скорость.");
        }
    }
    private void jump(int delta) {
        if (prepared && player != null && player.getDuration() > 0)
            seekToMs(Math.max(0, Math.min(player.getDuration(), player.getCurrentPosition()+delta)));
    }
    private void seekToRatio(int ratio) {
        if (prepared && player != null && player.getDuration() > 0)
            seekToMs((int)(player.getDuration() * (long)ratio / 1000));
    }
    private void seekToMs(int pos) {
        if (player==null) return;
        embeddedSubtitle=null;
        if (Build.VERSION.SDK_INT>=26) player.seekTo(pos,MediaPlayer.SEEK_CLOSEST);
        else player.seekTo(pos);
    }
    private void savePosition() {
        if (!resumeEnabled || !prepared || resumePending || playingRef==null || player==null) return;
        try { library.remember(playingRef,player.getCurrentPosition(),player.getDuration()); }
        catch (IllegalStateException ignored) {}
    }
    private final Runnable updatePosition = new Runnable() {
        public void run() {
            if (!prepared || player == null) return;
            int pos = player.getCurrentPosition(), duration = player.getDuration();
            int bucket=pos/5000;
            if (!resumePending && bucket!=lastSavedSecond) {
                lastSavedSecond=bucket; if (bucket>0) savePosition();
            }
            updateCaption();
            playbackStatus(time(pos) + (duration > 0 ? "  /  " + time(duration) : ""));
            boolean playing=player.isPlaying();
            for (Controls group:playControls) {
                if (!dragging && duration>0) group.seek().setProgress((int)(pos * 1000L/duration));
                updatePlayButton(group.toggle(),playing);
            }
            ui.postDelayed(this,(externalSubtitles.isEmpty() && subtitleTrack<0)?500:150);
        }
    };
    private String time(int ms) {
        long s = Math.max(0,ms/1000); return String.format(Locale.ROOT,"%d:%02d",s/60,s%60);
    }
    @Override public boolean dispatchKeyEvent(KeyEvent e) {
        int key=e.getKeyCode();
        if (wakeKey!=0 && wakeKey==key && e.getAction()==KeyEvent.ACTION_UP) { wakeKey=0; return true; }
        if (playFrame!=null && phoneBlack==null && key>=KeyEvent.KEYCODE_DPAD_UP && key<=KeyEvent.KEYCODE_DPAD_CENTER
            && e.getAction()==KeyEvent.ACTION_DOWN) {
            if (!controlsVisible) {
                if (tv && prepared && player!=null) {
                    if (key==KeyEvent.KEYCODE_DPAD_CENTER) togglePlayback();
                    else if (key==KeyEvent.KEYCODE_DPAD_LEFT) jump(-10000);
                    else if (key==KeyEvent.KEYCODE_DPAD_RIGHT) jump(10000);
                }
                showControls(true); wakeKey=key; return true;
            }
            if (wakeKey==key) return true;
            scheduleHide();
        }
        return super.dispatchKeyEvent(e);
    }
    @Override public boolean onKeyDown(int key, KeyEvent event) {
        if (prepared && (key == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE || key == KeyEvent.KEYCODE_MEDIA_PLAY ||
                key == KeyEvent.KEYCODE_MEDIA_PAUSE)) {
            if (event.getRepeatCount() == 0) {
                if (key == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) togglePlayback();
                else if (key == KeyEvent.KEYCODE_MEDIA_PLAY && !player.isPlaying()) togglePlayback();
                else if (key == KeyEvent.KEYCODE_MEDIA_PAUSE && player.isPlaying()) togglePlayback();
            }
            return true;
        }
        return super.onKeyDown(key, event);
    }
    @Override protected void onPause() {
        visible=false;
        savePosition();
        super.onPause(); if (prepared && player != null && player.isPlaying()) player.pause();
        if (stereo!=null) stereo.onPause();
    }
    @Override protected void onResume() {
        super.onResume(); visible=true;
        if (stereo!=null) stereo.onResume();
        if (prepared && player != null && wantPlay) player.start();
        scheduleHide();
    }
    @Override public void onWindowFocusChanged(boolean focus) {
        super.onWindowFocusChanged(focus);
        if (focus && visible && prepared && player != null && wantPlay && !player.isPlaying()) player.start();
    }
    private void releasePlayer() {
        savePosition();
        ui.removeCallbacks(updatePosition); ui.removeCallbacks(hideControls);
        prepared = false; wantPlay = false; wakeKey=0;
        dragging = false; videoWidth = videoHeight = 0;
        ++outputGeneration;
        detachOutput();
        if (playbackRoot!=null) getWindow().getDecorView().setSystemUiVisibility(beforePlayerBars);
        if (player != null) { player.release(); player = null; }
        playingRef=null; queue=Collections.emptyList(); queueIndex=0; extraPanel=0;
        repeatItem=false; lastSavedSecond=-1; resumePending=false; subtitleTrack=-1;
        externalSubtitles=Collections.emptyList(); embeddedSubtitle=null; caption="";
        playFrame=null; playbackBars=null; playbackRoot=null; playbackScreen=null; tapArea=null;
        playControls.clear(); edgeControls.clear(); showStereoSettings=false; stereoMode=0;
        restoreOrientation();
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }
    @Override protected void onDestroy() {
        destroyed = true; displays.unregisterDisplayListener(displayListener);
        releasePlayer(); io.shutdownNow(); super.onDestroy();
    }
}
