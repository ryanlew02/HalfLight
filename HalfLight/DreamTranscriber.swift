//
//  DreamTranscriber.swift
//  HalfLight
//
//  Live speech-to-text for dictating dreams, built on the Speech framework.
//

import Foundation
import AVFoundation
import Speech

@MainActor
@Observable
final class DreamTranscriber {
    /// The latest recognized text for the current dictation session.
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func toggle() {
        if isRecording {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""

        guard await Self.requestSpeechAuthorization() == .authorized else {
            errorMessage = "Enable Speech Recognition in Settings to dictate."
            return
        }
        guard await Self.requestMicPermission() else {
            errorMessage = "Enable Microphone access in Settings to dictate."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        do {
            try beginSession(recognizer)
            isRecording = true
        } catch {
            errorMessage = "Couldn't start recording."
            cleanup()
        }
    }

    func stop() {
        cleanup()
        isRecording = false
    }

    // MARK: - Audio pipeline

    private func beginSession(_ recognizer: SFSpeechRecognizer) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.stop() }
                } else if error != nil {
                    self.stop()
                }
            }
        }
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Authorization

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private static func requestMicPermission() async -> Bool {
        #if os(iOS)
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        #else
        return true
        #endif
    }
}
