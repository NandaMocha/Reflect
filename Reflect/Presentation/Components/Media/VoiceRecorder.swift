import SwiftUI
import AVFoundation
import Combine

struct VoiceRecorderView: View {
    @Binding var isPresented: Bool
    var onComplete: (VoiceRecordingInput) -> Void

    @State private var isRecording = false
    @State private var isPaused = false
    @State private var duration: TimeInterval = 0
    @State private var audioLevel: Float = 0
    @State private var selectedLanguage: SpeechLanguage = .english
    @State private var transcription = ""
    @State private var recordingResult: AudioRecordingResult?
    @State private var showConfirmation = false
    @State private var error: Error?

    @StateObject private var audioRecorder = AudioRecorderWrapper()
    @StateObject private var speechRecognizer = SpeechRecognizerWrapper()

    private let maxDuration: TimeInterval = 300 // 5 minutes

    var body: some View {
        NavigationStack {
            VStack(spacing: Constants.Spacing.xl) {
                Spacer()

                // Recording indicator
                recordingIndicator

                // Status text
                Text(statusText)
                    .font(.headline)

                // Duration
                if isRecording || isPaused {
                    Text(formatDuration(duration))
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                }

                // Language picker
                if !isRecording && !isPaused && !showConfirmation {
                    languagePicker
                }

                // Live transcription
                if isRecording && !transcription.isEmpty {
                    transcriptionPreview
                }

                // Confirmation view
                if showConfirmation {
                    confirmationView
                }

                Spacer()

                // Controls
                controlButtons
            }
            .padding(Constants.Spacing.lg)
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelRecording()
                        isPresented = false
                    }
                }
            }
            .onChange(of: audioRecorder.currentTime) { _, newValue in
                duration = newValue
                if duration >= maxDuration {
                    Task { await stopRecording() }
                }
            }
            .onChange(of: audioRecorder.audioLevel) { _, newValue in
                audioLevel = newValue
            }
            .onChange(of: speechRecognizer.transcription) { _, newValue in
                transcription = newValue
            }
        }
    }

    // MARK: - Components

    private var recordingIndicator: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(isRecording ? Color.error.opacity(0.2) : Color.secondary.opacity(0.1))
                .frame(width: 160, height: 160)

            // Audio level indicator
            if isRecording {
                Circle()
                    .fill(Color.error.opacity(0.3))
                    .frame(width: 120 + CGFloat(audioLevel) * 40, height: 120 + CGFloat(audioLevel) * 40)
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)
            }

            // Center icon
            Image(systemName: isRecording ? "mic.fill" : (showConfirmation ? "checkmark" : "mic"))
                .font(.system(size: 50))
                .foregroundColor(isRecording ? .error : (showConfirmation ? .success : .secondary))
        }
    }

    private var languagePicker: some View {
        VStack(spacing: Constants.Spacing.xs) {
            Text("Select Language")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("Language", selection: $selectedLanguage) {
                Text("English").tag(SpeechLanguage.english)
                Text("Indonesian").tag(SpeechLanguage.indonesian)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 250)
        }
    }

    private var transcriptionPreview: some View {
        ScrollView {
            Text(transcription)
                .font(.body)
                .foregroundColor(.secondary)
                .padding()
        }
        .frame(maxHeight: 100)
        .glassCard()
    }

    private var confirmationView: some View {
        VStack(spacing: Constants.Spacing.md) {
            if !transcription.isEmpty {
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text("Transcription")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)

                    ScrollView {
                        Text(transcription)
                            .font(.body)
                    }
                    .frame(maxHeight: 150)
                    .padding()
                    .glassCard()
                }
            }
        }
    }

    private var controlButtons: some View {
        HStack(spacing: Constants.Spacing.xl) {
            if showConfirmation {
                // Retake button
                SecondaryButton("Retake", icon: "arrow.counterclockwise") {
                    retakeRecording()
                }

                // Done button
                PrimaryButton("Done", icon: "checkmark") {
                    completeRecording()
                }
            } else {
                // Main record/stop button
                Button {
                    Task {
                        if isRecording {
                            await stopRecording()
                        } else {
                            await startRecording()
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.error : Color.primaryDefault)
                            .frame(width: 72, height: 72)

                        if isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
            }
        }
        .padding(.bottom, Constants.Spacing.lg)
    }

    // MARK: - Computed Properties

    private var statusText: String {
        if showConfirmation {
            return "Recording Complete"
        } else if isRecording {
            return "Recording..."
        } else if isPaused {
            return "Paused"
        } else {
            return "Tap to Record"
        }
    }

    // MARK: - Methods

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    @MainActor
    private func startRecording() async {
        do {
            try await audioRecorder.startRecording()
            try await speechRecognizer.startRecording(language: selectedLanguage)
            isRecording = true
            HapticManager.shared.lightImpact()
        } catch {
            self.error = error
            HapticManager.shared.error()
        }
    }

    @MainActor
    private func stopRecording() async {
        do {
            let audioResult = try await audioRecorder.stopRecording()
            let speechResult = try await speechRecognizer.stopRecording()

            recordingResult = audioResult
            transcription = speechResult.transcription ?? "-"
            isRecording = false
            showConfirmation = true
            HapticManager.shared.success()
        } catch {
            self.error = error
            HapticManager.shared.error()
        }
    }

    private func cancelRecording() {
        audioRecorder.cancelRecording()
        speechRecognizer.cancelRecording()
    }

    private func retakeRecording() {
        recordingResult = nil
        transcription = ""
        duration = 0
        showConfirmation = false
        HapticManager.shared.lightImpact()
    }

    private func completeRecording() {
        guard let result = recordingResult else { return }

        let input = VoiceRecordingInput(
            audioData: result.data,
            transcription: transcription.isEmpty ? nil : transcription,
            language: selectedLanguage.localeCode,
            duration: result.duration
        )

        onComplete(input)
        isPresented = false
        HapticManager.shared.success()
    }
}

// MARK: - Wrapper Classes

class AudioRecorderWrapper: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var audioLevel: Float = 0

    private let service = AudioRecorderService()

    func startRecording() async throws {
        try await service.startRecording()
    }

    func stopRecording() async throws -> AudioRecordingResult {
        try await service.stopRecording()
    }

    func cancelRecording() {
        service.cancelRecording()
    }
}

class SpeechRecognizerWrapper: ObservableObject {
    @Published var transcription: String = ""

    private let service = SpeechRecognitionService()

    func startRecording(language: SpeechLanguage) async throws {
        try await service.startRecording(language: language)
    }

    func stopRecording() async throws -> VoiceRecordingResult {
        try await service.stopRecording()
    }

    func cancelRecording() {
        service.cancelRecording()
    }
}

#Preview {
    VoiceRecorderView(isPresented: .constant(true)) { recording in
        print("Recording completed: \(recording.duration)s")
    }
}
