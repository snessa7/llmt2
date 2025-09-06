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
    
    init(id: UUID = UUID(), sender: Sender, text: String) {
        self.id = id
        self.sender = sender
        self.text = text
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
    
    init() {
        // Setup LLM session with helpful assistant instructions
        let instructions = """
        You are a helpful, friendly chat assistant. Keep your answers concise and use natural conversational language. If you don't know, say so politely.
        """
        
        do {
            session = LanguageModelSession(instructions: instructions)
            print("✅ LanguageModelSession created successfully")
        } catch {
            print("❌ Failed to create LanguageModelSession: \(error)")
            // Add a welcome message to indicate the app is working
            messages.append(ChatMessage(sender: .llm, text: "Hello! I'm your AI assistant. The language model is initializing..."))
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
            messages.append(ChatMessage(sender: .llm, text: "Sorry, the language model is not available. Please check that you're running macOS 26 beta and that FoundationModels is properly installed."))
            return
        }
        
        userInput = ""
        messages.append(ChatMessage(sender: .user, text: prompt))
        isResponding = true
        
        do {
            print("🤖 Sending prompt to LanguageModelSession: \(prompt)")
            let response = try await session!.respond(to: prompt)
            print("✅ Received response: \(response.content)")
            messages.append(ChatMessage(sender: .llm, text: response.content))
        } catch {
            print("❌ Error getting response: \(error)")
            messages.append(ChatMessage(sender: .llm, text: "Sorry, I encountered an error: \(error.localizedDescription)"))
        }
        isResponding = false
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

struct ContentView: View {
    // MARK: Stored messages in AppStorage as Data
    @AppStorage("chatMessages") private var storedMessages: Data = Data() // Used only for persistence sync
    
    // MARK: ViewModel and states
    @State private var viewModel = ChatViewModel()
    @FocusState private var inputFocused: Bool
    
    // MARK: Speech recognition states
    @State private var speechRecognizer: SpeechRecognizer?
    @State private var speechInputActive = false
    
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
            Text(message.text)
                .padding(14)
                .foregroundStyle(isFromUser ? Color.white : Color.primary)
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
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark) // Enforce dark mode in preview
}
