# Games played for vibration

<!-- Made from vibration.json by tools/vibration-md.py: edit the JSON, then run the script. -->

The games played for vibration with a DualSense or DualSense Edge on a Mac. A game is added after a session, from what was felt and what the Wine modules logged, never from what it should do. Each connection has its own result.

Played with MacGameFix's Wine modules in a NotProton runner (CrossOver Preview 27), Steam Input off for the game, unless a result says otherwise. Updated 2026-10-21.

**How a game vibrates** decides what Game Feel needs to give it:

- **Haptics**: the game plays its vibration as audio on the pad's haptic actuators, as on a PS5, and
  usually sets trigger effects too. It needs the Wine modules for the pad's audio output.
- **Motors**: the game writes the pad's rumble itself, and the pad plays it on its actuators the way it
  emulates motors.
- **XInput**: the game rumbles an Xbox-style controller. Game Feel's XInput option gives it the pad as an
  XInput controller, or puts its rumble on the motors.

| Game | Vibration | Cable | Bluetooth |
|---|---|---|---|
| [Marvel's Spider-Man 2](#2651280) | Haptics | Works, DualSense Edge and DualSense (2026-10-19) | Works, DualSense Edge and DualSense (2026-10-19) |
| [F1 23](#2108330) | Haptics | Works, DualSense Edge shown as a DualSense, and DualSense (2026-10-19) | Works, DualSense Edge shown as a DualSense, and DualSense; both at once (2026-10-19) |
| [FINAL FANTASY VII REBIRTH](#2909400) | Haptics | Not played yet | Works (2026-10-21) |
| [CONTROL Resonant](#3669870) | Haptics | Works, DualSense Edge and DualSense (2026-10-19) | Works, DualSense Edge (2026-10-19) |
| [UNCHARTED: Legacy of Thieves Collection](#1659420) | Haptics | Played; how it felt was not recorded (2026-10-19) | Works, DualSense Edge (2026-10-19) |
| [Beast of Reincarnation](#2001760) | Haptics | Works, DualSense Edge and DualSense (2026-10-18) | Works, DualSense Edge (2026-10-19) |
| [Ghost of Tsushima](#2215430) | Haptics | Works, DualSense Edge and DualSense (2026-10-18) | Not played yet |
| [Returnal](#1649240) | Haptics | Works, DualSense Edge and DualSense (2026-10-18) | Not played yet |
| [Mortal Shell II](#2584270) | Motors | Works (2026-10-18) | Not played yet |
| [Mortal Kombat 1](#1971870) | Motors | Works, DualSense Edge (2026-10-20) | Works, DualSense Edge and DualSense (2026-10-20) |
| [Onimusha: Way of the Sword](#2638890) | XInput | Not played yet | Works, DualSense Edge (2026-10-20) |
| [God of War](#1593500) | Motors | Played; which connection was not recorded (2026-10-16) | Played; which connection was not recorded (2026-10-16) |
| [Nioh 3](#3681010) | Haptics | Not played yet | Does not vibrate, DualSense Edge (2026-10-21) |

<a id="2651280"></a>
## Marvel's Spider-Man 2

Insomniac's PC port drives the pad itself, as on a PS5: haptics on the actuators and adaptive triggers, on a cable and over Bluetooth.

- **Status:** Works
- **Technology:** Its own DualSense support, over raw HID. It plays its haptics as audio on the pad's audio output, which it finds by the audio endpoint's container.
- **Features:** Haptics, Adaptive triggers, Touchpad
- **Cable:** Works, DualSense Edge and DualSense (2026-10-19)
- **Bluetooth:** Works, DualSense Edge and DualSense (2026-10-19). The same as on a cable.
- **Settings:** Suggested: full motor power on the Edge and the Edge's haptics at 2x, on a cable and over Bluetooth.
- **Steam app:** 2651280

What was measured:

- It claims the motor power at 0x00 in every report for a standard DualSense, never for an Edge, which keeps its own stored reduction. With the power at full and the haptics at 2x the Edge felt like a standard DualSense.
- It sends the same haptic signal to both pads (a level meter showed the same peaks and RMS for the same moments).
- It reads feature reports 0x09, 0x20 and 0x05 only.
- The touchpad moved the in-game camera (2026-10-20).

<a id="2108330"></a>
## F1 23

Codemasters' game uses Sony's own library for the pad: haptics and trigger effects on a cable and over Bluetooth, with the Edge shown as a standard DualSense.

- **Status:** Works
- **Technology:** Sony's PC library (libScePad), which finds the pad over HID and plays its haptics on the pad's audio output.
- **Features:** Haptics, Adaptive triggers
- **Cable:** Works, DualSense Edge shown as a DualSense, and DualSense (2026-10-19). In a CrossOver Preview bottle an Edge seen as an Edge worked too: buttons, haptics and triggers.
- **Bluetooth:** Works, DualSense Edge shown as a DualSense, and DualSense; both at once (2026-10-19). A standard DualSense felt jerky at 1x and steady at 2x.
- **Settings:** Suggested: the Edge shown as a standard DualSense, and a DualSense's haptics at 2x over Bluetooth. Steam Input off: with it on, the haptics over Bluetooth started and stopped.
- **Steam app:** 2108330

What was measured:

- Under NotProton, as an Edge, the game assigned no buttons ("No preset control scheme", 2026-10-15).
- The level meter showed the same continuous signal leaving the modules with Steam Input on or off.

<a id="2909400"></a>
## FINAL FANTASY VII REBIRTH

Square Enix's PC port plays its haptics on the pad's actuators. Played over Bluetooth: "works very well".

- **Status:** Works
- **Technology:** Its own DualSense support, over raw HID; its haptics play as audio on the pad's audio output.
- **Features:** Haptics
- **Cable:** Not played yet
- **Bluetooth:** Works (2026-10-21). "Works very well." The modules logged the game keeping 20 ms waiting in the Bluetooth haptics output.
- **Steam app:** 2909400

What was measured:

- The modules saw its haptics as audio and its motor power claim.

<a id="3669870"></a>
## CONTROL Resonant

Remedy's game drives the pad itself: haptics and trigger effects, on a cable and over Bluetooth.

- **Status:** Works
- **Technology:** Its own DualSense support, over raw HID; its haptics play as audio on the pad's audio output.
- **Features:** Haptics, Adaptive triggers
- **Cable:** Works, DualSense Edge and DualSense (2026-10-19)
- **Bluetooth:** Works, DualSense Edge (2026-10-19)
- **Steam app:** 3669870

<a id="1659420"></a>
## UNCHARTED: Legacy of Thieves Collection

Its haptics came with the action over Bluetooth once the modules stopped writing copies of its motor reports.

- **Status:** Works
- **Technology:** Not analysed. It plays haptics as audio and sends motor values beside them.
- **Features:** Haptics, Adaptive triggers
- **Cable:** Played; how it felt was not recorded (2026-10-19). The haptics output was open: the game asked for 32 ms of buffer.
- **Bluetooth:** Works, DualSense Edge (2026-10-19). The queue held 29 ms on average and 34 at most; 94 haptics reports every 2 s, nothing dropped.
- **Steam app:** 1659420

What was measured:

- It sends motor values all the time beside its haptics, up to about 18 control reports a second. Over Bluetooth those copies took the room the haptics need, and the haptics restarted 54 times in two minutes, until the modules stopped writing a copy while haptics stream.

<a id="2001760"></a>
## Beast of Reincarnation

Haptics and trigger effects on a cable and over Bluetooth. Its XInput rumble with the modules' XInput option is not played yet.

- **Status:** Works
- **Technology:** Its own DualSense support, over raw HID, for the haptics and triggers; it also rumbles through XInput.
- **Features:** Haptics, Adaptive triggers, XInput rumble
- **Cable:** Works, DualSense Edge and DualSense (2026-10-18). Haptics, on an earlier build of the modules.
- **Bluetooth:** Works, DualSense Edge (2026-10-19). Haptics and triggers, in a CrossOver Preview bottle. Its motors rumbled only with Steam Input on, before the modules had an XInput rumble.
- **Steam app:** 2001760

<a id="2215430"></a>
## Ghost of Tsushima

Haptics on a cable with both pads.

- **Status:** Works
- **Technology:** Its own DualSense support, over raw HID; its haptics play as audio on the pad's audio output.
- **Features:** Haptics
- **Cable:** Works, DualSense Edge and DualSense (2026-10-18). On an earlier build of the modules.
- **Bluetooth:** Not played yet
- **Steam app:** 2215430

<a id="1649240"></a>
## Returnal

Haptics on a cable with both pads.

- **Status:** Works
- **Technology:** Sony's PC library (libScePad).
- **Features:** Haptics
- **Cable:** Works, DualSense Edge and DualSense (2026-10-18). On an earlier build of the modules.
- **Bluetooth:** Not played yet
- **Steam app:** 1649240

<a id="2584270"></a>
## Mortal Shell II

Its rumble and trigger effects kept working with the modules on a cable.

- **Status:** Works
- **Technology:** Its own DualSense support, over raw HID: it drives the motors and the trigger effects itself.
- **Features:** Motors, Adaptive triggers
- **Cable:** Works (2026-10-18). On an earlier build of the modules.
- **Bluetooth:** Not played yet
- **Steam app:** 2584270

<a id="1971870"></a>
## Mortal Kombat 1

Each rumble ends with its hit, on a cable and over Bluetooth, since the Wine modules of 2026-10-20.

- **Status:** Works
- **Technology:** SDL 2 (SDL2.dll 2.32.0), which drives the pad over HID: the rumble as the pad's emulation of motors.
- **Features:** Motors
- **Cable:** Works, DualSense Edge (2026-10-20). 17 rumbles in 74 s, the motors on 6 % of the time, each ended by SDL's stop.
- **Bluetooth:** Works, DualSense Edge and DualSense (2026-10-20). 15 rumbles in 38 s with a DualSense, 34 in 73 s with an Edge, none longer than about 250 ms.
- **Settings:** Rumble on the haptic actuators is optional over Bluetooth.
- **Steam app:** 1971870

What was measured:

- SDL 2 asks an Edge (firmware 0x0217) for the old emulation at half strength and a DualSense from firmware 2.24 for the improved one at full; the modules give the Edge the improved one at twice what SDL wrote, as SDL 3 would.
- SDL ends a rumble with a report that has no rumble bit; over Bluetooth the modules missed it until 2026-10-20, and the rumble went on for the whole fight.

<a id="2638890"></a>
## Onimusha: Way of the Sword

With the pad shown as an XInput controller, its rumble plays on the motors, or on the haptic actuators if chosen.

- **Status:** Works
- **Technology:** XInput only: its executable reads no DualSense, and the store does not list the DualSense for it. Game Feel gives it the pad as an XInput controller.
- **Features:** XInput rumble, Trigger effects from Game Feel
- **Cable:** Not played yet
- **Bluetooth:** Works, DualSense Edge (2026-10-20). 82 rumbles in 218 s, 154 ms each at the median. Rumble on the haptic actuators felt right too.
- **Settings:** The pad as an XInput controller (by the store's rule). Trigger effects for the game from Game Feel: R2 slope, and resist while L2 is pressed.
- **Steam app:** 2638890

<a id="1593500"></a>
## God of War

Shown as a standard DualSense, the Edge rumbles on the motors and gets the game's lightbar. Played before the Wine modules.

- **Status:** Works
- **Technology:** Sony's PC library (libScePad), which does not know the Edge.
- **Features:** Motors, Lightbar
- **Cable:** Played; which connection was not recorded (2026-10-16)
- **Bluetooth:** Played; which connection was not recorded (2026-10-16)
- **Settings:** Suggested: the Edge shown as a standard DualSense.
- **Steam app:** 1593500

What was measured:

- 2026-10-16, NotProton's pad bridge (PR #90): rumble on the motors and the lightbar; the game sets no trigger effects.

<a id="3681010"></a>
## Nioh 3

The game finds the pad and sets its lights and triggers, but never vibrates: Wine registers no audio device with SetupAPI, so the game never finds the pad's output, and with a DualSense it does not fall back to the motors.

- **Status:** Does not vibrate
- **Technology:** Its own DualSense support, over raw HID. It looks for the pad's audio output through SetupAPI: it reads the pad's container (SPDRP_BASE_CONTAINERID) and searches the audio render interfaces for the same one.
- **Features:** Haptics (not working yet), Lightbar
- **Cable:** Not played yet
- **Bluetooth:** Does not vibrate, DualSense Edge (2026-10-21)
- **Settings:** In the game: all five vibration options on, mode Immersive.
- **Steam app:** 3681010

What was measured:

- A Wine trace showed it asking for the audio render interfaces about 70 times a second, and getting an empty list every time.
- It writes the old rumble emulation once, with both motors at 0, and never a motor value after that.
- It creates and releases XAudio2 without ever playing through it.
- A fix that lists Wine's audio outputs with SetupAPI is being tested (patch 0009).

## Adding a game

After a session, add the game to `vibration.json` with what was felt and what the modules logged (Game
Feel's **Seen** column, or Diagnose this game), one result per connection, then run
`tools/vibration-md.py`. A game that needed a setting says which one; if many players need the same one, it
becomes the game's suggested setting in `app/pad-presets.json`.
