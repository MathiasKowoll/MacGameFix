# Games played for vibration

<!-- Made from vibration.json by tools/vibration-md.py: edit the JSON, then run the script. -->

The games played for vibration with a DualSense or DualSense Edge on a Mac. A game is added after a session, from what was felt and what the Wine modules logged, never from what it should do. Each test names its controller and its connection.

Played with MacGameFix's Wine modules in a NotProton runner (CrossOver Preview 27), Steam Input off for the game, unless a result says otherwise. Updated 2026-10-25.

**How a game vibrates** decides what Game Feel needs to give it:

- **Haptics**: the game plays its vibration as audio on the pad's haptic actuators, as on a PS5, and
  usually sets trigger effects too. It needs the Wine modules for the pad's audio output.
- **Motors**: the game writes the pad's rumble itself, and the pad plays it on its actuators the way it
  emulates motors.
- **XInput**: the game rumbles an Xbox-style controller. Game Feel's XInput option gives it the pad as an
  XInput controller, or puts its rumble on the motors.

**Library** is how the game reaches the pad: Sony libScePad, SDL, Raw HID, XInput or DirectInput, the names
Game Feel's **It Vibrates…** fills in from the game's folder. When a game rumbles the pad another way than it
reads it, the column names the way it rumbles and the entry says so, as for Mortal Kombat 11. A Haptics game
plays its haptics as audio on the pad's output, whatever its library.

| Game | Vibration | Library | Cable | Bluetooth |
|---|---|---|---|---|
| [Marvel's Spider-Man 2](#2651280) | Haptics | Raw HID | DualSense Edge: Works (2026-10-19); DualSense: Works (2026-10-19) | DualSense Edge: Works (2026-10-19); DualSense: Works (2026-10-19) |
| [F1 23](#2108330) | Haptics | Sony libScePad | DualSense Edge shown as a DualSense: Works (2026-10-19); DualSense: Works (2026-10-19); DualSense Edge: Works (2026-10-19) | DualSense Edge shown as a DualSense: Works (2026-10-19); DualSense: Works (2026-10-19) |
| [FINAL FANTASY VII REBIRTH](#2909400) | Haptics | Raw HID | Not played yet | DualSense Edge: Works (2026-10-21) |
| [CONTROL Resonant](#3669870) | Haptics | Raw HID | DualSense Edge: Works (2026-10-18); DualSense: Works (2026-10-19) | DualSense Edge: Works (2026-10-19) |
| [UNCHARTED: Legacy of Thieves Collection](#1659420) | Haptics |  | Controller not recorded: Played; how it felt was not recorded (2026-10-19) | DualSense Edge: Works (2026-10-19) |
| [Beast of Reincarnation](#2001760) | Haptics | Raw HID | DualSense Edge: Works (2026-10-18); DualSense: Works (2026-10-18) | DualSense Edge: Works (2026-10-19) |
| [Ghost of Tsushima](#2215430) | Haptics | Raw HID | DualSense Edge: Works (2026-10-18); DualSense: Works (2026-10-18) | Not played yet |
| [Returnal](#1649240) | Haptics | Sony libScePad | DualSense Edge: Works (2026-10-18); DualSense: Works (2026-10-18) | Not played yet |
| [Mortal Shell II](#2584270) | Motors | Raw HID | Controller not recorded: Works (2026-10-18) | Not played yet |
| [Mortal Kombat 1](#1971870) | Motors | SDL | DualSense Edge: Works (2026-10-20) | DualSense: Works (2026-10-20); DualSense Edge: Works (2026-10-20) |
| [Onimusha: Way of the Sword](#2638890) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-20) |
| [God of War](#1593500) | Motors | Sony libScePad | DualSense Edge shown as a DualSense: Works (2026-10-16, connection not recorded) | DualSense Edge shown as a DualSense: Works (2026-10-16, connection not recorded) |
| [Resonance: A Plague Tale Legacy](#2713000) | Haptics | Raw HID | Not played yet | DualSense Edge: Works (2026-10-21) |
| [Resident Evil Requiem](#3764200) | Motors | Sony libScePad | Not played yet | DualSense Edge: Works (2026-10-21) |
| [PRAGMATA](#3357650) | Motors | Sony libScePad | Not played yet | DualSense Edge: Works (2026-10-21) |
| [Crysis Remastered](#1715130) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-21) |
| [Crysis 2 Remastered](#2096600) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-21); DualSense Edge shown as a DualShock 4: Does not vibrate (2026-10-22); DualSense Edge shown as a DualShock 4: Does not vibrate (2026-10-22) |
| [Crysis 3 Remastered](#2096610) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-21) |
| [SILENT HILL 2](#2124490) | Haptics | Raw HID | Not played yet | DualSense Edge: Works (2026-10-21) |
| [Revenge of the Savage Planet](#2787320) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-21) |
| [TIEBREAK - GRAND SLAM EDITION](#2264340) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-21) |
| [Teenage Mutant Ninja Turtles: Splintered Fate](#2996040) | XInput | XInput | Not played yet | DualSense Edge: Partly (2026-10-21) |
| [Nioh 3](#3681010) | Haptics | Raw HID | DualSense Edge: Does not vibrate (2026-10-21) | DualSense Edge: Does not vibrate (2026-10-21); DualSense Edge shown as a DualSense: Does not vibrate (2026-10-21); DualSense Edge shown as a DualSense: Works (2026-10-22) |
| [NINJA GAIDEN 4](#2627260) | Motors | Raw HID | Not played yet | DualSense Edge shown as a DualSense: Works (2026-10-22) |
| [Mortal Kombat 11](#976310) | Motors | Sony libScePad | DualSense Edge shown as a DualShock 4: Works (2026-10-22) | DualSense Edge shown as a DualSense: Does not vibrate (2026-10-21); DualSense Edge shown as a DualSense: Does not vibrate (2026-10-21); DualSense Edge shown as a DualSense: Does not vibrate (2026-10-21); DualSense Edge shown as a DualShock 4: Works (2026-10-22); DualSense shown as a DualShock 4: Works (2026-10-22) |
| [Crash Bandicoot 4: It's About Time](#1378990) | Motors | Raw HID | Not played yet | DualSense Edge: Works (2026-10-23); DualSense Edge shown as a DualShock 4: Works (2026-10-23) |
| [Crash Bandicoot N. Sane Trilogy](#731490) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-23); DualSense Edge shown as a DualShock 4: Does not vibrate (2026-10-23); DualSense Edge shown as a DualShock 4: Does not vibrate (2026-10-23) |
| [God of War Ragnarök](#2322010) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-23); DualSense Edge shown as a DualSense: Works (2026-10-23) |
| [Persona 5 Strikers](#1382330) | XInput | XInput | Not played yet | DualSense Edge shown as a DualShock 4: Does not vibrate (2026-10-23); DualSense Edge shown as a DualShock 4: Works (2026-10-23) |
| [The Last of Us Part I](#1888930) | Haptics | Raw HID | Not played yet | DualSense Edge: Works (2026-10-25) |

<a id="2651280"></a>
## Marvel's Spider-Man 2

Insomniac's PC port drives the pad itself, as on a PS5: haptics on the actuators and adaptive triggers, on a cable and over Bluetooth.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Its own DualSense support, over raw HID. It plays its haptics as audio on the pad's audio output, which it finds by the audio endpoint's container.
- **Features:** Haptics, Adaptive triggers, Touchpad
- **Settings:** Suggested: full motor power on the Edge and the Edge's haptics at 2x, on a cable and over Bluetooth.
- **Steam app:** 2651280

Tested:

- DualSense Edge, Cable: Works (2026-10-19)
- DualSense, Cable: Works (2026-10-19)
- DualSense Edge, Bluetooth: Works (2026-10-19). The same as on a cable.
- DualSense, Bluetooth: Works (2026-10-19). The same as on a cable at 1x.

What was measured:

- It claims the motor power at 0x00 in every report for a standard DualSense, never for an Edge, which keeps its own stored reduction. With the power at full and the haptics at 2x the Edge felt like a standard DualSense.
- It sends the same haptic signal to both pads (a level meter showed the same peaks and RMS for the same moments).
- It reads feature reports 0x09, 0x20 and 0x05 only.
- The touchpad moved the in-game camera (2026-10-20).

<a id="2108330"></a>
## F1 23

Codemasters' game uses Sony's own library for the pad: haptics and trigger effects on a cable and over Bluetooth, with the Edge shown as a standard DualSense.

- **Status:** Works
- **Library:** Sony libScePad
- **Technology:** Sony's PC library (libScePad), which finds the pad over HID and plays its haptics on the pad's audio output.
- **Features:** Haptics, Adaptive triggers
- **Settings:** Suggested: the Edge shown as a standard DualSense, and a DualSense's haptics at 2x over Bluetooth. Steam Input off: with it on, the haptics over Bluetooth started and stopped.
- **Steam app:** 2108330

Tested:

- DualSense Edge shown as a DualSense, Cable: Works (2026-10-19)
- DualSense, Cable: Works (2026-10-19)
- DualSense Edge, Cable: Works (2026-10-19). In a CrossOver Preview bottle, seen as an Edge: buttons, haptics and triggers.
- DualSense Edge shown as a DualSense, Bluetooth: Works (2026-10-19)
- DualSense, Bluetooth: Works (2026-10-19). Jerky at 1x, steady at 2x.

What was measured:

- Under NotProton, as an Edge, the game assigned no buttons ("No preset control scheme", 2026-10-15).
- The level meter showed the same continuous signal leaving the modules with Steam Input on or off.

<a id="2909400"></a>
## FINAL FANTASY VII REBIRTH

Square Enix's PC port plays its haptics on the pad's actuators. Played over Bluetooth: "works very well".

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Its own DualSense support, over raw HID; its haptics play as audio on the pad's audio output.
- **Features:** Haptics
- **Steam app:** 2909400

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21). "Works very well." The modules logged the game playing haptics on the Bluetooth Edge's output, keeping 20 ms waiting.

What was measured:

- The modules saw its haptics as audio and its motor power claim.

<a id="3669870"></a>
## CONTROL Resonant

Remedy's game drives the pad itself: haptics and trigger effects, on a cable and over Bluetooth.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Its own DualSense support, over raw HID; its haptics play as audio on the pad's audio output.
- **Features:** Haptics, Adaptive triggers
- **Steam app:** 3669870

Tested:

- DualSense Edge, Cable: Works (2026-10-18)
- DualSense, Cable: Works (2026-10-19)
- DualSense Edge, Bluetooth: Works (2026-10-19)

<a id="1659420"></a>
## UNCHARTED: Legacy of Thieves Collection

Its haptics came with the action over Bluetooth once the modules stopped writing copies of its motor reports.

- **Status:** Works
- **Technology:** Not analysed. It plays haptics as audio and sends motor values beside them.
- **Features:** Haptics, Adaptive triggers
- **Steam app:** 1659420

Tested:

- Controller not recorded, Cable: Played; how it felt was not recorded (2026-10-19). The haptics output was open: the game asked for 32 ms of buffer.
- DualSense Edge, Bluetooth: Works (2026-10-19). The queue held 29 ms on average and 34 at most; 94 haptics reports every 2 s, nothing dropped.

What was measured:

- It sends motor values all the time beside its haptics, up to about 18 control reports a second. Over Bluetooth those copies took the room the haptics need, and the haptics restarted 54 times in two minutes, until the modules stopped writing a copy while haptics stream.

<a id="2001760"></a>
## Beast of Reincarnation

Haptics and trigger effects on a cable and over Bluetooth. Its XInput rumble with the modules' XInput option is not played yet.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Its own DualSense support, over raw HID, for the haptics and triggers; it also rumbles through XInput.
- **Features:** Haptics, Adaptive triggers, XInput rumble
- **Steam app:** 2001760

Tested:

- DualSense Edge, Cable: Works (2026-10-18). Haptics, on an earlier build of the modules.
- DualSense, Cable: Works (2026-10-18). Haptics, on an earlier build of the modules.
- DualSense Edge, Bluetooth: Works (2026-10-19). Haptics and triggers, in a CrossOver Preview bottle. Its motors rumbled only with Steam Input on, before the modules had an XInput rumble.

<a id="2215430"></a>
## Ghost of Tsushima

Haptics on a cable with both pads.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Its own DualSense support, over raw HID; its haptics play as audio on the pad's audio output.
- **Features:** Haptics
- **Steam app:** 2215430

Tested:

- DualSense Edge, Cable: Works (2026-10-18). On an earlier build of the modules.
- DualSense, Cable: Works (2026-10-18). On an earlier build of the modules.

<a id="1649240"></a>
## Returnal

Haptics on a cable with both pads.

- **Status:** Works
- **Library:** Sony libScePad
- **Technology:** Sony's PC library (libScePad).
- **Features:** Haptics
- **Steam app:** 1649240

Tested:

- DualSense Edge, Cable: Works (2026-10-18). On an earlier build of the modules.
- DualSense, Cable: Works (2026-10-18). On an earlier build of the modules.

<a id="2584270"></a>
## Mortal Shell II

Its rumble and trigger effects kept working with the modules on a cable.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Its own DualSense support, over raw HID: it drives the motors and the trigger effects itself.
- **Features:** Motors, Adaptive triggers
- **Steam app:** 2584270

Tested:

- Controller not recorded, Cable: Works (2026-10-18). On an earlier build of the modules.

<a id="1971870"></a>
## Mortal Kombat 1

Each rumble ends with its hit, on a cable and over Bluetooth, since the Wine modules of 2026-10-20.

- **Status:** Works
- **Library:** SDL
- **Technology:** SDL 2 (SDL2.dll 2.32.0), which drives the pad over HID: the rumble as the pad's emulation of motors.
- **Features:** Motors
- **Settings:** Rumble on the haptic actuators is optional over Bluetooth.
- **Steam app:** 1971870

Tested:

- DualSense Edge, Cable: Works (2026-10-20). 17 rumbles in 74 s, the motors on 6 % of the time, each ended by SDL's stop.
- DualSense, Bluetooth: Works (2026-10-20). 15 rumbles in 38 s, about 250 ms each.
- DualSense Edge, Bluetooth: Works (2026-10-20). 34 rumbles in 73 s, none longer than 239 ms.

What was measured:

- SDL 2 asks an Edge (firmware 0x0217) for the old emulation at half strength and a DualSense from firmware 2.24 for the improved one at full; the modules give the Edge the improved one at twice what SDL wrote, as SDL 3 would.
- SDL ends a rumble with a report that has no rumble bit; over Bluetooth the modules missed it until 2026-10-20, and the rumble went on for the whole fight.

<a id="2638890"></a>
## Onimusha: Way of the Sword

With the pad shown as an XInput controller, its rumble plays on the motors, or on the haptic actuators if chosen.

- **Status:** Works
- **Library:** XInput
- **Technology:** XInput only: its executable reads no DualSense, and the store does not list the DualSense for it. Game Feel gives it the pad as an XInput controller.
- **Features:** XInput rumble, Trigger effects from Game Feel
- **Settings:** The pad as an XInput controller (by the store's rule). Trigger effects for the game from Game Feel: R2 slope, and resist while L2 is pressed.
- **Steam app:** 2638890

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-20). 82 rumbles in 218 s, 154 ms each at the median. Rumble on the haptic actuators felt right too.

<a id="1593500"></a>
## God of War

Shown as a standard DualSense, the Edge rumbles on the motors and gets the game's lightbar. Played before the Wine modules.

- **Status:** Works
- **Library:** Sony libScePad
- **Technology:** Sony's PC library (libScePad), which does not know the Edge.
- **Features:** Motors, Lightbar
- **Settings:** Suggested: the Edge shown as a standard DualSense.
- **Steam app:** 1593500

Tested:

- DualSense Edge shown as a DualSense, connection not recorded: Works (2026-10-16). On NotProton's pad bridge (PR #90), before the Wine modules: rumble on the motors and the lightbar.

What was measured:

- 2026-10-16, NotProton's pad bridge (PR #90): rumble on the motors and the lightbar; the game sets no trigger effects.

<a id="2713000"></a>
## Resonance: A Plague Tale Legacy

Haptics over Bluetooth with the defaults.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Asobo's own engine, with its own DualSense code on Sony's pad code, over raw HID. Its haptics play as audio on the pad's output through Wwise Motion.
- **Features:** Haptics
- **Steam app:** 2713000

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21). "Vibrated very well."

What was measured:

- The modules logged the game opening the Bluetooth haptics output and keeping 16 to 44 ms waiting in it.
- The Bluetooth haptics queue sat at its 64 ms cap, with about 1.6 s of every 2 s of haptics dropped; it did not show in the feel.

<a id="3764200"></a>
## Resident Evil Requiem

Over Bluetooth it vibrates with Bluetooth as a cable turned off for the game: it then sees a Bluetooth pad with no audio output and vibrates it itself. With the pad shown as wired it sets the trigger effects, never opens the pad's audio output and leaves the motors at zero.

- **Status:** Works
- **Library:** Sony libScePad
- **Technology:** Capcom's RE Engine, with Sony's pad library linked in, over raw HID. It chooses between its own audio vibration device, when it believes the pad's audio output exists, and the motors, and it tells Bluetooth from a cable.
- **Features:** Motors, Adaptive triggers
- **Settings:** Game Feel: Bluetooth as a cable off for this game.
- **Steam app:** 3764200

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21). Bluetooth as a cable off for the game.

What was measured:

- With Bluetooth as a cable on (the default), the modules logged trigger effects and motor values always at 0, and no haptics output opened (2026-10-21).
- It vibrated the same way on NotProton's direct mode, without an audio output (2026-10-16).
- Not played on a cable with the modules yet.

<a id="3357650"></a>
## PRAGMATA

Over Bluetooth it vibrates with Bluetooth as a cable turned off for the game, as Resident Evil Requiem does.

- **Status:** Works
- **Library:** Sony libScePad
- **Technology:** Capcom's RE Engine, with Sony's pad library linked in, over raw HID, the same as Resident Evil Requiem.
- **Features:** Motors, Adaptive triggers
- **Settings:** Game Feel: Bluetooth as a cable off for this game.
- **Steam app:** 3357650

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21). Bluetooth as a cable off for the game.

What was measured:

- On NotProton's older bridge, with the pad's audio output visible, it set trigger effects and did not vibrate, and on a cable it did not vibrate either (2026-10-16).
- Not played on a cable with the modules yet.

<a id="1715130"></a>
## Crysis Remastered

It reads an Xbox-style controller. Game Feel gives it the pad as an XInput controller and puts its rumble on the actuators over Bluetooth; the trigger effects come from Game Feel.

- **Status:** Works
- **Library:** XInput
- **Technology:** CryEngine, reading an XInput controller only.
- **Features:** XInput rumble, Trigger effects from Game Feel
- **Settings:** Game Feel: the pad as an XInput controller (by the store's rule), its rumble on the actuators over Bluetooth, R2 slope and L2 vibrate.
- **Steam app:** 1715130

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21). On NotProton's Rosetta runner. Steam Input was on for the game (Steam's default for a game the store does not list for the DualSense).

What was measured:

- The modules logged the game's motor values and its rumble played on the actuators over Bluetooth, with no haptics dropped.

<a id="2096600"></a>
## Crysis 2 Remastered

It reads an Xbox-style controller. Game Feel gives it the pad as an XInput controller and puts its rumble on the actuators over Bluetooth; the trigger effects come from Game Feel.

- **Status:** Works
- **Library:** XInput. It ships Sony's library, so It Vibrates… fills in Sony libScePad; its rumble goes through XInput.
- **Technology:** CryEngine, reading the pad as an XInput controller. It ships Sony's pad library, which was not needed.
- **Features:** XInput rumble, Trigger effects from Game Feel
- **Settings:** Game Feel: the pad as an XInput controller (by the store's rule), its rumble on the actuators over Bluetooth, R2 slope and L2 vibrate.
- **Steam app:** 2096600

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21). On NotProton's Rosetta runner. Steam Input was on for the game (Steam's default for a game the store does not list for the DualSense).
- DualSense Edge shown as a DualShock 4, Bluetooth: Does not vibrate (2026-10-22). PlayStation prompts; the game opened the pad through its Sony code and sent no rumble to it.
- DualSense Edge shown as a DualShock 4, Bluetooth: Does not vibrate (2026-10-22). With XInput's rumble beside the identity: nothing written to XInput either.

What was measured:

- The modules logged the game's motor values and its rumble played on the actuators over Bluetooth, with no haptics dropped.
- Shown as a DualShock 4 (2026-10-22) the game's copy of Sony's library opened the pad and the game showed PlayStation prompts, but it sent no rumble, to the DualShock 4 or to XInput's motors beside it: it rumbles only the XInput controller it plays with. It stays an XInput controller.

<a id="2096610"></a>
## Crysis 3 Remastered

It reads an Xbox-style controller. Game Feel gives it the pad as an XInput controller and puts its rumble on the actuators over Bluetooth; the trigger effects come from Game Feel.

- **Status:** Works
- **Library:** XInput
- **Technology:** CryEngine, reading the pad as an XInput controller.
- **Features:** XInput rumble, Trigger effects from Game Feel
- **Settings:** Game Feel: the pad as an XInput controller (by the store's rule), its rumble on the actuators over Bluetooth, R2 slope and L2 vibrate.
- **Steam app:** 2096610

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21). On NotProton's FEX runner. Steam Input was on for the game (set in Steam).

What was measured:

- The modules logged the game's motor values and its rumble played on the actuators over Bluetooth, with no haptics dropped.

<a id="2124490"></a>
## SILENT HILL 2

Haptics over Bluetooth with the defaults.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Unreal Engine 5.1 with Epic's older Sony controller plugin, over raw HID. Its haptics play as audio on the pad's output through Wwise Motion.
- **Features:** Haptics
- **Steam app:** 2124490

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21)

What was measured:

- The modules logged the game opening the Bluetooth haptics output and playing haptics on it, and some motor values too.
- The Bluetooth haptics queue sat at its 64 ms cap, with about 1.6 s of every 2 s of haptics dropped, as in Resonance: A Plague Tale Legacy.

<a id="2787320"></a>
## Revenge of the Savage Planet

It reads an Xbox-style controller; Game Feel gives it the pad as an XInput controller, and its rumble goes to the motors.

- **Status:** Works
- **Library:** XInput
- **Technology:** Unreal Engine 5.3, reading an XInput controller only.
- **Features:** XInput rumble
- **Settings:** Game Feel: the pad as an XInput controller.
- **Steam app:** 2787320

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21). Works with the Edge.

What was measured:

- The modules logged the game rumbling the pad's motors through XInput.

<a id="2264340"></a>
## TIEBREAK - GRAND SLAM EDITION

It reads an Xbox-style controller; Game Feel gives it the pad as an XInput controller, and its rumble goes to the motors.

- **Status:** Works
- **Library:** XInput
- **Technology:** Big Ant Studios' own engine, reading XInput and DirectInput.
- **Features:** XInput rumble
- **Settings:** Game Feel: the pad as an XInput controller (by the store's rule).
- **Steam app:** 2264340

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21). Works well (the user). Xbox prompts.

What was measured:

- The modules logged the game's motor values rising and falling through XInput for the whole session.
- It shows Xbox prompts with the DualSense: its controller table lists the DualShock 4, not the DualSense.

<a id="2996040"></a>
## Teenage Mutant Ninja Turtles: Splintered Fate

As an XInput controller it vibrates, but the game sees the controller twice. With XInput off it sees one controller, shown as a DualSense, and does not vibrate.

- **Status:** Partly
- **Library:** XInput
- **Technology:** Super Evil Megacorp's engine. It reads the pad through XInput and through a path of its own, where it shows a DualSense.
- **Features:** XInput rumble
- **Settings:** Game Feel: XInput off for this game, against the duplicate.
- **Steam app:** 2996040

Tested:

- DualSense Edge, Bluetooth: Partly (2026-10-21). As an XInput controller: vibration, and the controller twice. XInput off: one controller, no vibration.

What was measured:

- With the pad as an XInput controller the modules logged the game rumbling it through XInput.
- Next: XInput's rumble on the motors alone (the defaults), so the game keeps its own DualSense and rumbles through XInput.

<a id="3681010"></a>
## Nioh 3

Haptics over Bluetooth, "vibrated very well", with three Wine module patches that are not released yet (0009, 0010, 0011) and the Edge shown as a standard DualSense with XInput off. Without the patches it finds no output and never vibrates, in Immersive or Functional mode.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Its own DualSense support, over raw HID. It finds the pad's audio output through SetupAPI (the pad's container, SPDRP_BASE_CONTAINERID, against the audio render interfaces) and plays its haptics there through an XAudio2 mastering voice opened on that interface's path.
- **Features:** Haptics, Lightbar
- **Settings:** Game Feel: the Edge shown as a DualSense, XInput off. In the game: vibration mode Immersive.
- **Steam app:** 3681010

Tested:

- DualSense Edge, Bluetooth: Does not vibrate (2026-10-21)
- DualSense Edge shown as a DualSense, Bluetooth: Does not vibrate (2026-10-21)
- DualSense Edge, Cable: Does not vibrate (2026-10-21)
- DualSense Edge shown as a DualSense, Bluetooth: Works (2026-10-22). Patches 0009-0011, XInput off, Immersive: "vibrated very well".

What was measured:

- 0009 lists Wine's audio outputs as SetupAPI interfaces with their containers; 0010 returns SPDRP_BASE_CONTAINERID as a WCHAR string from the A function, as Windows does; with both the game finds the pad's output.
- It then creates an XAudio2 mastering voice with that output's path as its device id; 0011 makes XAudio2 open that device (Wine ignored the id and used the default output).
- With the Edge shown as an Edge, or with XInput's rumble on the motors (the pad's id gains "&Col01"), it found the output and never created the voice.
- The modules logged the haptics output opened on the Bluetooth pad, peaks up to 1.12, the queue at about 29 ms and nothing dropped.
- In Functional mode, and without the patches, it never sends a motor value: a game that sees a DualSense plays only haptics.
- Proton on Linux shows the same failure without these pieces: the triggers work and the haptic vibration does not (ValveSoftware/Proton#9473).

<a id="2627260"></a>
## NINJA GAIDEN 4

Its own DualSense code drives the pad's motors, once it is shown a standard DualSense and the pad is a single HID device. With the Edge shown as an Edge, or with XInput's rumble on the motors (which adds a collection, so the pad's id gains "&Col01"), its code does not take the pad: no controller at all.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Its own pad code over raw HID (its executable is encrypted; its imports match Nioh 3's), plus XInput and DirectInput.
- **Features:** Motors
- **Settings:** Game Feel: the Edge shown as a DualSense, XInput off. Steam Input off.
- **Steam app:** 2627260

Tested:

- DualSense Edge shown as a DualSense, Bluetooth: Works (2026-10-22). XInput off: controls and vibration.

What was measured:

- With the defaults, and with the Edge shown as a DualSense but XInput's rumble on the motors, the game read the pad's reports 0x09, 0x20 and 0x05 and asked once for the old rumble emulation with both motors at 0, and the controller did nothing.
- As an XInput controller it played, with Xbox prompts, and did not vibrate.
- With the Edge shown as a DualSense and XInput off, the modules logged the game rumbling the pad's motors through its own code.
- With Bluetooth as a cable off too, the controller did not work: the game read the pad's report 0x05, which switches a Bluetooth DualSense to its full report, and the modules saw nothing from it afterwards.

<a id="976310"></a>
## Mortal Kombat 11

With the pad shown as a DualShock 4 the game's Sony library opens it and the game rumbles it, on a cable and over Bluetooth. Shown as a DualSense it plays with the right controls and PlayStation prompts but never vibrates.

- **Status:** Works
- **Library:** Sony libScePad. Its input is read through DirectInput.
- **Technology:** NetherRealm's engine (the PC port by QLOC). It reads the pad through DirectInput with its own table and sends its rumble to Sony's library (scePadSetVibration). The library it ships (2017) opens only a USB DualShock 4, so the rumble reaches a DualSense only when the pad is shown to the game as one.
- **Features:** Motors, PlayStation button prompts
- **Settings:** Game Feel: the pad shown as a DualShock 4 (patch 0013, in MacGameFix 1.5.6 and later). Steam Input off.
- **Steam app:** 976310

Tested:

- DualSense Edge shown as a DualSense, Bluetooth: Does not vibrate (2026-10-21). XInput off, with Steam Input still on for the game. Controls and PlayStation prompts right.
- DualSense Edge shown as a DualSense, Bluetooth: Does not vibrate (2026-10-21). XInput's rumble on the motors, Steam Input off: no vibration request reached the modules in 3 minutes.
- DualSense Edge shown as a DualSense, Bluetooth: Does not vibrate (2026-10-21). The pad also as an XInput controller, Steam Input off: still no vibration request.
- DualSense Edge shown as a DualShock 4, Bluetooth: Works (2026-10-22). Vibrated (the user); 34 motor rises in the log, up to 0xff.
- DualSense Edge shown as a DualShock 4, Cable: Works (2026-10-22). Vibrated (the user); 13 motor rises in the log, both motors up to 0xff.
- DualSense shown as a DualShock 4, Bluetooth: Works (2026-10-22). Vibrated (the user); 40 motor rises in the log, up to 0xff.

What was measured:

- Shown as a DualShock 4, the game's library read the pad's reports 0x12, 0xa3 and 0x02 and set 0x14, all answered by the modules, then wrote the DualShock 4's output 0x05 with its motors; the modules turned it into the DualSense's.
- With the Edge shown as a DualSense, XInput off, on the motors or as a controller, the game sent no vibration request at all.
- No light bar write was seen in the session.

<a id="1378990"></a>
## Crash Bandicoot 4: It's About Time

Shown as a DualShock 4 it shows PlayStation buttons and rumbles the motors. As an XInput controller it rumbles too, with Xbox buttons; the game lets you choose its button prompts in its own settings.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Unreal Engine 4.24. It reads an XInput controller, and a DualShock 4 with its own code over HID: shown as one, the game reads the pad's DualShock 4 reports itself and rumbles it.
- **Features:** Motors, PlayStation button prompts
- **Settings:** Game Feel: the pad shown as a DualShock 4, XInput off. Steam Input off.
- **Steam app:** 1378990

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-23). As an XInput controller: vibrates (the user), Xbox prompts; 41 motor rises through XInput.
- DualSense Edge shown as a DualShock 4, Bluetooth: Works (2026-10-23). PlayStation prompts and vibration (the user); 16 motor rises, written by the game to the DualShock 4.

What was measured:

- Shown as a DualShock 4, the game read the DualShock 4's feature reports 0x12 and 0xa3, answered by the modules, then wrote its motors itself: 16 rises in two and a half minutes, up to 0xe6.
- As an XInput controller it rumbled through XInput, with Xbox button prompts: 41 rises in four minutes.

<a id="731490"></a>
## Crash Bandicoot N. Sane Trilogy

As an XInput controller it rumbles, with Xbox button prompts; the game has no setting for its prompts. Shown as a DualShock 4 it shows PlayStation buttons and does not vibrate. Which one is the player's choice: vibration as an XInput controller (the setting kept here), or PlayStation buttons as a DualShock 4.

- **Status:** Works
- **Library:** XInput
- **Technology:** Vicarious Visions' engine. It reads XInput and DirectInput, and rumbles only an XInput controller. A DualShock 4 seen through DirectInput is its PS4 controller type, with PlayStation prompts, but it never rumbles one.
- **Features:** XInput rumble
- **Settings:** Game Feel: the pad as an XInput controller (by the store's rule). Steam Input off. For PlayStation buttons without vibration: the pad shown as a DualShock 4.
- **Steam app:** 731490

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-23). As an XInput controller: vibrates (the user), Xbox prompts; 834 motor rises in five minutes through XInput.
- DualSense Edge shown as a DualShock 4, Bluetooth: Does not vibrate (2026-10-23). XInput off: PlayStation prompts, no vibration request in the log.
- DualSense Edge shown as a DualShock 4, Bluetooth: Does not vibrate (2026-10-23). XInput's rumble on the motors beside it: PlayStation prompts, and still no vibration request.

What was measured:

- Shown as a DualShock 4 the controls and the PlayStation prompts were right, and the game sent no vibration at all: none to the pad, and none to XInput's rumble on the motors, which the modules had ready beside it.
- Its executable classifies controllers (ECONTROLLERTYPE_PS4) and imports only XInputGetState and XInputSetState from XInput, so it cannot see a Sony pad behind XInput.

<a id="2322010"></a>
## God of War Ragnarök

With Steam Input on for the game, it shows PlayStation buttons and vibrates: Steam reads the pad, gives the game its controller and sends the game's rumble back to the pad's motors. With Steam Input off, as an XInput controller, it vibrates with Xbox buttons. No adaptive triggers or haptics either way: those come from Sony's SDK, which does not run under Wine.

- **Status:** Works
- **Library:** XInput. With Steam Input on, Steam reads the pad and gives the game its controller and button type.
- **Technology:** Its executable carries Sony's library (libScePad: adaptive triggers, haptics) and loads it through the PlayStation PC SDK, but under Wine Steam answers that it runs on a Steam Deck, and the game never loads the SDK. It then reads the controller as Steam presents it: with Steam Input on, through Steam's own XInput controller and Steam Input's controller type, which names a DualSense; with Steam Input off, through XInput alone.
- **Features:** XInput rumble, PlayStation button prompts
- **Settings:** Steam Input ON for this game (an exception to Steam Input off): Game Feel with the Edge shown as a standard DualSense and XInput's rumble (the store's rule). Without Steam Input: the pad as an XInput controller, with Xbox buttons.
- **Steam app:** 2322010

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-23). Steam Input off, the pad as an XInput controller: vibrates well (the user), Xbox prompts, no adaptive triggers.
- DualSense Edge shown as a DualSense, Bluetooth: Works (2026-10-23). Steam Input on: PlayStation prompts and vibration (the user); 232 motor rises through Steam's controller.

What was measured:

- Steam Input on: the input came through Steam's controller (130 reports a second reached the pad's HID device), and the game's rumble came back through XInput to the pad's motors: 232 rises in four and a half minutes, given the improved rumble emulation by the modules.
- Steam Input off, XInput's rumble only: the game had no controls, since it reads XInput and XInput then has only the motors.
- Steam Input off, the pad as an XInput controller: 347 motor rises in three minutes, Xbox buttons.
- With Wine's hidraw off (NotProton's Disable hidraw) the pad reached the game through SDL as an XInput controller, with Xbox buttons; the Wine modules took no part.
- Under NotProton, Steam's IsSteamRunningOnSteamDeck answers yes, so the game skips PsPcSdk and libScePad; told no, the SDK's initialisation fails (0x8a800111) and the game exits (measured 2026-10-16).

<a id="1382330"></a>
## Persona 5 Strikers

Shown as a DualShock 4 with XInput's rumble on the motors beside it, it shows PlayStation buttons and vibrates. Shown as a DualShock 4 with XInput off it shows PlayStation buttons and does not vibrate: its rumble has nowhere to go.

- **Status:** Works
- **Library:** XInput
- **Technology:** Koei Tecmo's engine (ktgl). It reads XInput and DirectInput and rumbles only through XInput (XInputSetState); it has no HID code of its own. A DualShock 4 seen through DirectInput gets PlayStation prompts.
- **Features:** XInput rumble, PlayStation button prompts
- **Settings:** Game Feel: the pad shown as a DualShock 4, XInput set to its rumble on the motors. Steam Input off. Its movies need the fix in the catalog.
- **Steam app:** 1382330

Tested:

- DualSense Edge shown as a DualShock 4, Bluetooth: Does not vibrate (2026-10-23). XInput off: PlayStation prompts, no vibration request in four and a half minutes.
- DualSense Edge shown as a DualShock 4, Bluetooth: Works (2026-10-23). XInput's rumble on the motors beside it: PlayStation prompts and vibration (the user); 11 motor rises through XInput.

What was measured:

- Shown as a DualShock 4 the game never read the DualShock 4's feature reports and never wrote to it: it reads the pad through DirectInput and rumbles only through XInput.
- With XInput's rumble on the motors beside the DualShock 4, the game rumbled through XInput: 11 motor rises in under a minute of play, up to 0xc8 heavy and 0xff light.

<a id="1888930"></a>
## The Last of Us Part I

Haptics, trigger effects and the motors, as on a PS5.

- **Status:** Works
- **Library:** Raw HID
- **Technology:** Naughty Dog's engine, with its own DualSense code over HID: it reads the pad's feature reports itself, writes its output report, and plays its haptics as audio on the pad's output.
- **Features:** Haptics, Trigger effects, Motors
- **Settings:** Game Feel: every game's settings. Steam Input off.
- **Steam app:** 1888930

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-25). Works perfectly (the user): haptics on the pad's output, trigger effects and motors, all seen in the modules' log.

What was measured:

- The game read the pad's feature reports 0x09, 0x20 and 0x05, opened the Bluetooth haptics output (48000 Hz, a 10 ms period) and played haptics on it, set trigger effects, and wrote the motors itself, up to 0xff on the heavy one.

## Adding a game

Played a game and felt it vibrate? In MacGameFix, open **Game Feel**, click the game, then
**It Vibrates…**: it saves the game's report and opens the "A game that vibrates" form with the game, the
controller, the connection, what the pad was shown to the game as and the library filled in. One report is
one test: one controller on one connection.

After a session, or from such a report, add the game to `vibration.json` with what was felt and what the
modules logged (Game Feel's **Seen** column, or Diagnose this game), one test per controller and connection
(a report's Controller, Connection, Shown to the game as and Result become a test's `controller`,
`connection`, `shownAs` and `result`), then run `tools/vibration-md.py`. A game that needed a setting says
which one; if many players need the same one, it becomes the game's suggested setting in
`app/pad-presets.json`.
