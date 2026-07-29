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
            LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.06),
                                    Color(red: 0.10, green: 0.11, blue: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            Circle()
                .fill(Palette.ember.opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: -140, y: -200)

            Circle()
                .fill(Palette.mint.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 180, y: 220)

            if perms.allGranted {
                ConsoleView(engine: engine)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                OnboardingView(perms: perms)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: perms.allGranted)
        .frame(minWidth: 560, minHeight: 680)
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
                    symbol: "mic.circle.fill",
                    title: "Microphone",
                    detail: "Let DicType hear your voice clearly.",
                    state: perms.microphone,
                    action: perms.requestMicrophone
                )
                StepCard(
                    index: 2,
                    symbol: "sparkles.square.fill.on.square",
                    title: "Speech Recognition",
                    detail: "Turn your words into text instantly on this Mac.",
                    state: perms.speech,
                    action: perms.requestSpeech
                )
                StepCard(
                    index: 3,
                    symbol: "keyboard.badge.ellipsis",
                    title: "Accessibility",
                    detail: "Give DicType permission to type into other apps.",
                    state: perms.accessibility,
                    action: perms.requestAccessibility
                )
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 10)

            footer
        }
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(24)
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Palette.ember.opacity(0.24), Palette.emberSoft.opacity(0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 86, height: 86)
                    .shadow(color: Palette.ember.opacity(0.2), radius: 18, x: 0, y: 10)
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("Welcome to DicType")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("A few permissions unlock a seamless voice typing experience.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.dim)
                    .multilineTextAlignment(.center)
            }

            ProgressPips(total: 3, filled: perms.grantedCount)
                .padding(.top, 2)
        }
        .padding(.bottom, 20)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.emberSoft)
                Text("This screen updates as you complete each step.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.dim)
            }
            Text("If a permission switch won’t stay enabled, reopen DicType and try again.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.dim.opacity(0.75))
                .multilineTextAlignment(.center)
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
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(done ? Palette.mint.opacity(0.18) : Palette.ember.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: done ? "checkmark.circle.fill" : symbol)
                    .font(.system(size: 19, weight: .semibold))
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
                    Label(state == .denied ? "Open Settings" : "Allow",
                          systemImage: state == .denied ? "gearshape.fill" : "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(done ? Palette.mint.opacity(0.35) : Color.white.opacity(0.07),
                                lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 4)
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
    @State private var wpm: Double
    @State private var jitter: Double

    init(engine: DictationEngine) {
        self.engine = engine
        _wpm = State(initialValue: engine.typewriter.targetWPM)
        _jitter = State(initialValue: engine.typewriter.jitterSigma)
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard.badge.waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.emberSoft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DicType")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Human-like voice typing")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.dim)
                    }
                }
                Spacer()
                Capsule()
                    .fill(Palette.mint.opacity(0.18))
                    .overlay(
                        Text("Live")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.mint)
                            .padding(.horizontal, 8)
                    )
                    .frame(width: 54, height: 24)
            }
            .padding(.top, 24)
            .padding(.horizontal, 28)

            micButton

            Text(engine.isListening
                 ? "Click into any text field and speak."
                 : "Ready when you are.")
                .font(.system(size: 13, weight: .medium))
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
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.16), radius: 20, x: 0, y: 12)
        )
        .padding(.horizontal, 24)
    }

    private var micButton: some View {
        Button {
            engine.isListening ? engine.stop() : engine.start()
        } label: {
            ZStack {
                Circle()
                    .fill(engine.isListening ? Palette.ember : Color.white.opacity(0.08))
                    .frame(width: 112, height: 112)
                    .shadow(color: engine.isListening ? Palette.ember.opacity(0.24) : .clear, radius: 18, x: 0, y: 12)
                Circle()
                    .stroke(engine.isListening ? Palette.ember.opacity(0.35) : .clear,
                            lineWidth: 10)
                    .frame(width: 132, height: 132)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
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
        .padding(.top, 2)
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
