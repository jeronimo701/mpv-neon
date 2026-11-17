package neon.androidplayer;

import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.util.*;
import java.util.regex.*;

final class SubRip {
    record Cue(long start,long end,String line) {}
    private static final Pattern RANGE=Pattern.compile("(\\d{1,4}:\\d\\d:\\d\\d[,.]\\d\\d\\d)\\s*-->\\s*(\\d{1,4}:\\d\\d:\\d\\d[,.]\\d\\d\\d).*");
    private static long time(String value) {
        String[] fields=value.split("[:.,]");
        return (Long.parseLong(fields[0])*3600+Long.parseLong(fields[1])*60+Long.parseLong(fields[2]))*1000+Long.parseLong(fields[3]);
    }
    static String clean(String value) {
        return value.replaceAll("</?(?:[biu]|font|c)(?:\\s[^<>]*)?>","")
            .replace("&lt;","<").replace("&gt;",">").replace("&amp;","&").trim();
    }
    static List<Cue> parse(byte[] bytes) {
        Charset charset=StandardCharsets.UTF_8;
        if (bytes.length>=2 && (((bytes[0]&255)==255 && (bytes[1]&255)==254)
            || ((bytes[0]&255)==254 && (bytes[1]&255)==255))) charset=StandardCharsets.UTF_16;
        String text;
        try { text=charset.newDecoder().decode(ByteBuffer.wrap(bytes)).toString(); }
        catch (CharacterCodingException e) { text=new String(bytes,Charset.forName("windows-1251")); }
        text=text.replace("\ufeff","").replace("\r\n","\n").replace('\r','\n');
        List<Cue> list=new ArrayList<>();
        for (String block:text.split("\\n\\s*\\n")) {
            String[] lines=block.split("\n",3);
            int line=-1;
            for (int i=0;i<Math.min(lines.length,2);i++) if (RANGE.matcher(lines[i].trim()).matches()) {line=i;break;}
            if (line==-1) continue;
            Matcher range=RANGE.matcher(lines[line].trim()); range.matches();
            long start=time(range.group(1)),end=time(range.group(2));
            int offset=0;
            for (int i=0;i<=line;i++) {
                offset=block.indexOf('\n',offset);
                if (offset<0) break;
                offset++;
            }
            if (offset<0 || end<=start) continue;
            String subtitle=clean(block.substring(offset));
            if (!subtitle.isEmpty()) list.add(new Cue(start,end,subtitle));
            if (list.size()>=30000) break;
        }
        list.sort(Comparator.comparingLong(Cue::start));
        return list;
    }
    static Cue at(List<Cue> cues,long pos) {
        int lo=0,hi=cues.size();
        while (lo<hi) {
            int mid=(lo+hi)>>>1;
            if (cues.get(mid).start()<=pos) lo=mid+1; else hi=mid;
        }
        if (lo==0) return null;
        Cue c=cues.get(lo-1);
        return pos<c.end()?c:null;
    }
}
