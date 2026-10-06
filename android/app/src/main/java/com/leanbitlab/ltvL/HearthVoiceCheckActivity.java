package com.leanbitlab.ltvL;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.speech.tts.TextToSpeech;

import java.util.ArrayList;
import java.util.Locale;

/**
 * Answers the text-to-speech settings' "is this engine's voice data installed?" check for Hearth voice. Without it,
 * Google TV's settings put the previous engine back as soon as Hearth voice is chosen.
 */
public class HearthVoiceCheckActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ArrayList<String> voices = new ArrayList<>();
        Locale locale = Locale.getDefault();
        try {
            voices.add(locale.getISO3Language() + "-" + locale.getISO3Country());
        } catch (Exception e) {
            voices.add("eng-USA");
        }
        Intent result = new Intent()
                .putStringArrayListExtra(TextToSpeech.Engine.EXTRA_AVAILABLE_VOICES, voices)
                .putStringArrayListExtra(TextToSpeech.Engine.EXTRA_UNAVAILABLE_VOICES, new ArrayList<>());
        setResult(TextToSpeech.Engine.CHECK_VOICE_DATA_PASS, result);
        finish();
    }
}
