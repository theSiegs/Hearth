# Leads

From the stopped research runs of 2026-10-08 (cloud session). Summaries are of what each page said; they aren't
verified.

## Read

- **SmartTube #4132** (2024-11-21, Chromecast with Google TV, Android TV 12),
  https://github.com/yuliskov/SmartTube/issues/4132: a sideloaded app doesn't appear in the child profile's "Manage
  apps" even with "Allow third party apps" on in Family Link; installing from the child profile's browser fails. Closed,
  no workaround.
- **SmartTube #3426** (2024-04-12, Chromecast with Google TV), https://github.com/yuliskov/SmartTube/issues/3426:
  "Unable to find explicit activity class" opening SmartTube in a kids profile. No workaround.
- **SmartTube #5131** (2025-11-27), https://github.com/yuliskov/SmartTube/issues/5131: Google disabled SmartTube on a
  MiBox as a dangerous app (signing certificate revoked by its author). Relevant only as a Play Protect risk for forks.
- **MindTheGapps 16.0.0-arm64 #6** (2026-07-16), https://github.com/MindTheGapps/16.0.0-arm64/issues/6:
  `cmd overlay lookup android android:string/config_defaultSupervisionProfileOwnerComponent` →
  `com.google.android.gms/.kids.account.receiver.ProfileOwnerReceiver`; supervision runs in process
  `com.google.android.gms.supervision` (TimeLimitCheckingIntentOperation, SupervisionDataStoreOperations).
- **Dhizuku #34**, https://github.com/iamr0s/Dhizuku/issues/34: a supervised user already has that profile owner, so
  no other device/profile owner can be set.
- **Android developer verification FAQ** (updated 2026-09-30),
  https://developer.android.com/developer-verification/guides/faq: adb installs exempt; outside Play, enforcement only
  on phones/tablets in select regions from 2026-09-30, global rollout 2027; "advanced flow" for unverified apps; free
  limited-distribution account for up to 20 devices without ID.
- **UAD-ng #100** (2023-12-19), https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/issues/100:
  Google TV package names (launcherx, tungsten.setupwraith, katniss, tvlauncher).
- **jellyfin-androidtv discussion #4528** (2025-03 to 2026-04): app logins carry across Android TV profiles; no fix.
- Not relevant on reading: krzywdzin/owntv-pl (in-app kids mode only), itcon-pty-au/pickwick (Downloader install
  steps), Silo-Server/silo-android #333, rifting/chronolink (a child-side time-limit bypass tool; no mechanics).

## Couldn't be read from the cloud session (DNS failures) — read these next

- https://xdaforums.com/t/guide-run-side-loaded-apps-on-child-profile.4411683/
- https://xdaforums.com/t/how-to-youtube-kids-and-other-sideloaded-google-services-apps-on-a-child-profile.3839714/
- https://xdaforums.com/t/google-tv-my-sideloaded-apps-cant-sideload.4710564/
- https://www.googlenestcommunity.com/t5/Streaming/How-to-get-sideloaded-app-to-kids-profile/m-p/376656
- https://www.googlenestcommunity.com/t5/Streaming/Kids-profile-Apps-suspended/m-p/127630
- https://www.googlenestcommunity.com/t5/Streaming/Google-TV-streamer-kids-profiles-and-Family-Link/m-p/667442
- https://www.googlenestcommunity.com/t5/Streaming/YouTube-App-Missing-from-Kid-Profile-on-Brand-New-Google-TV-Streamer/m-p/746876
- https://jellywatch.app/blog/jellywatch-android-tv-kids-profile-linked-profiles-home-assistant
- https://enemyhideout.com/2025/09/hacking-your-android-tv/
- https://tvusage.app/permissions-with-adb (and gist https://gist.github.com/balachandarlinks/46be5ffa675ae3dbedc27b5f8e2f84b8:
  `pm grant --user <USER_ID>` / `appops set --user <USER_ID>` for another profile)
- https://support.google.com/families/answer/10491112 , https://support.google.com/families/answer/7103028 ,
  https://support.google.com/googletv/answer/10070481
- https://forum.f-droid.org/t/f-droid-with-family-link-solved/11953
- https://whitelist.video/blog/apps-from-unknown-sources-family-link
- https://support.bark.us/en/articles/13461179-install-or-update-bark-on-androids-supervised-with-family-link
- https://www.androidpolice.com/google-tv-set-up-kids-profile-how-to/ , https://9to5google.com/2021/03/09/google-tv-kids-profiles/
- Reddit (r/GoogleTV, r/AndroidTV, r/FamilyLink, r/onn, r/SmartTube) — www.reddit.com was blocked.
