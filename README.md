# DicType

**Speak. Watch it type.**

This repository now uses a plain build flow powered by Python so it no longer depends on Swift or Xcode for the build step. The current build entry point is [build.py](build.py), which produces a simple build artifact under [build/dist](build/dist).

macOS Dictation drops finished words onto the screen all at once. DicType doesn't. It listens, then types what you said one character at a time — with a natural cadence, tiny hesitations, and the occasional human-like hitch that makes it feel lived-in rather than robotic.

<br>

```
        you say ──▶  "the cow jumped"

        screen  ──▶  t h e   c o w   j u m p e d
                     ↑
                     one key at a time, at 62 WPM
```

<br>

|              |                                                            |
| ------------ | ---------------------------------------------------------- |
| **Platform** | macOS 13 Ventura or newer                                  |
| **Privacy**  | Speech is transcribed on your Mac. Nothing is uploaded.    |
| **Works in** | Notes, Slack, Xcode, Mail, browsers, anywhere you can type |
| **Cost**     | Free, MIT licensed                                         |

---

## Install

### The easy way

1. Go to the **[Releases](releases)** page.
2. Download the latest **[DicType.dmg](releases/latest)** installer from the releases page.
3. Open it and drag **DicType** onto the **Applications** shortcut.
4. Double-click DicType.

That's it. No security warnings, no right-clicking, no terminal. Official releases are signed and notarized by Apple, while local builds work without a developer certificate.

The app opens to a polished setup walk-through with clear icons, rich status feedback, and a refined visual style that feels more like a modern desktop utility than a basic prototype. The packaged app also ships with a custom icon so it looks polished in the Dock, Applications folder, and Finder.

<br>

### Building it yourself

Build the project from the repository root with:

```bash
python3 build.py
```

This produces a build artifact in [build/dist](build/dist). The build no longer requires Swift or Xcode.

You can also run:

```bash
make
```

---

## Releasing a signed build

_Maintainer only. Requires an Apple Developer Program membership._

**One-time setup**

1. Create a **Developer ID Application** certificate — Xcode → Settings → Accounts → Manage Certificates → **+**, or at [developer.apple.com](https://developer.apple.com/account/resources/certificates).
2. Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords.
3. Store notarization credentials in your keychain:

```bash
xcrun notarytool store-credentials "dictype" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "abcd-efgh-ijkl-mnop"
```

Your Team ID is on the [membership page](https://developer.apple.com/account#MembershipDetailsCard).

**Every release**

```bash
bash release.sh
```

The script compiles, signs with the hardened runtime, notarizes, staples the ticket, builds a drag-to-Applications DMG, notarizes that too, and verifies Gatekeeper acceptance. Notarization takes one to five minutes per submission.

Output: `DicType.dmg` (the drag-to-Applications installer) and `DicType.zip` (the app archive), both ready to attach to a GitHub release.

```bash
gh release create v1.0.0 DicType.dmg DicType.zip \
   --title "DicType 1.0.0" \
   --notes "Speak, and watch it type."
```

**Note on sandboxing.** DicType is signed with the hardened runtime but is deliberately _not_ sandboxed. A sandboxed app cannot post keyboard events into other applications, which is the entire function of this tool. That rules out Mac App Store distribution; direct download is the only channel.

---

## First launch

DicType opens to a clean setup experience with three beautifully styled cards. Each one updates as you approve it, and the interface walks you through the process with a calm, premium feel and recognizable iconography throughout.

|     | Permission             | Why                                   |
| --- | ---------------------- | ------------------------------------- |
| 1   | **Microphone**         | To hear you                           |
| 2   | **Speech Recognition** | To turn sound into words, on this Mac |
| 3   | **Accessibility**      | To type into your other apps          |

Accessibility is the fussy one. macOS opens System Settings and you flip the switch next to DicType by hand. If the switch won't stay enabled, quit DicType entirely (`Cmd + Q`) and open it again.

Once all three are green, the setup screen disappears and DicType is ready to use.

---

## Using it

1. Open DicType.
2. Press the big **microphone** button.
3. Click into any text field — Notes, a browser, wherever.
4. Talk.

Press the button again to stop.

### Two controls

**Speed** — 25 to 110 words per minute. 40 reads as a slow typist, 62 as an average one, and 90 feels fast.

**Looseness** — how irregular the rhythm is. At `0.00` it feels mechanical, around `0.42` it feels human, and above `0.60` it becomes noticeably erratic.

---

## What to expect

**Text stays on screen and builds naturally.** DicType keeps the visible transcript stable as you speak, so words don't vanish or get erased mid-stream. It still feels dynamic, with uneven pacing and tiny pauses that make the typing feel human.

**Typing trails your voice.** Speech can move quickly, but DicType preserves a human rhythm rather than chasing it perfectly. That makes the output feel more natural, even when the recognition stream is changing in real time.

**Keystrokes land wherever the cursor is.** Click into your target field before you start talking, or your words will go somewhere you didn't intend.

---

## Troubleshooting

<details>
<summary><b>The setup screen won't turn green</b></summary>

Quit DicType completely with `Cmd + Q` — closing the window isn't enough — then reopen it. macOS sometimes doesn't hand a running app its new permissions.

</details>

<details>
<summary><b>It hears me but nothing gets typed</b></summary>

Accessibility permission. System Settings → Privacy & Security → Accessibility. DicType must be listed **and** switched on. Listed-but-off is the usual cause.

</details>

<details>
<summary><b>Nothing is heard at all</b></summary>

Check that the right microphone is selected in System Settings → Sound → Input, and that its level moves when you speak.

</details>

<details>
<summary><b>I want a different language</b></summary>

Open the app configuration in the repository and adjust the language settings there before rebuilding with `python3 build.py`.

</details>

---

## How it works

1. `AVAudioEngine` captures the microphone.
2. `SFSpeechRecognizer` returns partial transcripts as you speak.
3. Each transcript is compared to the last confirmed text, and only the newly spoken characters are queued so the visible output stays stable.
4. The queue drains on a human-like timing model with uneven pauses, longer gaps after punctuation or word boundaries, and the occasional micro-hitch.
5. Each character is posted to the system as a `CGEvent`, indistinguishable from a real keypress.

---

## Roadmap

- [ ] Menu bar mode with a global push-to-talk hotkey
- [ ] Migration to `SpeechAnalyzer` for lower latency
- [ ] Per-app speed profiles

---

## License

MIT — see [LICENSE](LICENSE).
