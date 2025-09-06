//
//  ContentView.swift
//  llmt2
//
//  Created by Seth Paonessa on 9/6/25.
//

import SwiftUI
import FoundationModels
import Speech // Added for speech recognition API
import Combine
import AVFoundation

/// Represents a single chat message.
struct ChatMessage: Identifiable, Hashable, Codable { // Made Codable for persistence
    enum Sender: String, Codable {
        case user
        case llm
    }
    let id: UUID
    let sender: Sender
    let text: String
    let timestamp: Date
    
    init(id: UUID = UUID(), sender: Sender, text: String, timestamp: Date = Date()) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
    }
}

@Observable
class ChatViewModel {
    // MARK: Persistence key storage for chat messages
    private static let storageKey = "chatMessages"
    
    // MARK: Published properties
    var messages: [ChatMessage] = [] {
        didSet {
            saveMessages()
        }
    }
    var userInput: String = ""
    var isResponding: Bool = false
    
    private var session: LanguageModelSession? = nil
    
    // Callback for when a new AI message is added
    var onNewAIMessage: ((String) -> Void)?
    
    init() {
        print("🔄 Initializing ChatViewModel...")
        
        // Add a welcome message first
        addAIMessage("Hello! I'm your AI assistant. Initializing...")
        
        // Setup LLM session with helpful assistant instructions
        let instructions = """
        You are a helpful, friendly chat assistant. Keep your answers concise and use natural conversational language. If you don't know, say so politely.
        """
        
        // Try to create session with better error handling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                self.session = LanguageModelSession(instructions: instructions)
                print("✅ LanguageModelSession created successfully")
                
                        // Update the welcome message
                        if let lastMessageIndex = self.messages.firstIndex(where: { $0.sender == .llm && $0.text.contains("Initializing") }) {
                            self.messages[lastMessageIndex] = ChatMessage(sender: .llm, text: "Hello! I'm your AI assistant. Ready to chat!")
                            self.onNewAIMessage?("Hello! I'm your AI assistant. Ready to chat!")
                        }
            } catch {
                print("❌ Failed to create LanguageModelSession: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                
                        // Update the welcome message to indicate the issue
                        if let lastMessageIndex = self.messages.firstIndex(where: { $0.sender == .llm && $0.text.contains("Initializing") }) {
                            self.messages[lastMessageIndex] = ChatMessage(sender: .llm, text: "Hello! I'm your AI assistant. Note: Language model is not available, but you can still use the chat interface.")
                            self.onNewAIMessage?("Hello! I'm your AI assistant. Note: Language model is not available, but you can still use the chat interface.")
                        }
            }
        }
        
        // Load messages from persistent storage
        loadMessages()
    }
    
    /// Encode and save messages to UserDefaults via AppStorage Data
    private func saveMessages() {
        do {
            let encoded = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        } catch {
            print("Failed to save messages: \(error)")
        }
    }
    
    /// Load messages from UserDefaults at startup
    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([ChatMessage].self, from: data)
            messages = decoded
        } catch {
            print("Failed to load messages: \(error)")
        }
    }

    /// Sends a user message and gets LLM response
    @MainActor
    func sendMessage() async {
        let prompt = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        if session == nil {
            addAIMessage("Sorry, the language model is not available. Please check that you're running macOS 26 beta and that FoundationModels is properly installed.")
            return
        }
        
        userInput = ""
        messages.append(ChatMessage(sender: .user, text: prompt))
        isResponding = true
        
        do {
            print("🤖 Sending prompt to LanguageModelSession: \(prompt)")
            let response = try await session!.respond(to: prompt)
            print("✅ Received response: \(response.content)")
            addAIMessage(response.content)
        } catch {
            print("❌ Error getting response: \(error)")
            addAIMessage("Sorry, I encountered an error: \(error.localizedDescription)")
        }
        isResponding = false
    }
    
    /// Clears all chat messages
    func clearChat() {
        messages.removeAll()
        userInput = ""
    }
    
    /// Adds an AI message and triggers TTS callback
    private func addAIMessage(_ text: String) {
        messages.append(ChatMessage(sender: .llm, text: text))
        onNewAIMessage?(text)
    }
    
}

/// SpeechRecognizer helper class to manage speech recognition lifecycle
final class SpeechRecognizer: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var isRecognizing = false
    @Published var recognizedText = ""
    
    private let speechRecognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    override init() {
        super.init()
        requestAuthorization()
    }
    
    /// Request speech recognition authorization
    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                self.isAuthorized = (authStatus == .authorized)
            }
        }
    }
    
    /// Starts speech recognition, appends recognized text continuously
    func startRecognition() throws {
        guard !audioEngine.isRunning else { return }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognizer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        recognitionRequest.shouldReportPartialResults = true
        
        // Audio input node
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                // Append recognized text, preserving new content
                self.recognizedText = result.bestTranscription.formattedString
            }
            if error != nil || (result?.isFinal ?? false) {
                self.stopRecognition()
            }
        }
        
        // Install tap on audio input node
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRecognizing = true
    }
    
    /// Stop speech recognition and reset
    func stopRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            audioEngine.inputNode.removeTap(onBus: 0)
            isRecognizing = false
        }
    }
}

/// Text-to-Speech manager for speaking AI responses
final class TextToSpeechManager: NSObject, ObservableObject {
    @Published var isSpeaking = false
    @Published var isEnabled = true
    
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    /// Speaks the given text
    func speak(_ text: String) {
        guard isEnabled && !text.isEmpty else { return }
        
        // Stop any current speech
        stopSpeaking()
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9 // Slightly slower for better comprehension
        utterance.volume = 0.8
        utterance.pitchMultiplier = 1.0
        
        // Try to use a pleasant voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        synthesizer.speak(utterance)
    }
    
    /// Stops current speech
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    /// Toggles TTS on/off
    func toggleEnabled() {
        isEnabled.toggle()
        if !isEnabled {
            stopSpeaking()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TextToSpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}


struct ContentView: View {
    // MARK: Stored messages in AppStorage as Data
    @AppStorage("chatMessages") private var storedMessages: Data = Data() // Used only for persistence sync
    
    // MARK: ViewModel and states
    @State private var viewModel = ChatViewModel()
    @FocusState private var inputFocused: Bool
    
    // MARK: Speech recognition states
    @State private var speechRecognizer: SpeechRecognizer?
    @State private var speechInputActive = false
    
    // MARK: Text-to-Speech states
    @StateObject private var ttsManager = TextToSpeechManager()
    
    var body: some View {
        VStack(spacing: 16) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                }
                //.background(.secondary) // Removed as per instructions
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastID = viewModel.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                // Microphone button for speech input
                Button {
                    // Toggle speech recognition
                    if speechInputActive {
                        speechRecognizer?.stopRecognition()
                        speechInputActive = false
                        // Append recognized text to user input
                        if !(speechRecognizer?.recognizedText.isEmpty ?? true) {
                            if !viewModel.userInput.isEmpty {
                                viewModel.userInput += " "
                            }
                            viewModel.userInput += speechRecognizer?.recognizedText ?? ""
                        }
                        speechRecognizer?.recognizedText = ""
                    } else {
                        // Start recognition; handle errors gracefully
                        do {
                            try speechRecognizer?.startRecognition()
                            speechInputActive = true
                        } catch {
                            speechInputActive = false
                        }
                    }
                } label: {
                    Image(systemName: speechInputActive ? "mic.fill" : "mic")
                        .font(.system(size: 24))
                        .foregroundColor(
                            (speechRecognizer?.isAuthorized ?? false) ? (speechInputActive ? .accentColor : .primary) : .gray
                        )
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(speechInputActive ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                }
                .disabled(!(speechRecognizer?.isAuthorized ?? false))
                .help((speechRecognizer?.isAuthorized ?? false) ? (speechInputActive ? "Stop recording" : "Start recording") : "Speech recognition permission not granted")
                .animation(.default, value: speechInputActive)
                
                TextField("Type your message…", text: $viewModel.userInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .lineLimit(1...6)
                    .disabled(viewModel.isResponding)
                    .padding(.vertical, 8)
                    .onSubmit {
                        if !viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isResponding {
                            Task { await viewModel.sendMessage() }
                        }
                    }
                
                
                // Clear chat button
                Button {
                    viewModel.clearChat()
                } label: {
                    Image(systemName: "trash.circle")
                        .font(.system(size: 24))
                        .tint(.secondary)
                }
                .disabled(viewModel.messages.isEmpty || viewModel.isResponding)
                .buttonStyle(PlainButtonStyle())
                .help("Clear chat history")
                
                // TTS toggle button
                Button {
                    ttsManager.toggleEnabled()
                } label: {
                    Image(systemName: ttsManager.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 24))
                        .tint(ttsManager.isEnabled ? .accentColor : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(ttsManager.isEnabled ? "Text-to-Speech enabled" : "Text-to-Speech disabled")
                
                // Stop TTS button (only show when speaking)
                if ttsManager.isSpeaking {
                    Button {
                        ttsManager.stopSpeaking()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .tint(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Stop speaking")
                }
                
                Button {
                    Task { await viewModel.sendMessage() }
                } label: {
                    if viewModel.isResponding {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .tint(.accentColor)
                    }
                }
                .disabled(viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isResponding)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
        // Custom dark gradient background on main VStack
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.12, green: 0.12, blue: 0.18),
                    Color(red: 0.07, green: 0.07, blue: 0.12)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        // Enforce dark mode for entire ContentView
        .preferredColorScheme(.dark)
        .navigationTitle("AI Chat")
        .onAppear { 
            inputFocused = true
            
            // Run FoundationModels tests
            FoundationModelsTest.runTests()
            
            // Delay speech recognition initialization to ensure Info.plist is loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                speechRecognizer = SpeechRecognizer()
                #if os(macOS)
                requestMicrophonePermission()
                #endif
            }
            
            // Set up TTS callback for AI messages
            viewModel.onNewAIMessage = { [weak ttsManager] message in
                ttsManager?.speak(message)
            }
        }
    }
    
    #if os(macOS)
    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                // Permission is handled by SpeechRecognizer
            }
        }
    }
    #endif
}

/// Modernized chat bubble with gradient, border, and shadow for improved contrast
struct ChatBubble: View {
    let message: ChatMessage
    
    var isFromUser: Bool { message.sender == .user }
    
    var body: some View {
        HStack {
            if isFromUser { Spacer() }
            VStack(alignment: isFromUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .foregroundStyle(isFromUser ? Color.white : Color.primary)
                
                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(isFromUser ? Color.white.opacity(0.7) : Color.secondary)
            }
            .padding(14)
            .background(
                Group {
                    if isFromUser {
                        // User bubble: accent gradient with shadow
                        LinearGradient(
                            gradient: Gradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        // LLM bubble: dark background with subtle border
                        Color(white: 0.15)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isFromUser ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: isFromUser ? Color.accentColor.opacity(0.4) : Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
            .frame(maxWidth: 320, alignment: isFromUser ? .trailing : .leading)
            if !isFromUser { Spacer() }
        }
        .padding(.horizontal, 6)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark) // Enforce dark mode in preview
}
