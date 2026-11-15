package com.thesiegs.hearth;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Log;

import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.math.BigInteger;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.security.interfaces.RSAPublicKey;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import javax.security.auth.x500.X500Principal;

/**
 * The remote API (docs/tv-remote-api.md): a phone app on the home network pairs with a code shown on the TV, then
 * reads what's on and controls media, volume and apps. Runs in the TV owner's user only, as a foreground service:
 * the session port ({@link #SESSION_PORT}, announced as _hearth-tv._tcp) and the pairing port ({@link #PAIRING_PORT}).
 * Both answer home-network addresses only, over TLS with the phone's certificate; the session only for paired ones.
 */
public class RemoteApiService extends Service {
    private static final String TAG = "HearthRemoteApi";
    static final int SESSION_PORT = 7677;
    static final int PAIRING_PORT = 7678;
    static final String SERVICE_TYPE = "_hearth-tv._tcp";
    private static final String KEY_ALIAS = "hearth-remote-api-v2";
    private static final String CHANNEL = "remote_api";
    private static final int NOTIFICATION_ID = 3;
    private static final String CODE_TAG = "hearth_remote_pair";
    /** How long the code shows, and how long a pairing connection may take. */
    private static final int PAIRING_TIMEOUT_MS = 120_000;
    /** After a wrong code, another pairing waits this long (a code on the TV can't be guessed by retrying). */
    private static final long AFTER_WRONG_CODE_MS = 10_000;
    private static final long PUSH_DEBOUNCE_MS = 300;
    private static final long IN_USE_RECENT_MS = 10 * 60 * 1000;
    private static final long NSD_UPDATE_MIN_MS = 30_000;

    private static volatile RemoteApiService sInstance;

    private final Handler mMain = new Handler(Looper.getMainLooper());
    private final ExecutorService mWorkers = Executors.newCachedThreadPool(r -> new Thread(r, "HearthRemoteApi"));
    private final Map<Connection, Boolean> mSessions = new ConcurrentHashMap<>();
    private RemotePhones mPhones;
    private RemoteTv mTv;
    private SSLContext mTls;
    private RSAPublicKey mPublicKey;
    private String mTvId;
    private ServerSocket mSessionServer;
    private ServerSocket mPairingServer;
    private volatile boolean mPairing;
    private volatile long mPairingBlockedUntil;
    private NsdManager mNsd;
    private NsdManager.RegistrationListener mRegistration;
    private boolean mAnnouncedInUse;
    private long mAnnouncedAt;
    private long mLastPlayingAt;

    private final Runnable mPush = this::pushState;

    /** Starts the API in the TV owner's user (from Hearth's start, boot and its accessibility service). */
    static void sync(Context context) {
        Context app = context.getApplicationContext();
        if (AgentService.isAgent(app)) return;
        try {
            Intent intent = new Intent(app, RemoteApiService.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                app.startForegroundService(intent);
            } else {
                app.startService(intent);
            }
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't start the remote API: " + e.getClass().getSimpleName());
        }
    }

    /** Something a phone sees changed (the app in front, the screen, what plays): push to open sessions. */
    static void stateChanged() {
        RemoteApiService service = sInstance;
        if (service == null) return;
        service.mMain.removeCallbacks(service.mPush);
        service.mMain.postDelayed(service.mPush, PUSH_DEBOUNCE_MS);
    }

    /** A phone was removed in Settings: close its sessions now. */
    static void phoneRemoved(String fingerprint) {
        RemoteApiService service = sInstance;
        if (service == null) return;
        for (Connection c : service.mSessions.keySet()) {
            if (fingerprint.equals(c.fingerprint)) c.close();
        }
        service.updateAnnouncement();
    }

    @Override
    public void onCreate() {
        super.onCreate();
        startInForeground();
        mPhones = new RemotePhones(this);
        mTv = new RemoteTv(this, RemoteApiService::stateChanged);
        mTv.start();
        sInstance = this;
        mWorkers.execute(this::serve);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startInForeground();
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        sInstance = null;
        mMain.removeCallbacksAndMessages(null);
        unannounce();
        closeQuietly(mSessionServer);
        closeQuietly(mPairingServer);
        for (Connection c : mSessions.keySet()) c.close();
        mTv.stop();
        mWorkers.shutdownNow();
        super.onDestroy();
    }

    private void startInForeground() {
        NotificationManager notifications = getSystemService(NotificationManager.class);
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(new NotificationChannel(CHANNEL,
                    getString(R.string.remote_api_channel_name), NotificationManager.IMPORTANCE_MIN));
            builder = new Notification.Builder(this, CHANNEL);
        } else {
            builder = new Notification.Builder(this);
        }
        Notification notification = builder.setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Hearth TV")
                .setContentText(getString(R.string.remote_api_notification_text))
                .build();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    // --- Servers

    private void serve() {
        try {
            setUpKey();
            mSessionServer = listen(SESSION_PORT);
            mPairingServer = listen(PAIRING_PORT);
        } catch (Exception e) {
            Log.w(TAG, "Remote API not started: " + e);
            return;
        }
        mWorkers.execute(() -> accept(mPairingServer, true));
        mMain.post(this::announce);
        accept(mSessionServer, false);
    }

    private static ServerSocket listen(int port) throws IOException {
        ServerSocket server = new ServerSocket();
        server.setReuseAddress(true);
        server.bind(new InetSocketAddress(port));
        return server;
    }

    private void accept(ServerSocket server, boolean pairing) {
        while (!server.isClosed()) {
            Socket socket;
            try {
                socket = server.accept();
            } catch (IOException e) {
                return;
            }
            if (!LocalNet.isLocal(socket.getInetAddress())) {
                closeQuietly(socket);
                continue;
            }
            mWorkers.execute(() -> {
                if (pairing) pair(socket); else session(socket);
            });
        }
    }

    /** One TLS connection over an accepted socket; the phone's certificate is checked by the caller. */
    private SSLSocket tls(Socket socket, int timeoutMs) throws IOException {
        socket.setSoTimeout(timeoutMs);
        SSLSocket ssl = (SSLSocket) mTls.getSocketFactory().createSocket(
                socket, socket.getInetAddress().getHostAddress(), socket.getPort(), true);
        ssl.setUseClientMode(false);
        ssl.setNeedClientAuth(true);
        ssl.startHandshake();
        return ssl;
    }

    private static X509Certificate peer(SSLSocket ssl) throws IOException {
        Certificate[] chain = ssl.getSession().getPeerCertificates();
        if (chain.length == 0 || !(chain[0] instanceof X509Certificate)) throw new IOException("no client certificate");
        return (X509Certificate) chain[0];
    }

    static String fingerprint(X509Certificate cert) {
        try {
            return Hex.of(MessageDigest.getInstance("SHA-256").digest(cert.getEncoded()));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    // --- Pairing

    private void pair(Socket socket) {
        if (mPairing || SystemClock.elapsedRealtime() < mPairingBlockedUntil) {
            closeQuietly(socket);
            return;
        }
        mPairing = true;
        boolean shown = false;
        try (SSLSocket ssl = tls(socket, PAIRING_TIMEOUT_MS)) {
            X509Certificate phone = peer(ssl);
            if (!(phone.getPublicKey() instanceof RSAPublicKey)) return;
            RemotePolo polo = new RemotePolo((RSAPublicKey) phone.getPublicKey(), mPublicKey,
                    ShareDiscovery.deviceName(this), new SecureRandom());
            InputStream in = ssl.getInputStream();
            OutputStream out = ssl.getOutputStream();
            while (true) {
                byte[] frame = RemoteWire.readFrame(in);
                if (frame == null) return;
                RemotePolo.Step step = polo.handle(frame);
                if (step.reply != null) RemoteWire.writeFrame(out, step.reply);
                if (step.showCode != null) {
                    if (!screenOn()) return; // a sleeping TV can't show its code
                    shown = showCode(polo.clientName(), step.showCode);
                    if (!shown) return;
                }
                if (step.paired) {
                    mPhones.add(fingerprint(phone), polo.clientName(), System.currentTimeMillis());
                    Log.i(TAG, "Paired: " + polo.clientName());
                    mMain.post(this::updateAnnouncement);
                }
                if (step.close) {
                    if (!step.paired) {
                        mPairingBlockedUntil = SystemClock.elapsedRealtime() + AFTER_WRONG_CODE_MS;
                        Log.i(TAG, "Pairing refused: " + polo.clientName());
                    }
                    return;
                }
            }
        } catch (IOException e) {
            Log.i(TAG, "Pairing ended: " + e.getClass().getSimpleName());
        } finally {
            if (shown) clearCode();
            mPairing = false;
        }
    }

    /** The code, in Hearth's pop-up (drawn by its accessibility service); false when it can't be shown. */
    private boolean showCode(String phone, String code) {
        HaNotificationServer.Notification n = new HaNotificationServer.Notification();
        n.title = getString(R.string.remote_api_code_title);
        n.message = getString(R.string.remote_api_code_message, phone,
                code.substring(0, 3) + " " + code.substring(3));
        n.durationSeconds = PAIRING_TIMEOUT_MS / 1000;
        n.position = 4; // center
        n.tag = CODE_TAG;
        return LauncherAccessibilityService.showHaNotification(n);
    }

    private void clearCode() {
        HaNotificationServer.Notification clear = new HaNotificationServer.Notification();
        clear.tag = CODE_TAG;
        clear.message = "clear_notification";
        LauncherAccessibilityService.showHaNotification(clear);
    }

    // --- Sessions

    private final class Connection {
        final SSLSocket ssl;
        final String fingerprint;
        final RemoteSession session;
        final OutputStream out;

        Connection(SSLSocket ssl, String fingerprint, RemoteSession session) throws IOException {
            this.ssl = ssl;
            this.fingerprint = fingerprint;
            this.session = session;
            this.out = ssl.getOutputStream();
        }

        synchronized void send(JSONObject message) {
            try {
                RemoteWire.writeFrame(out, message.toString().getBytes(StandardCharsets.UTF_8));
            } catch (IOException e) {
                close();
            }
        }

        void close() {
            closeQuietly(ssl);
        }
    }

    private void session(Socket socket) {
        Connection connection = null;
        try (SSLSocket ssl = tls(socket, 0)) {
            X509Certificate phone = peer(ssl);
            String fp = fingerprint(phone);
            RemotePhones.Phone paired = mPhones.get(fp);
            if (paired == null) {
                RemoteWire.writeFrame(ssl.getOutputStream(), RemoteSession.error(RemoteSession.NOT_PAIRED, null)
                        .toString().getBytes(StandardCharsets.UTF_8));
                return;
            }
            mPhones.touch(fp, System.currentTimeMillis());
            connection = new Connection(ssl, fp, new RemoteSession(mTv, paired.adult));
            mSessions.put(connection, true);
            Log.i(TAG, "Session: " + paired.name);
            InputStream in = ssl.getInputStream();
            while (true) {
                byte[] frame = RemoteWire.readFrame(in);
                if (frame == null) return;
                // A phone removed in Settings meanwhile is answered no more
                if (mPhones.get(fp) == null) return;
                List<JSONObject> replies = connection.session.handle(frame);
                for (JSONObject reply : replies) {
                    if ("error".equals(reply.optString("t")) && RemoteSession.NOT_ALLOWED.equals(reply.optString("code"))) {
                        Log.i(TAG, "Refused for " + paired.name + ": " + reply.optString("for"));
                    }
                    connection.send(reply);
                }
                if (connection.session.ended()) return;
            }
        } catch (IOException e) {
            // The phone went away
        } finally {
            if (connection != null) {
                mSessions.remove(connection);
                Log.i(TAG, "Session ended");
            }
        }
    }

    /** Main thread: each open session gets the state if it changed for it. */
    private void pushState() {
        if (!mSessions.isEmpty()) {
            mWorkers.execute(() -> {
                for (Connection c : mSessions.keySet()) {
                    JSONObject state = c.session.stateIfChanged();
                    if (state != null) c.send(state);
                }
            });
        }
        updateAnnouncement();
    }

    // --- The key

    private void setUpKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        if (!keyStore.containsAlias(KEY_ALIAS)) {
            KeyPairGenerator generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore");
            // DECRYPT with no padding too: for TLS 1.3's RSA-PSS the TLS library pads itself and asks the keystore for
            // the raw RSA operation
            generator.initialize(new KeyGenParameterSpec.Builder(KEY_ALIAS,
                    KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(2048)
                    .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384,
                            KeyProperties.DIGEST_SHA512)
                    .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1, KeyProperties.SIGNATURE_PADDING_RSA_PSS)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE, KeyProperties.ENCRYPTION_PADDING_RSA_PKCS1)
                    .setCertificateSubject(new X500Principal("CN=hearth-tv"))
                    .setCertificateSerialNumber(BigInteger.ONE)
                    .setCertificateNotBefore(new Date(0))
                    .setCertificateNotAfter(new Date(4102444800000L)) // 2100
                    .build());
            generator.generateKeyPair();
        }
        X509Certificate cert = (X509Certificate) keyStore.getCertificate(KEY_ALIAS);
        mPublicKey = (RSAPublicKey) cert.getPublicKey();
        mTvId = Hex.of(MessageDigest.getInstance("SHA-256").digest(mPublicKey.getEncoded())).substring(0, 16);
        java.security.PrivateKey key = (java.security.PrivateKey) keyStore.getKey(KEY_ALIAS, null);
        mTls = SSLContext.getInstance("TLS");
        // Only this key: the keystore also holds Hearth's other keys (the household's EC key), which a key manager
        // over the whole keystore may pick. Any phone certificate gets through the handshake: pairing needs it to
        // pair, the session checks it's paired
        mTls.init(new javax.net.ssl.KeyManager[]{new OneKey(key, cert)}, new TrustManager[]{new AnyClient()},
                new SecureRandom());
    }

    /** Presents the remote API's own key, whatever else the keystore holds. */
    private static final class OneKey extends javax.net.ssl.X509ExtendedKeyManager {
        private final java.security.PrivateKey mKey;
        private final X509Certificate mCert;

        OneKey(java.security.PrivateKey key, X509Certificate cert) {
            mKey = key;
            mCert = cert;
        }

        @Override public String[] getClientAliases(String keyType, java.security.Principal[] issuers) { return null; }
        @Override public String chooseClientAlias(String[] keyType, java.security.Principal[] issuers, Socket socket) {
            return null;
        }
        @Override public String[] getServerAliases(String keyType, java.security.Principal[] issuers) {
            return new String[]{KEY_ALIAS};
        }
        @Override public String chooseServerAlias(String keyType, java.security.Principal[] issuers, Socket socket) {
            return KEY_ALIAS;
        }
        @Override public String chooseEngineServerAlias(String keyType, java.security.Principal[] issuers,
                javax.net.ssl.SSLEngine engine) {
            return KEY_ALIAS;
        }
        @Override public X509Certificate[] getCertificateChain(String alias) {
            return KEY_ALIAS.equals(alias) ? new X509Certificate[]{mCert} : null;
        }
        @Override public java.security.PrivateKey getPrivateKey(String alias) {
            return KEY_ALIAS.equals(alias) ? mKey : null;
        }
    }

    private static final class AnyClient implements X509TrustManager {
        @Override
        public void checkClientTrusted(X509Certificate[] chain, String authType) throws java.security.cert.CertificateException {
            if (chain == null || chain.length == 0) throw new java.security.cert.CertificateException("no certificate");
            chain[0].checkValidity();
        }

        @Override
        public void checkServerTrusted(X509Certificate[] chain, String authType) throws java.security.cert.CertificateException {
            throw new java.security.cert.CertificateException("a server only");
        }

        @Override
        public X509Certificate[] getAcceptedIssuers() {
            return new X509Certificate[0];
        }
    }

    // --- The announcement (main thread)

    private boolean inUse() {
        if (!mPhones.any() || !screenOn()) return false;
        JSONObject state = mTv.state();
        if (state.optBoolean("playing")) mLastPlayingAt = SystemClock.elapsedRealtime();
        boolean recent = mLastPlayingAt > 0 && SystemClock.elapsedRealtime() - mLastPlayingAt < IN_USE_RECENT_MS;
        String app = state.optString("app", "");
        boolean awayFromHome = !app.isEmpty() && !app.equals(getPackageName())
                && !app.equals(LauncherAccessibilityService.GOOGLE_TV_PACKAGE);
        return recent || awayFromHome;
    }

    private void announce() {
        if (mNsd == null) mNsd = (NsdManager) getSystemService(Context.NSD_SERVICE);
        if (mNsd == null || mTvId == null) return;
        NsdServiceInfo info = new NsdServiceInfo();
        info.setServiceName(ShareDiscovery.deviceName(this));
        info.setServiceType(SERVICE_TYPE);
        info.setPort(SESSION_PORT);
        info.setAttribute("id", mTvId);
        info.setAttribute("n", ShareDiscovery.deviceName(this));
        info.setAttribute("v", String.valueOf(RemoteSession.VERSION));
        info.setAttribute("pp", String.valueOf(PAIRING_PORT));
        mAnnouncedInUse = inUse();
        if (mAnnouncedInUse) info.setAttribute("u", "1");
        mAnnouncedAt = SystemClock.elapsedRealtime();
        mRegistration = new NsdManager.RegistrationListener() {
            @Override public void onServiceRegistered(NsdServiceInfo serviceInfo) {}
            @Override public void onRegistrationFailed(NsdServiceInfo serviceInfo, int errorCode) {
                Log.w(TAG, "Announcement failed: " + errorCode);
            }
            @Override public void onServiceUnregistered(NsdServiceInfo serviceInfo) {}
            @Override public void onUnregistrationFailed(NsdServiceInfo serviceInfo, int errorCode) {}
        };
        try {
            mNsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, mRegistration);
        } catch (RuntimeException e) {
            mRegistration = null;
        }
    }

    private void unannounce() {
        if (mNsd != null && mRegistration != null) {
            try {
                mNsd.unregisterService(mRegistration);
            } catch (RuntimeException ignored) {
            }
        }
        mRegistration = null;
    }

    /** The TXT record's in-use flag changed: announce again, not more often than every 30 s. */
    private void updateAnnouncement() {
        if (mRegistration == null) return;
        if (inUse() == mAnnouncedInUse) return;
        long wait = NSD_UPDATE_MIN_MS - (SystemClock.elapsedRealtime() - mAnnouncedAt);
        if (wait > 0) {
            mMain.postDelayed(this::updateAnnouncement, wait);
            return;
        }
        unannounce();
        announce();
    }

    private boolean screenOn() {
        android.os.PowerManager power = (android.os.PowerManager) getSystemService(Context.POWER_SERVICE);
        return power != null && power.isInteractive();
    }

    private static void closeQuietly(java.io.Closeable closeable) {
        if (closeable == null) return;
        try {
            closeable.close();
        } catch (IOException ignored) {
        }
    }
}
