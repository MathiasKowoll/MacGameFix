# Games played for vibration

Every game here was played with a DualSense or DualSense Edge on a Mac, with MacGameFix's Wine modules in a
NotProton runner unless a row says otherwise, and Steam Input off for the game. A row says what was played,
when, and how the game drives the pad; a game is added after a session, never from what it should do.

**How a game vibrates** decides what Game Feel needs to give it:

- **Haptics**: the game plays its vibration as audio on the pad's haptic actuators, as on a PS5, and usually
  sets trigger effects too. It needs the Wine modules for the pad's audio output, on a cable or over Bluetooth.
- **Motors**: the game writes the pad's rumble itself (over HID, as SDL does), and the pad plays it on its
  actuators the way it emulates motors.
- **XInput**: the game rumbles an Xbox-style controller. Game Feel's XInput option gives it the pad as an XInput
  controller, or puts its rumble on the motors.

## Works

| Game | How it vibrates | Played with | Date | Notes |
|---|---|---|---|---|
| Marvel's Spider-Man 2 | Haptics, trigger effects | Edge and DualSense, cable and Bluetooth | 2026-10-19 | Suggested settings: full motor power on the Edge, the Edge's haptics at 2x, which makes it feel like a standard DualSense |
| F1 23 | Haptics, trigger effects (Sony's library) | Edge shown as a DualSense, and DualSense, cable and Bluetooth | 2026-10-19 | Suggested: the Edge shown as a standard DualSense (under NotProton, as an Edge, it assigned no buttons), and a DualSense's haptics at 2x over Bluetooth |
| FINAL FANTASY VII REBIRTH | Haptics | Bluetooth | 2026-10-21 | "Works very well"; the modules saw its haptics as audio and its motor power |
| CONTROL Resonant | Haptics, trigger effects | Edge over Bluetooth, DualSense on a cable | 2026-10-19 | |
| UNCHARTED: Legacy of Thieves Collection | Haptics, trigger effects | Edge over Bluetooth | 2026-10-19 | The haptics came with the action once the modules stopped writing copies of its motor reports over Bluetooth |
| Beast of Reincarnation | Haptics, trigger effects | Edge over Bluetooth, in a CrossOver Preview bottle | 2026-10-19 | It also rumbles through XInput: in that session the motors rumbled only with Steam Input on. With the modules' XInput option it is not played yet |
| Ghost of Tsushima | Haptics | Edge and DualSense on a cable | 2026-10-18 | Bluetooth not played yet |
| Returnal | Haptics | Edge and DualSense on a cable | 2026-10-18 | Bluetooth not played yet |
| Mortal Shell II | Motors, trigger effects | On a cable | 2026-10-18 | |
| Mortal Kombat 1 | Motors (SDL 2) | DualSense over Bluetooth; Edge over Bluetooth and on a cable | 2026-10-20 | Since the modules of 2026-10-20: each rumble ends with its hit, and an Edge gets the strength SDL 3 would give it |
| Onimusha: Way of the Sword | XInput | Edge over Bluetooth | 2026-10-20 | The pad as an XInput controller (the store does not list the DualSense for it). Rumble on the haptic actuators felt right too |
| God of War | Motors | Edge shown as a DualSense | 2026-10-16 | Played on NotProton's pad bridge (PR #90), before the Wine modules. Suggested: the Edge shown as a standard DualSense, since its Sony library does not know the Edge |

## Does not vibrate

| Game | What it does | Played with | Date | Status |
|---|---|---|---|---|
| Nioh 3 | Finds the pad over HID and sets its lights and triggers, but never writes a motor value nor opens the pad's audio output. Its executable carries PS5-style "advanced vibration" and plays its sound through XAudio2 | Edge over Bluetooth | 2026-10-21 | Being measured. Two gaps in Wine could stop it: its XAudio2 opens the default output whatever device a game asks for, and it lists no audio devices for a game that looks them up through SetupAPI |

## Adding a game

After a session, add a row with what was felt and what the modules logged (Game Feel's **Seen** column, or
Diagnose this game). A game that needed a setting to work says which one; if many players need the same one,
it becomes the game's suggested setting in `app/pad-presets.json`.
