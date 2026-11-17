package neon.androidplayer;

import android.media.MediaDataSource;
import android.net.Uri;
import android.util.Base64;
import com.hierynomus.smbj.SMBClient;
import com.hierynomus.smbj.SmbConfig;
import com.hierynomus.smbj.auth.AuthenticationContext;
import com.hierynomus.smbj.share.DiskShare;
import com.hierynomus.smbj.share.File;
import com.hierynomus.msdtyp.AccessMask;
import com.hierynomus.mssmb2.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.TimeUnit;
import org.json.*;

final class Sources {
    record Entry(String label, String path, boolean folder, int index) {}
    record Login(String user, String password, String domain) {
        boolean guest() { return user.isEmpty(); }
    }
    record Smb(String host, int port, String share, Login login) {
        SMBClient client() {
            // Limit active requests. The socket itself may sit idle while paused.
            return new SMBClient(SmbConfig.builder().withTimeout(6, TimeUnit.SECONDS)
                .withSoTimeout(0, TimeUnit.SECONDS).build());
        }
        DiskShare open(SMBClient client, boolean guestFallback) throws IOException {
            AuthenticationContext context = login.guest()
                ? (guestFallback ? AuthenticationContext.guest() : AuthenticationContext.anonymous())
                : new AuthenticationContext(login.user(), login.password().toCharArray(), login.domain());
            return (DiskShare) client.connect(host, port).authenticate(context).connectShare(share);
        }
        List<Entry> list(String folder) throws Exception {
            return attempt((client, disk) -> {
                List<Entry> entries = new ArrayList<>();
                for (var f : disk.list(folder)) {
                    String n = f.getFileName();
                    if (n.equals(".") || n.equals("..")) continue;
                    boolean dir = (f.getFileAttributes() & 0x10) != 0;
                    if (dir || media(n)) entries.add(new Entry(n, folder.isEmpty() ? n : folder + "\\" + n, dir, 0));
                }
                entries.sort(Comparator.comparing((Entry e) -> !e.folder()).thenComparing(Entry::label, String.CASE_INSENSITIVE_ORDER));
                return entries;
            }, false);
        }
        MediaDataSource file(String path) throws Exception {
            return attempt((client, disk) -> {
                File file = disk.openFile(path, EnumSet.of(AccessMask.GENERIC_READ), null,
                    SMB2ShareAccess.ALL, SMB2CreateDisposition.FILE_OPEN, null);
                long size = disk.getFileInformation(path).getStandardInformation().getEndOfFile();
                return new MediaDataSource() {
                    final byte[] block = new byte[128 * 1024];
                    long start = -1;
                    int length;
                    boolean closed;
                    @Override public synchronized int readAt(long position, byte[] dst, int offset, int count) throws IOException {
                        if (closed) throw new IOException("SMB закрыт");
                        if (count == 0) return 0;
                        if (position >= size) return -1;
                        int copied = 0;
                        try {
                            while (copied < count && position < size) {
                                if (position < start || position >= start + length) {
                                    start = position;
                                    length = file.read(block, position, 0, (int)Math.min(block.length, size - position));
                                    if (length <= 0) break;
                                }
                                int delta = (int)(position - start);
                                int n = Math.min(count - copied, length - delta);
                                System.arraycopy(block, delta, dst, offset + copied, n);
                                position += n;
                                copied += n;
                            }
                        } catch (RuntimeException e) { throw new IOException("Чтение SMB прервано", e); }
                        return copied == 0 ? -1 : copied;
                    }
                    @Override public long getSize() { return size; }
                    @Override public synchronized void close() {
                        if (closed) return;
                        closed = true;
                        try { file.close(); } catch (Exception ignored) {}
                        client.close();
                    }
                };
            }, true);
        }
        private <T> T attempt(SmbWork<T> work, boolean transferOwnership) throws Exception {
            Exception first = null;
            for (int n = 0; n < (login.guest() ? 2 : 1); n++) {
                SMBClient client = client();
                boolean transferred = false;
                try {
                    T value = work.run(client, open(client, n == 1));
                    transferred = transferOwnership;
                    return value;
                } catch (Exception e) {
                    if (first == null) first = e;
                } finally {
                    if (!transferred) client.close();
                }
            }
            throw first;
        }
    }
    interface SmbWork<T> { T run(SMBClient client, DiskShare disk) throws Exception; }

    record Torr(String base, Login login) {
        Map<String,String> headers() {
            if (login.guest()) return Collections.emptyMap();
            return Collections.singletonMap("Authorization", "Basic " + Base64.encodeToString(
                (login.user() + ":" + login.password()).getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP));
        }
        JSONArray torrents() throws Exception {
            String raw = post(new JSONObject().put("action", "list"));
            return raw.trim().equals("null") ? new JSONArray() : new JSONArray(raw);
        }
        List<Entry> files(String hash, JSONObject summary) throws Exception {
            JSONArray files = summary.optJSONArray("file_stats");
            if (files == null || files.length() == 0)
                files = new JSONObject(post(new JSONObject().put("action", "get").put("hash", hash))).optJSONArray("file_stats");
            if (files == null) return Collections.emptyList();
            List<Entry> out = new ArrayList<>();
            for (int i = 0; i < files.length(); i++) {
                JSONObject item = files.optJSONObject(i);
                if (item == null || !item.has("id")) continue;
                String path = item.optString("path");
                if (media(path)) out.add(new Entry(path, path, false, item.getInt("id")));
            }
            return out;
        }
        String stream(String hash, Entry file) {
            String name = file.path().substring(file.path().lastIndexOf('/') + 1);
            return base + "/stream/" + Uri.encode(name) + "?link=" + Uri.encode(hash) + "&index=" + file.index() + "&play";
        }
        private String post(JSONObject request) throws Exception {
            HttpURLConnection c = (HttpURLConnection) new URL(base + "/torrents").openConnection();
            c.setInstanceFollowRedirects(false);
            c.setConnectTimeout(4000); c.setReadTimeout(12000);
            c.setRequestMethod("POST"); c.setDoOutput(true);
            c.setRequestProperty("Content-Type", "application/json");
            headers().forEach(c::setRequestProperty);
            try {
                try (OutputStream out = c.getOutputStream()) { out.write(request.toString().getBytes(StandardCharsets.UTF_8)); }
                int status = c.getResponseCode();
                if (status == 401 || status == 403) throw new IOException("TorrServer отклонил вход. Проверьте логин и пароль.");
                if (status != 200) throw new IOException("TorrServer: HTTP " + status);
                try (InputStream in = c.getInputStream()) { return readText(in, 4 * 1024 * 1024); }
            } finally { c.disconnect(); }
        }
    }

    static String readText(InputStream in, int limit) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        for (int n; (n = in.read(buf)) != -1;) {
            if (out.size() + n > limit) throw new IOException("Ответ сервера слишком большой");
            out.write(buf, 0, n);
        }
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
    }
    static boolean media(String name) {
        return name.toLowerCase(Locale.ROOT).matches(".*\\.(mkv|mp4|mov|avi|webm|m4v|mpg|mpeg|ts|m2ts|wmv|flv|3gp|ogv|mp3|m4a|flac|ogg|opus|wav|aac)$");
    }
}
