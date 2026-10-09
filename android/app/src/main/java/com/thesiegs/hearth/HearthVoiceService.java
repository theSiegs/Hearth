package com.thesiegs.hearth;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.media.AudioFormat;
import android.os.Bundle;
import android.speech.tts.SynthesisCallback;
import android.speech.tts.SynthesisRequest;
import android.speech.tts.TextToSpeech;
import android.speech.tts.TextToSpeechService;
import android.speech.tts.UtteranceProgressListener;
import android.util.Log;
import android.view.accessibility.AccessibilityManager;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * "Hearth voice", a text-to-speech engine for Profile Pairing. Netflix describes its "Who's watching?" screen only
 * by speaking it through the default engine, so while Profile Pairing handles an app's launch this engine hears what
 * that app says and keeps it quiet. Everything else, including the same apps at any other time (for someone using a
 * screen reader), is passed on to Google's voice. In another profile's user, where Hearth runs as that profile's
 * agent, what the app says is relayed to Profile Pairing in Hearth (AgentService).
 */
public class HearthVoiceService extends TextToSpeechService {
    private static final String TAG = "HearthVoice";
    private static final String GOOGLE_TTS = "com.google.android.tts";
    private static final long FORWARD_TIMEOUT_S = 20;

    private TextToSpeech mForward;
    private volatile boolean mForwardReady;
    private volatile boolean mStopped;
    private final Map<String, CountDownLatch> mPending = new ConcurrentHashMap<>();

    @Override
    public void onCreate() {
        super.onCreate();
        try {
            getPackageManager().getPackageInfo(GOOGLE_TTS, 0);
            mForward = new TextToSpeech(this, status -> mForwardReady = status == TextToSpeech.SUCCESS, GOOGLE_TTS);
            mForward.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                @Override
                public void onStart(String utteranceId) {
                }

                @Override
                public void onDone(String utteranceId) {
                    release(utteranceId);
                }

                @Override
                public void onError(String utteranceId) {
                    release(utteranceId);
                }
            });
        } catch (Exception e) {
            Log.i(TAG, "No Google voice to pass speech on to");
        }
    }

    private void release(String utteranceId) {
        CountDownLatch latch = mPending.remove(utteranceId);
        if (latch != null) latch.countDown();
    }

    @Override
    public void onDestroy() {
        if (mForward != null) mForward.shutdown();
        super.onDestroy();
    }

    @Override
    protected int onIsLanguageAvailable(String lang, String country, String variant) {
        return TextToSpeech.LANG_COUNTRY_AVAILABLE;
    }

    @Override
    protected String[] onGetLanguage() {
        Locale locale = Locale.getDefault();
        try {
            return new String[]{locale.getISO3Language(), locale.getISO3Country(), ""};
        } catch (Exception e) {
            return new String[]{"eng", "USA", ""};
        }
    }

    @Override
    protected int onLoadLanguage(String lang, String country, String variant) {
        return TextToSpeech.LANG_COUNTRY_AVAILABLE;
    }

    // One voice for every language. TextToSpeech.setLanguage() asks for the language's default voice and looks for it
    // in the engine's voices; without these overrides the names don't match and apps that check the result (Hulu)
    // think Hearth voice can't speak their language, and stay quiet.
    private static final String VOICE = "hearth";

    @Override
    public String onGetDefaultVoiceNameFor(String lang, String country, String variant) {
        return VOICE;
    }

    @Override
    public java.util.List<android.speech.tts.Voice> onGetVoices() {
        return java.util.Collections.singletonList(new android.speech.tts.Voice(VOICE, Locale.getDefault(),
                android.speech.tts.Voice.QUALITY_NORMAL, android.speech.tts.Voice.LATENCY_NORMAL, false,
                java.util.Collections.emptySet()));
    }

    @Override
    public int onIsValidVoiceName(String voiceName) {
        return VOICE.equals(voiceName) ? TextToSpeech.SUCCESS : TextToSpeech.ERROR;
    }

    @Override
    public int onLoadVoice(String voiceName) {
        return onIsValidVoiceName(voiceName);
    }

    @Override
    protected void onStop() {
        mStopped = true;
    }

    @Override
    protected void onSynthesizeText(SynthesisRequest request, SynthesisCallback callback) {
        mStopped = false;
        CharSequence text = request.getCharSequenceText();
        String caller = getPackageManager().getNameForUid(request.getCallerUid());
        if (ProfilePairingService.isListeningTo(caller)) {
            ProfilePairingService.onSpeech(caller, text != null ? text.toString() : null);
            silence(callback);
            return;
        }
        // In another profile's user (Hearth as its agent): Profile Pairing runs in Hearth, so relay it there
        if (AgentService.isListeningTo(caller)) {
            AgentService.relaySpeech(caller, text != null ? text.toString() : null);
            silence(callback);
            return;
        }
        // The picker apps only talk because Hearth put them in screen-reader mode for a pick, and they don't always
        // hear when it's off again (a first sign-in outlasting the pick, or a kids profile, whose apps Android never
        // tells): unless someone uses a real screen reader, their speech goes nowhere rather than out loud.
        if (ProfilePairingService.needsScreenReaderMode(caller) && !realScreenReaderOn()) {
            silence(callback);
            return;
        }
        if (text == null || !mForwardReady || !forward(text, request, callback)) silence(callback);
    }

    /** A screen reader other than Hearth's own Profile Pairing (TalkBack, say) gives spoken feedback. */
    private boolean realScreenReaderOn() {
        AccessibilityManager manager = (AccessibilityManager) getSystemService(ACCESSIBILITY_SERVICE);
        if (manager == null) return false;
        for (AccessibilityServiceInfo info
                : manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_SPOKEN)) {
            if (info.getResolveInfo() == null || info.getResolveInfo().serviceInfo == null) continue;
            if (!getPackageName().equals(info.getResolveInfo().serviceInfo.packageName)) return true;
        }
        return false;
    }

    private static void silence(SynthesisCallback callback) {
        callback.start(16000, AudioFormat.ENCODING_PCM_16BIT, 1);
        callback.done();
    }

    /** Has Google's voice render the text to a file, then plays that file through this request. */
    private boolean forward(CharSequence text, SynthesisRequest request, SynthesisCallback callback) {
        String id = "hearth-" + System.nanoTime();
        File wav = new File(getCacheDir(), id + ".wav");
        CountDownLatch done = new CountDownLatch(1);
        mPending.put(id, done);
        try {
            mForward.setSpeechRate(request.getSpeechRate() / 100f);
            mForward.setPitch(request.getPitch() / 100f);
            if (mForward.synthesizeToFile(text, new Bundle(), wav, id) != TextToSpeech.SUCCESS) return false;
            if (!done.await(FORWARD_TIMEOUT_S, TimeUnit.SECONDS) || mStopped || !wav.exists()) return false;
            return play(wav, callback);
        } catch (Exception e) {
            Log.w(TAG, "Passing speech on failed", e);
            return false;
        } finally {
            mPending.remove(id);
            //noinspection ResultOfMethodCallIgnored
            wav.delete();
        }
    }

    private boolean play(File wav, SynthesisCallback callback) throws Exception {
        byte[] bytes = new byte[(int) wav.length()];
        try (InputStream in = new FileInputStream(wav)) {
            int read = 0;
            while (read < bytes.length) {
                int n = in.read(bytes, read, bytes.length - read);
                if (n < 0) break;
                read += n;
            }
        }
        ByteBuffer buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
        if (bytes.length < 12 || buf.getInt(0) != 0x46464952 /* RIFF */) return false;
        int pos = 12;
        int channels = 1, rate = 22050, bits = 16, dataStart = -1, dataLength = 0;
        while (pos + 8 <= bytes.length) {
            int chunkId = buf.getInt(pos);
            int size = buf.getInt(pos + 4);
            if (chunkId == 0x20746d66 /* "fmt " */) {
                channels = buf.getShort(pos + 10);
                rate = buf.getInt(pos + 12);
                bits = buf.getShort(pos + 22);
            } else if (chunkId == 0x61746164 /* "data" */) {
                dataStart = pos + 8;
                dataLength = Math.min(size, bytes.length - dataStart);
                break;
            }
            pos += 8 + size + (size & 1);
        }
        if (dataStart < 0 || bits != 16) return false;
        callback.start(rate, AudioFormat.ENCODING_PCM_16BIT, channels);
        int max = callback.getMaxBufferSize();
        for (int off = 0; off < dataLength && !mStopped; off += max) {
            if (callback.audioAvailable(bytes, dataStart + off, Math.min(max, dataLength - off))
                    != TextToSpeech.SUCCESS) {
                break;
            }
        }
        callback.done();
        return true;
    }
}
