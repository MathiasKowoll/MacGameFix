# Games played for vibration

<!-- Made from vibration.json by tools/vibration-md.py: edit the JSON, then run the script. -->

The games played for vibration with a DualSense or DualSense Edge on a Mac. A game is added after a session, from what was felt and what the Wine modules logged, never from what it should do. Each test names its controller and its connection.

Played with MacGameFix's Wine modules in a NotProton runner (CrossOver Preview 27), Steam Input off for the game, unless a result says otherwise. Updated 2026-10-21.

**How a game vibrates** decides what Game Feel needs to give it:

- **Haptics**: the game plays its vibration as audio on the pad's haptic actuators, as on a PS5, and
  usually sets trigger effects too. It needs the Wine modules for the pad's audio output.
- **Motors**: the game writes the pad's rumble itself, and the pad plays it on its actuators the way it
  emulates motors.
- **XInput**: the game rumbles an Xbox-style controller. Game Feel's XInput option gives it the pad as an
  XInput controller, or puts its rumble on the motors.

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
| [Crysis 2 Remastered](#2096600) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-21) |
| [Crysis 3 Remastered](#2096610) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-21) |
| [SILENT HILL 2](#2124490) | Haptics | Raw HID | Not played yet | DualSense Edge: Works (2026-10-21) |
| [Revenge of the Savage Planet](#2787320) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-21) |
| [TIEBREAK - GRAND SLAM EDITION](#2264340) | XInput | XInput | Not played yet | DualSense Edge: Works (2026-10-21) |
| [Teenage Mutant Ninja Turtles: Splintered Fate](#2996040) | XInput | XInput | Not played yet | DualSense Edge: Partly (2026-10-21) |
| [Nioh 3](#3681010) | Haptics | Raw HID | DualSense Edge: Does not vibrate (2026-10-21) | DualSense Edge: Does not vibrate (2026-10-21); DualSense Edge shown as a DualSense: Does not vibrate (2026-10-21) |
| [NINJA GAIDEN 4](#2627260) | None yet | Raw HID | Not played yet | DualSense Edge: Does not vibrate (2026-10-21) |
| [Mortal Kombat 11](#976310) | None yet | DirectInput | Not played yet | DualSense Edge shown as a DualSense: Does not vibrate (2026-10-21); DualSense Edge shown as a DualSense: Does not vibrate (2026-10-21); DualSense Edge shown as a DualSense: Does not vibrate (2026-10-21) |

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
- **Library:** XInput
- **Technology:** CryEngine, reading the pad as an XInput controller. It ships Sony's pad library, which was not needed.
- **Features:** XInput rumble, Trigger effects from Game Feel
- **Settings:** Game Feel: the pad as an XInput controller (by the store's rule), its rumble on the actuators over Bluetooth, R2 slope and L2 vibrate.
- **Steam app:** 2096600

Tested:

- DualSense Edge, Bluetooth: Works (2026-10-21). On NotProton's Rosetta runner. Steam Input was on for the game (Steam's default for a game the store does not list for the DualSense).

What was measured:

- The modules logged the game's motor values and its rumble played on the actuators over Bluetooth, with no haptics dropped.

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

The game finds the pad and sets its lights and triggers, but never vibrates. With two SetupAPI patches of the modules (0009 and 0010, not released) it finds the pad's audio output, asks for its path and stops searching, but never opens it.

- **Status:** Does not vibrate
- **Library:** Raw HID
- **Technology:** Its own DualSense support, over raw HID. It looks for the pad's audio output through SetupAPI: it reads the pad's container (SPDRP_BASE_CONTAINERID) and searches the audio render interfaces for the same one.
- **Features:** Haptics (not working yet), Lightbar
- **Settings:** In the game: all five vibration options on, mode Immersive.
- **Steam app:** 3681010

Tested:

- DualSense Edge, Bluetooth: Does not vibrate (2026-10-21)
- DualSense Edge shown as a DualSense, Bluetooth: Does not vibrate (2026-10-21)
- DualSense Edge, Cable: Does not vibrate (2026-10-21)

What was measured:

- Without patch 0009 it asked for the audio render interfaces about 70 times a second and got an empty list every time.
- With 0009 and 0010 it finds the output whose container is the pad's, asks for its path once and stops; it never opens it, as audio, through MMDevice or as a file.
- It writes the old rumble emulation once, with both motors at 0, and never a motor value after that; its pad thread sets XInput's vibration to 0 every frame.
- It creates and releases XAudio2 without ever playing through it.
- Neither the Edge shown as a DualSense nor XInput off for the game changed it.
- Proton on Linux shows the same: the triggers work and the haptic vibration does not (ValveSoftware/Proton#9473).

<a id="2627260"></a>
## NINJA GAIDEN 4

With the defaults the controller does nothing. As an XInput controller it plays, with Xbox prompts, but does not vibrate: the game reads the pad, asks once for the old rumble emulation with both motors at 0 and never sends a motor value, as Nioh 3 does.

- **Status:** Does not vibrate
- **Library:** Raw HID
- **Technology:** Its own pad code over raw HID (its executable is encrypted; its imports match Nioh 3's), plus XInput and DirectInput.
- **Features:** 
- **Settings:** Game Feel: the pad as an XInput controller.
- **Steam app:** 2627260

Tested:

- DualSense Edge, Bluetooth: Does not vibrate (2026-10-21). As an XInput controller: controls and Xbox prompts, no vibration.

What was measured:

- With Bluetooth as a cable off as well, the controller did not work: the game read the pad's report 0x05, which switches a Bluetooth DualSense to its full report, and the modules saw nothing from it afterwards.

<a id="976310"></a>
## Mortal Kombat 11

With XInput off and the Edge shown as a DualSense it plays with the right controls and PlayStation prompts ("never played so well"), but it does not vibrate. With the pad also given as an XInput controller (the store's rule) the buttons were assigned wrong.

- **Status:** Does not vibrate
- **Library:** DirectInput
- **Technology:** NetherRealm's engine (the PC port by QLOC). It reads the pad through DirectInput with its own table, which has the DualSense's id (054C:0CE6) and not the Edge's; the Sony library it ships (2017) knows neither pad.
- **Features:** PlayStation button prompts
- **Settings:** Game Feel: the Edge shown as a DualSense; XInput off, on the motors or as a controller gives the same. Steam Input off.
- **Steam app:** 976310

Tested:

- DualSense Edge shown as a DualSense, Bluetooth: Does not vibrate (2026-10-21). XInput off, with Steam Input still on for the game. Controls and PlayStation prompts right.
- DualSense Edge shown as a DualSense, Bluetooth: Does not vibrate (2026-10-21). XInput's rumble on the motors, Steam Input off: no vibration request reached the modules in 3 minutes.
- DualSense Edge shown as a DualSense, Bluetooth: Does not vibrate (2026-10-21). The pad also as an XInput controller, Steam Input off: still no vibration request.

What was measured:

- No motor value and no XInput vibration in the modules' log, in either session.
- Its executable sends its rumble to XInput (XInputSetState) or to Sony's library (scePadSetVibration), and creates no DirectInput force-feedback effect. The Sony library it ships (2017) does not open a DualSense, and with the pad read through DirectInput the game wrote nothing to XInput, even with the pad there as an XInput controller too.

## Adding a game

After a session, add the game to `vibration.json` with what was felt and what the modules logged (Game
Feel's **Seen** column, or Diagnose this game), one test per controller and connection, then run
`tools/vibration-md.py`. A game that needed a setting says which one; if many players need the same one, it
becomes the game's suggested setting in `app/pad-presets.json`.
