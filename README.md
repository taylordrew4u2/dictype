# DicType

**Speak. Watch it type.**

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
| **Platform** | macOS 13 Ventura or newer, Apple Silicon or Intel          |
| **Privacy**  | Speech is transcribed on your Mac. Nothing is uploaded.    |
| **Works in** | Notes, Slack, Xcode, Mail, browsers, anywhere you can type |
| **Cost**     | Free, MIT licensed                                         |

---

## Install

### Download the installer

1. Download **[DicType.dmg](https://github.com/taylordrew4u2/dictype/releases/latest/download/DicType.dmg)** — or pick a specific build from the **[Releases](https://github.com/taylordrew4u2/dictype/releases)** page.
2. Open the DMG and drag **DicType** onto the **Applications** shortcut.
3. Clear the download quarantine flag once, in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/DicType.app
   ```

4. Open DicType from Applications.

Nothing to compile, no toolchain, no Xcode.

**Why step 3?** macOS quarantines everything downloaded from the internet and refuses to open it unless the build was notarized by Apple, which requires a paid Apple Developer Program membership. DicType's public builds are signed but not notarized, so without this step macOS shows *"DicType is damaged and can't be opened."* The command clears that flag. It is a one-time step per install.

If a release has no `DicType.dmg` attached, no installer was ever published for that build — use the latest release, or build one yourself in a couple of minutes with the steps below.

<br>

### Building it yourself

You need the Apple **Command Line Tools**. This is *not* Xcode — it is a smaller download that needs no Apple ID and no App Store:

```bash
xcode-select --install
```

Then, from the repository root:

```bash
make dmg
```

That compiles the Swift sources, assembles `DicType.app`, signs it, and packages `DicType/DicType.dmg`. Open it and drag DicType to Applications as above — a DMG you built locally is not quarantined, so you can skip the `xattr` step.

Other targets:

| Command      | What it does                                                          |
| ------------ | --------------------------------------------------------------------- |
| `make dmg`   | Build the app and package the installer                                |
| `make app`   | Build `DicType.app` only                                               |
| `make test`  | Run the repository checks                                              |
| `make icon`  | Regenerate `AppIcon.icns` from the SVG (needs `pip install cairosvg`)   |
| `make clean` | Delete build output                                                    |

The scripts behind these are [DicType/build.sh](DicType/build.sh) and [DicType/build-dmg.sh](DicType/build-dmg.sh). Both produce a **universal binary**, so one DMG runs natively on Apple Silicon and Intel.

DicType is written in Swift and SwiftUI and links against AppKit, AVFoundation and Speech, so a Swift compiler and the macOS SDK are genuinely required to build it. The Command Line Tools provide both. If you'd rather not install anything, download the DMG instead — that is what it is there for.

<br>

### Building from CI

Every push builds the app and a DMG on a macOS runner and uploads it as a workflow artifact — see [.github/workflows/ci.yml](.github/workflows/ci.yml).

To publish an installer to a release, push a tag such as `v1.1.1`, or run the **Release** workflow by hand from the Actions tab and give it a tag name. [.github/workflows/release.yml](.github/workflows/release.yml) builds the DMG and attaches it to that release, creating the release first if it does not exist yet. Running it against a tag that already has a release adds the DMG to the existing one.

---

## First launch

DicType opens to a setup screen with three cards. Each updates as you approve it.

|     | Permission             | Why                                   |
| --- | ---------------------- | ------------------------------------- |
| 1   | **Microphone**         | To hear you                           |
| 2   | **Speech Recognition** | To turn sound into words, on this Mac |
| 3   | **Accessibility**      | To type into your other apps          |

Accessibility is the fussy one. macOS opens System Settings and you flip the switch next to DicType by hand. If the switch won't stay enabled, quit DicType entirely (`Cmd + Q`) and open it again.

Once all three are green, the setup screen disappears and DicType is ready to use.

> **Note on rebuilds.** macOS ties Accessibility and Microphone grants to an app's code signature. Locally built copies are ad-hoc signed, and that signature changes on every rebuild, so macOS may ask you to re-approve DicType after `make dmg`. Remove the old entry in System Settings → Privacy & Security → Accessibility and add the new one. Builds installed from a release DMG are not affected.

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
<summary><b>"DicType is damaged and can't be opened"</b></summary>

This is the download quarantine flag, not a corrupt file. Clear it:

```bash
xattr -dr com.apple.quarantine /Applications/DicType.app
```

Then open the app again. See the note under **Install** for why this is necessary.

</details>

<details>
<summary><b>The setup screen won't turn green</b></summary>

Quit DicType completely with `Cmd + Q` — closing the window isn't enough — then reopen it. macOS sometimes doesn't hand a running app its new permissions.

If you just rebuilt the app yourself, the ad-hoc signature changed and macOS treats it as a different app. Remove the stale DicType entry in System Settings → Privacy & Security → Accessibility, then add the new build.

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
<summary><b>The app has no icon</b></summary>

The bundle must contain `Contents/Resources/AppIcon.icns`. If it is missing, regenerate it and rebuild:

```bash
pip install cairosvg
make icon
make dmg
```

</details>

<details>
<summary><b>I want a different language</b></summary>

Change `localeID` in [DicType/Sources/DicType/DictationEngine.swift](DicType/Sources/DicType/DictationEngine.swift) from `"en-US"` to the locale you want, then rebuild with `make dmg`. The language needs an on-device speech model installed under System Settings → Keyboard → Dictation.

</details>

---

## How it works

1. `AVAudioEngine` captures the microphone.
2. `SFSpeechRecognizer` returns partial transcripts as you speak.
3. Each transcript is compared to the last confirmed text, and only the newly spoken characters are queued so the visible output stays stable.
4. The queue drains on a human-like timing model with uneven pauses, longer gaps after punctuation or word boundaries, and the occasional micro-hitch.
5. Each character is posted to the system as a `CGEvent`, indistinguishable from a real keypress.

---

## Releasing a signed and notarized build

_Maintainer only. Requires an Apple Developer Program membership._

Notarization is the only thing that removes the quarantine prompt for people downloading the DMG. Everything else works without it.

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
bash DicType/release.sh
```

[DicType/release.sh](DicType/release.sh) compiles, signs with the hardened runtime, notarizes, staples the ticket, builds a drag-to-Applications DMG, notarizes that too, and verifies Gatekeeper acceptance. Notarization takes one to five minutes per submission.

Output lands in [assets/](assets): `DicType.dmg` (the installer) and `DicType.zip` (the app archive), both ready to attach to a GitHub release.

```bash
gh release create v1.1.0 assets/DicType.dmg assets/DicType.zip \
   --title "DicType 1.1.0" \
   --notes "Speak, and watch it type."
```

**Note on sandboxing.** DicType is signed with the hardened runtime but is deliberately _not_ sandboxed. A sandboxed app cannot post keyboard events into other applications, which is the entire function of this tool. That rules out Mac App Store distribution; direct download is the only channel.

---

## Roadmap

- [ ] Menu bar mode with a global push-to-talk hotkey
- [ ] Migration to `SpeechAnalyzer` for lower latency
- [ ] Per-app speed profiles

---

## License

MIT — see [LICENSE](DicType/LICENSE).
