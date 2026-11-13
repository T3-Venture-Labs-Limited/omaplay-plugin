# Changelog

## 0.1.0 (2026-11-13)

First public release.

- Bar widget showing what omaplay is playing; click for the mini player, middle-click to pause.
- Mini player with seek bar, transport, volume, loop and shuffle state, fully usable from the keyboard.
- IPC target `omaplay` for keybindings: `togglePanel`, `playPause`, `next`, `previous`, `volumeUp`, `volumeDown`,
  `seek <seconds>` and `status`.
- Talks to omaplay only over MPRIS; ignores every other player, including the official VLC.
