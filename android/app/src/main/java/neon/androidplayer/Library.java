package neon.androidplayer;

import android.content.SharedPreferences;
import java.util.*;
import org.json.*;

final class Library {
    // Persist locators, never credentials. For secured servers the user signs in again.
    record Ref(String kind,String title,String address,int port,String share,String path,boolean auth) {
        JSONObject json() {
            try {
                return new JSONObject().put("kind",kind).put("title",title).put("address",address)
                    .put("port",port).put("share",share).put("path",path).put("auth",auth);
            } catch (JSONException e) { throw new IllegalStateException(e); }
        }
        static Ref read(JSONObject o) {
            return new Ref(o.optString("kind"),o.optString("title"),o.optString("address"),o.optInt("port",445),
                o.optString("share"),o.optString("path"),o.optBoolean("auth"));
        }
        String key() { return kind+'\n'+address+'\n'+port+'\n'+share+'\n'+path; }
    }
    record Item(Ref ref,Sources.Login login) {}
    record Recent(Ref ref,int position) {}
    private final SharedPreferences prefs;
    Library(SharedPreferences prefs) { this.prefs=prefs; }

    private JSONObject read(String key) {
        try { return new JSONObject(prefs.getString(key,"{}")); }
        catch (JSONException e) { return new JSONObject(); }
    }
    private void store(String key,JSONObject v) { prefs.edit().putString(key,v.toString()).apply(); }
    int position(Ref ref) {
        JSONObject item=read("watchPositions").optJSONObject(ref.key());
        return item==null ? 0 : item.optInt("pos");
    }
    Recent recent() {
        JSONObject data=read("watchPositions");
        String key=prefs.getString("lastWatched","");
        JSONObject item=data.optJSONObject(key);
        return item==null || item.optJSONObject("media")==null ? null :
            new Recent(Ref.read(item.optJSONObject("media")),item.optInt("pos"));
    }
    void remember(Ref ref,int pos,int length) {
        if (length<=0 || (pos>0 && pos<3000)) return;
        JSONObject data=read("watchPositions");
        data.remove(ref.key());
        boolean finished=pos>=length-5000 || pos==0;
        try {
            if (!finished) data.put(ref.key(),new JSONObject().put("media",ref.json()).put("pos",pos));
            ArrayList<String> keys=new ArrayList<>();
            data.keys().forEachRemaining(keys::add);
            for (int i=0;i<keys.size()-200;i++) data.remove(keys.get(i));
        } catch (JSONException e) { return; }
        SharedPreferences.Editor out=prefs.edit().putString("watchPositions",data.toString());
        if (!finished) out.putString("lastWatched",ref.key());
        else if (ref.key().equals(prefs.getString("lastWatched",""))) out.remove("lastWatched");
        out.apply();
    }
    void clearHistory() { prefs.edit().remove("lastWatched").remove("watchPositions").apply(); }
    List<String> names() {
        ArrayList<String> list=new ArrayList<>();
        read("savedLists").keys().forEachRemaining(list::add);
        list.sort(String.CASE_INSENSITIVE_ORDER);
        return list;
    }
    List<Ref> entries(String name) {
        JSONArray array=read("savedLists").optJSONArray(name);
        ArrayList<Ref> out=new ArrayList<>();
        if (array!=null) for (int i=0;i<array.length();i++) {
            JSONObject value=array.optJSONObject(i);
            if (value!=null) out.add(Ref.read(value));
        }
        return out;
    }
    void create(String name) { if (!names().contains(name)) replace(name,new ArrayList<>()); }
    void add(String name,Ref ref) {
        List<Ref> values=entries(name);
        if (values.size()>=250 || values.stream().anyMatch(v->v.key().equals(ref.key()))) return;
        values.add(ref);replace(name,values);
    }
    void remove(String name,int index) {
        List<Ref> values=entries(name);
        if (index>=0 && index<values.size()) { values.remove(index);replace(name,values); }
    }
    void delete(String name) { JSONObject data=read("savedLists"); data.remove(name); store("savedLists",data); }
    private void replace(String name,List<Ref> entries) {
        JSONObject data=read("savedLists");
        JSONArray list=new JSONArray();
        for (Ref entry:entries) list.put(entry.json());
        try { data.put(name,list); store("savedLists",data); } catch (JSONException ignored) {}
    }
}
