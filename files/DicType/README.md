# DicType

**Speak. Watch it type.**

macOS Dictation drops finished words onto the screen all at once. DicType doesn't. It listens, then types what you said one character at a time — with the pauses, rhythm, and hesitations of an actual person at a keyboard.

<br>

```
        you say ──▶  "the cow jumped"

        screen  ──▶  t h e   c o w   j u m p e d
                     ↑
                     one key at a time, at 62 WPM
```

<br>

| | |
|---|---|
| **Platform** | macOS 13 Ventura or newer |
| **Privacy** | Speech is transcribed on your Mac. Nothing is uploaded. |
| **Works in** | Notes, Slack, Xcode, Mail, browsers, anywhere you can type |
| **Cost** | Free, MIT licensed |

---

## Install

### The easy way

1. Go to the **[Releases](../../releases)** page.
2. Download **DicType.dmg**.
3. Open it and drag **DicType** onto the **Applications** shortcut.
4. Double-click DicType.

That's it. No security warnings, no right-clicking, no terminal. DicType is signed and notarized by Apple.

The app opens and walks you through the rest.

<br>

### Building it yourself

If there's no release yet, or you'd rather compile from source:

```bash
git clone https://github.com/taylordrew4u2/dictype.git
cd dictype
bash build-app.sh
```

`DicType.app` appears in the folder. Drag it to Applications.

Requires Xcode Command Line Tools. If you don't have them:

```bash
xcode-select --install
```

---

## Releasing a signed build

*Maintainer only. Requires an Apple Developer Program membership.*

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

Output: `DicType.dmg` and `DicType.zip`, both ready to attach to a GitHub release.

```bash
gh release create v1.0.0 DicType.dmg DicType.zip \
   --title "DicType 1.0.0" \
   --notes "Speak, and watch it type."
```

**Note on sandboxing.** DicType is signed with the hardened runtime but is deliberately *not* sandboxed. A sandboxed app cannot post keyboard events into other applications, which is the entire function of this tool. That rules out Mac App Store distribution; direct download is the only channel.

---

## First launch

DicType opens to a setup screen with three cards. Each one turns green as you approve it. The screen watches for changes on its own — no refreshing, no restarting.

| | Permission | Why |
|---|---|---|
| 1 | **Microphone** | To hear you |
| 2 | **Speech Recognition** | To turn sound into words, on this Mac |
| 3 | **Accessibility** | To type into your other apps |

Accessibility is the fussy one. macOS opens System Settings and you flip the switch next to DicType by hand. If the switch won't hold, quit DicType entirely (`Cmd + Q`) and open it again.

Once all three are green, the setup screen disappears for good.

---

## Using it

1. Open DicType.
2. Press the big **microphone** button.
3. Click into any text field — Notes, a browser, wherever.
4. Talk.

Press the button again to stop.

### Two dials

**Speed** — 25 to 110 words per minute. 40 reads as a slow typist, 62 as an average one, 90 as fast.

**Looseness** — how irregular the rhythm is. At `0.00` it's a metronome. Around `0.42` it reads as human. Above `0.60` it looks like someone typing after a long night.

---

## What to expect

**Text rewrites itself mid-sentence.** Speech recognizers revise their guesses as you keep talking. You'll see characters backspace and retype. That's real-time transcription, not a bug.

**Typing trails your voice.** Speech runs 500–800 characters per minute. Typing at 62 WPM runs about 310. DicType speeds up automatically when it falls behind and eases off once it catches up, but a gap during long stretches of talking is unavoidable.

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

Open `Sources/DicType/DictationEngine.swift`, change `localeID` from `"en-US"`, and rebuild with `bash build-app.sh`.
</details>

---

## How it works

1. `AVAudioEngine` captures the microphone.
2. `SFSpeechRecognizer` returns partial transcripts, revising them as you speak.
3. Each transcript is diffed against what's already on screen. The part that changed gets backspaced; the new part is queued.
4. The queue drains on a log-normal timer — the same statistical shape real keystroke intervals follow — with longer gaps after spaces, commas, and periods, plus occasional hesitations.
5. Each character is posted to the system as a `CGEvent`, indistinguishable from a real keypress.

---

## Roadmap

- [ ] Menu bar mode with a global push-to-talk hotkey
- [ ] Migration to `SpeechAnalyzer` for lower latency
- [ ] Per-app speed profiles

---

## License

MIT — see [LICENSE](LICENSE).
