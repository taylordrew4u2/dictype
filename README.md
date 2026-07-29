# dictype

Dictation that types itself out, one character at a time.

macOS Dictation inserts finished words instantly. `dictype` replaces it: it listens to your microphone, transcribes speech on-device, then synthesizes real keystrokes into whatever app has focus — so the text appears letter by letter, as if someone were typing it.

Works in any text field: Notes, Slack, Xcode, a browser, a terminal.

---

## Requirements

| | |
|---|---|
| OS | macOS 13 Ventura or newer |
| Toolchain | Xcode Command Line Tools |
| Hardware | Apple silicon or Intel Mac with a microphone |

If you do not have the command line tools, install them once:

```bash
xcode-select --install
```

---

## Install

```bash
git clone https://github.com/taylordrew4u2/dictype.git
cd dictype
bash install.sh
```

The script builds the binary, installs it to `/usr/local/bin/dictype`, and walks you through the permissions below.

<details>
<summary>Manual build instead</summary>

```bash
swift build -c release
sudo install -m 755 "$(swift build -c release --show-bin-path)/dictype" /usr/local/bin/
```
</details>

---

## Permissions

`dictype` is a command-line tool, so macOS grants permissions to **your terminal app** rather than to `dictype` itself. Open **System Settings → Privacy & Security** and add Terminal (or iTerm) to all three:

1. **Microphone** — to hear you
2. **Speech Recognition** — to transcribe
3. **Accessibility** — to send keystrokes to other apps

Quit and reopen your terminal afterward. Permissions are not picked up by a session that was already running.

---

## Usage

```bash
dictype
```

Then click into any text field and speak. Press `Ctrl-C` to stop.

```
$ dictype
Listening. Focus a text field. Ctrl-C to quit.
```

---

## Configuration

Settings live at the top of `Sources/main.swift`. Edit, then rerun `bash install.sh`.

| Setting | Default | What it does |
|---|---|---|
| `charDelayMs` | `40` | Milliseconds between characters. Lower is faster. |
| `localeID` | `"en-US"` | Recognition language. |
| `onDeviceOnly` | `true` | Keeps audio on your Mac. Set `false` to allow Apple's servers. |

---

## How it works

1. `AVAudioEngine` captures microphone input and streams it to `SFSpeechRecognizer`.
2. The recognizer emits **partial** transcripts that it revises as you keep talking.
3. Each partial is diffed against the text already typed. The divergent tail is erased with backspaces; the new tail is queued.
4. A timer drains that queue at `charDelayMs` per character, posting `CGEvent` keystrokes to the system.

---

## Known behavior

- **Text may rewrite itself mid-sentence.** Streaming recognizers revise their guesses. You will occasionally see characters backspace and retype. This is the cost of typing in real time rather than after each sentence.
- **Typing trails speech.** At 40ms per character the output lags fast talking. Lower `charDelayMs` to close the gap.
- **Keystrokes go to the focused app.** Whatever has focus receives the text. Click into your target field before speaking.

---

## Troubleshooting

**`Grant Accessibility to this terminal, then rerun.`**
Add your terminal app under Privacy & Security → Accessibility, then quit and reopen it.

**`Speech recognition not authorized.`**
Add your terminal app under Privacy & Security → Speech Recognition.

**Nothing is transcribed.**
Your locale may lack an on-device model. Set `onDeviceOnly = false` in `main.swift` and rebuild.

**Nothing is typed, but transcription seems to work.**
Accessibility permission is missing or was granted to a different terminal app than the one you are running from.

---

## Roadmap

- Migrate to `SpeechAnalyzer` / `SpeechTranscriber` (macOS 26) for lower latency
- Menu bar app with a global push-to-talk hotkey
- Signed `.app` bundle so permissions attach to the app rather than the terminal

---

## License

MIT. See [LICENSE](LICENSE).
