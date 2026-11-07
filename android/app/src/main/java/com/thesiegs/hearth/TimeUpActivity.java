package com.thesiegs.hearth;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

/**
 * The exported entry for {@link TimeUpRequest#ACTION} (no permission: it only brings up Hearth's home and its time's up
 * card). In the TV owner's user Hearth handles it itself; in a kids profile's user (Hearth there is the agent) it goes
 * to Hearth in the owner's user over the agent's connection. Nothing shows of this screen.
 */
public class TimeUpActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Intent intent = getIntent();
        if (intent != null && TimeUpRequest.ACTION.equals(intent.getAction())) {
            String packageName = TimeUpRequest.cleanPackage(intent.getStringExtra(TimeUpRequest.EXTRA_PACKAGE));
            // An app this user doesn't have names nothing
            if (packageName != null && !TimeUpRequest.installed(this, packageName)) packageName = null;
            String group = TimeUpRequest.cleanGroup(intent.getStringExtra(TimeUpRequest.EXTRA_GROUP));
            if (AgentService.isAgent(this)) {
                if (!AgentService.relayTimeUp(packageName, group)) {
                    // The agent normally runs all the time; started now, the next ask gets through
                    AgentService.start(this);
                    Log.i("HearthTimeUp", "Hearth isn't connected: can't show the time's up card from this profile");
                }
            } else {
                TimeUpRequest.show(this, packageName, group);
            }
        }
        finish();
    }
}
