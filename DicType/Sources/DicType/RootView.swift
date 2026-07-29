import SwiftUI

// MARK: - Palette

enum Palette {
    static let ink       = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let inkSoft   = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let ember     = Color(red: 0.90, green: 0.35, blue: 0.22)
    static let emberSoft = Color(red: 0.98, green: 0.58, blue: 0.35)
    static let mint      = Color(red: 0.36, green: 0.82, blue: 0.58)
    static let dim       = Color.white.opacity(0.55)
}

// MARK: - Root

struct RootView: View {
    @StateObject private var perms = Permissions()
    @StateObject private var engine = DictationEngine()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.ink, Palette.inkSoft],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if perms.allGranted {
                ConsoleView(engine: engine)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                OnboardingView(perms: perms)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: perms.allGranted)
        .frame(minWidth: 520, minHeight: 620)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @ObservedObject var perms: Permissions

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                StepCard(
                    index: 1,
                    symbol: "mic.fill",
                    title: "Microphone",
                    detail: "So DicType can hear what you say.",
                    state: perms.microphone,
                    action: perms.requestMicrophone
                )
                StepCard(
                    index: 2,
                    symbol: "waveform",
                    title: "Speech Recognition",
                    detail: "So your words become text, on this Mac.",
                    state: perms.speech,
                    action: perms.requestSpeech
                )
                StepCard(
                    index: 3,
                    symbol: "keyboard.fill",
                    title: "Accessibility",
                    detail: "So DicType can type into your other apps.",
                    state: perms.accessibility,
                    action: perms.requestAccessibility
                )
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            footer
        }
        .padding(.vertical, 30)
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Palette.ember.opacity(0.16))
                    .frame(width: 78, height: 78)
                Image(systemName: "keyboard.badge.waveform")
                    .font(.system(size: 33, weight: .medium))
                    .foregroundStyle(Palette.emberSoft)
            }

            Text("Welcome to DicType")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Three quick permissions and you're done.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.dim)

            ProgressPips(total: 3, filled: perms.grantedCount)
                .padding(.top, 6)
        }
        .padding(.bottom, 26)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(Palette.dim)
            Text("This screen updates on its own as you approve each one.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.dim)
            Text("If a switch won't stick, quit DicType and open it again.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.dim.opacity(0.7))
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Components

struct ProgressPips: View {
    let total: Int
    let filled: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? Palette.mint : Color.white.opacity(0.16))
                    .frame(width: i < filled ? 26 : 18, height: 5)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: filled)
            }
        }
    }
}

struct StepCard: View {
    let index: Int
    let symbol: String
    let title: String
    let detail: String
    let state: PermissionState
    let action: () -> Void

    private var done: Bool { state == .granted }

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(done ? Palette.mint.opacity(0.18) : Palette.ember.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: done ? "checkmark" : symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(done ? Palette.mint : Palette.emberSoft)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("\(index). \(title)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    StatusPill(state: state)
                }
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !done {
                Button(action: action) {
                    Text(state == .denied ? "Open Settings" : "Allow")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(Palette.ember)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(done ? Palette.mint.opacity(0.35) : Color.white.opacity(0.07),
                                lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.25), value: done)
    }
}

struct StatusPill: View {
    let state: PermissionState

    private var tint: Color {
        switch state {
        case .granted:       return Palette.mint
        case .denied:        return Palette.ember
        case .notDetermined: return .white.opacity(0.5)
        }
    }

    var body: some View {
        Text(state.label.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
            .foregroundStyle(tint)
    }
}

// MARK: - Console

struct ConsoleView: View {
    @ObservedObject var engine: DictationEngine
    @State private var wpm: Double = 62
    @State private var jitter: Double = 0.42

    var body: some View {
        VStack(spacing: 22) {
            Text("DicType")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 26)

            micButton

            Text(engine.isListening
                 ? "Click into any text field and speak."
                 : "Ready when you are.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.dim)

            if let err = engine.errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ember)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            transcript

            sliders

            Spacer()
        }
    }

    private var micButton: some View {
        Button {
            engine.isListening ? engine.stop() : engine.start()
        } label: {
            ZStack {
                Circle()
                    .fill(engine.isListening ? Palette.ember : Color.white.opacity(0.08))
                    .frame(width: 108, height: 108)
                Circle()
                    .stroke(engine.isListening ? Palette.ember.opacity(0.35) : .clear,
                            lineWidth: 10)
                    .frame(width: 128, height: 128)
                Image(systemName: engine.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: engine.isListening)
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HEARD")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.dim)
            Text(engine.lastHeard.isEmpty ? "—" : engine.lastHeard)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .padding(.horizontal, 28)
    }

    private var sliders: some View {
        VStack(spacing: 14) {
            labelled("Speed", "\(Int(wpm)) WPM") {
                Slider(value: $wpm, in: 25...110, step: 1)
                    .tint(Palette.ember)
                    .onChange(of: wpm) { _ in engine.typewriter.targetWPM = wpm }
            }
            labelled("Looseness", String(format: "%.2f", jitter)) {
                Slider(value: $jitter, in: 0...0.7)
                    .tint(Palette.ember)
                    .onChange(of: jitter) { _ in engine.typewriter.jitterSigma = jitter }
            }
        }
        .padding(.horizontal, 28)
    }

    private func labelled<C: View>(_ title: String,
                                   _ value: String,
                                   @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.dim)
            }
            content()
        }
    }
}
