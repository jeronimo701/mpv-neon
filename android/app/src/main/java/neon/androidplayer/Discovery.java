package neon.androidplayer;

import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import java.io.InputStream;
import java.net.*;
import java.util.*;
import java.util.concurrent.*;

final class Discovery {
    record Result(boolean torr, String address, String detail) {
        String label() { return (torr ? "TorrServer · " : "SMB · ") + address + (detail.isEmpty() ? "" : " (" + detail + ")"); }
    }
    static List<Result> search(Network net, LinkProperties link) throws Exception {
        if (net == null || link == null) throw new IllegalStateException("No active local network");
        Set<String> addresses = new LinkedHashSet<>();
        for (LinkAddress a : link.getLinkAddresses()) {
            if (!(a.getAddress() instanceof Inet4Address)) continue;
            InetAddress local = a.getAddress();
            if (!(local.isSiteLocalAddress() || local.isLinkLocalAddress())) continue;
            byte[] bytes = local.getAddress();
            int own = ((bytes[0]&255)<<24)|((bytes[1]&255)<<16)|((bytes[2]&255)<<8)|(bytes[3]&255);
            int bits = Math.max(24, a.getPrefixLength());
            if (bits >= 31) continue;
            int count = 1 << (32-bits), base = own & ~(count-1);
            for (int i = 1; i < count-1 && addresses.size()<254; i++) {
                int ip = base + i;
                if (ip != own) addresses.add(((ip>>>24)&255)+"."+((ip>>>16)&255)+"."+((ip>>>8)&255)+"."+(ip&255));
            }
        }
        if (addresses.isEmpty()) throw new IllegalStateException("No directly connected private IPv4");
        List<Result> found = Collections.synchronizedList(new ArrayList<>());
        ArrayList<Callable<Void>> probes = new ArrayList<>();
        for (String host : addresses) {
            probes.add(() -> {
                try (Socket socket = net.getSocketFactory().createSocket()) {
                    socket.connect(new InetSocketAddress(host,445), 400);
                    found.add(new Result(false,host,"порт 445"));
                } catch (Exception ignored) {}
                return null;
            });
            for (int port : new int[]{8090,8099,5665}) probes.add(() -> {
                String endpoint = "http://" + host + ":" + port;
                HttpURLConnection c = null;
                try {
                    c = (HttpURLConnection) net.openConnection(new URL(endpoint + "/echo"), Proxy.NO_PROXY);
                    c.setInstanceFollowRedirects(false); c.setConnectTimeout(400); c.setReadTimeout(650);
                    int status = c.getResponseCode();
                    if (status == 200) {
                        try (InputStream in = c.getInputStream()) {
                            String v = Sources.readText(in, 256).trim();
                            if (v.startsWith("MatriX.") || v.startsWith("TorrServer"))
                                found.add(new Result(true, endpoint, v.replaceAll("[\\r\\n]", " ")));
                        }
                    } else if (status == 401 && c.getHeaderField("WWW-Authenticate") != null) {
                        found.add(new Result(true, endpoint, "возможный сервер, нужен вход"));
                    }
                } catch (Exception ignored) {}
                finally { if (c != null) c.disconnect(); }
                return null;
            });
        }
        ExecutorService pool = Executors.newFixedThreadPool(32);
        try { pool.invokeAll(probes, 20, TimeUnit.SECONDS); }
        finally { pool.shutdownNow(); }
        synchronized(found) {
            List<Result> result = new ArrayList<>(found);
            result.sort(Comparator.comparing(Result::torr).thenComparing(Result::address));
            return result;
        }
    }
}
