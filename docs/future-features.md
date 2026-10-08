# Future features

Ideas to keep, not yet designed or scheduled.

## Network entry in Settings

A Settings item that opens the TV's network settings (Wi-Fi, VPN, maybe more). Which settings it covers is still
open. There is no network icon in the top bar, and none is planned.

Until this is designed, the network code stays as it is: `NetworkService`'s network state, the `event_network`
channel and the Java side behind it (`NetworkEventStreamHandler`, `NetworkUtils`, `NetworkChangeReceiver`,
`PhoneStateListenerImpl`, `TelephonyCallbackImpl`), and `FLauncherChannel.openWifiSettings` /
`openVpnSettings`. The "Network indicator" switch in Settings → Home screen → Status bar (`status_bar_panel_page.dart`) does
nothing since the top-bar icon was removed in aa6ca8f. Remove or repurpose it when this entry is built.
