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

/// Represents a chat session with messages and metadata
struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var lastModified: Date
    
    init(id: UUID = UUID(), title: String, messages: [ChatMessage] = [], createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.lastModified = createdAt
    }
    
    /// Updates the last modified timestamp
    mutating func updateLastModified() {
        self.lastModified = Date()
    }
    
    /// Generates a title from the first user message if no title is set
    mutating func generateTitle() {
        if title.isEmpty || title == "New Chat" {
            if let firstUserMessage = messages.first(where: { $0.sender == .user }) {
                let preview = String(firstUserMessage.text.prefix(50))
                title = preview.isEmpty ? "New Chat" : preview
            }
        }
    }
}

/// Simple memory system for storing user preferences and context
struct UserMemory: Codable {
    var userName: String?
    var preferences: [String: String]
    var importantFacts: [String]
    var lastChatSessionId: UUID?
    var systemPrompt: String
    
    init() {
        self.userName = nil
        self.preferences = [:]
        self.importantFacts = []
        self.lastChatSessionId = nil
        self.systemPrompt = "You are a helpful, friendly chat assistant. Keep your answers concise and use natural conversational language. If you don't know something, say so politely."
    }
}

/// Memory manager for handling user memory and chat sessions
class MemoryManager: ObservableObject {
    private static let memoryKey = "userMemory"
    private static let chatSessionsKey = "chatSessions"
    
    var userMemory: UserMemory
    var chatSessions: [ChatSession]
    var currentSessionId: UUID?
    
    init() {
        self.userMemory = Self.loadMemory()
        self.chatSessions = Self.loadChatSessions()
        self.currentSessionId = userMemory.lastChatSessionId
    }
    
    // MARK: - Memory Management
    
    /// Load user memory from UserDefaults
    private static func loadMemory() -> UserMemory {
        guard let data = UserDefaults.standard.data(forKey: memoryKey),
              let memory = try? JSONDecoder().decode(UserMemory.self, from: data) else {
            return UserMemory()
        }
        return memory
    }
    
    /// Save user memory to UserDefaults
    private func saveMemory() {
        if let data = try? JSONEncoder().encode(userMemory) {
            UserDefaults.standard.set(data, forKey: Self.memoryKey)
        }
    }
    
    /// Load chat sessions from UserDefaults
    private static func loadChatSessions() -> [ChatSession] {
        guard let data = UserDefaults.standard.data(forKey: chatSessionsKey),
              let sessions = try? JSONDecoder().decode([ChatSession].self, from: data) else {
            return [ChatSession(title: "New Chat")]
        }
        return sessions
    }
    
    /// Save chat sessions to UserDefaults
    private func saveChatSessions() {
        if let data = try? JSONEncoder().encode(chatSessions) {
            UserDefaults.standard.set(data, forKey: Self.chatSessionsKey)
        }
    }
    
    // MARK: - Memory Operations
    
    /// Add or update a user preference
    func setPreference(_ key: String, value: String) {
        userMemory.preferences[key] = value
        saveMemory()
        print("🧠 Memory: Set preference '\(key)' = '\(value)'")
    }
    
    /// Get a user preference
    func getPreference(_ key: String) -> String? {
        return userMemory.preferences[key]
    }
    
    /// Add an important fact
    func addFact(_ fact: String) {
        if !userMemory.importantFacts.contains(fact) {
            userMemory.importantFacts.append(fact)
            saveMemory()
            print("🧠 Memory: Added fact '\(fact)'")
        }
    }
    
    /// Set user name
    func setUserName(_ name: String) {
        userMemory.userName = name
        saveMemory()
        print("🧠 Memory: Set user name to '\(name)'")
    }
    
    // MARK: - Chat Session Management
    
    /// Create a new chat session
    func createNewChatSession() -> ChatSession {
        let newSession = ChatSession(title: "New Chat")
        chatSessions.append(newSession)
        saveChatSessions()
        currentSessionId = newSession.id
        userMemory.lastChatSessionId = newSession.id
        saveMemory()
        print("💬 Chat: Created new session '\(newSession.title)'")
        return newSession
    }
    
    /// Get current chat session
    func getCurrentSession() -> ChatSession? {
        return chatSessions.first { $0.id == currentSessionId }
    }
    
    /// Update current session messages
    func updateCurrentSessionMessages(_ messages: [ChatMessage]) {
        guard let index = chatSessions.firstIndex(where: { $0.id == currentSessionId }) else { return }
        chatSessions[index].messages = messages
        chatSessions[index].updateLastModified()
        chatSessions[index].generateTitle()
        saveChatSessions()
    }
    
    /// Switch to a different chat session
    func switchToSession(_ sessionId: UUID) {
        currentSessionId = sessionId
        userMemory.lastChatSessionId = sessionId
        saveMemory()
        print("💬 Chat: Switched to session '\(sessionId)'")
    }
    
    /// Delete a chat session
    func deleteSession(_ sessionId: UUID) {
        chatSessions.removeAll { $0.id == sessionId }
        if currentSessionId == sessionId {
            currentSessionId = chatSessions.first?.id
            userMemory.lastChatSessionId = currentSessionId
            saveMemory()
        }
        saveChatSessions()
        print("💬 Chat: Deleted session '\(sessionId)'")
    }
    
    /// Search chat sessions by title or content
    func searchSessions(_ query: String) -> [ChatSession] {
        let lowercaseQuery = query.lowercased()
        return chatSessions.filter { session in
            session.title.lowercased().contains(lowercaseQuery) ||
            session.messages.contains { $0.text.lowercased().contains(lowercaseQuery) }
        }
    }
    
    // MARK: - System Prompt Management
    
    /// Update the system prompt
    func updateSystemPrompt(_ prompt: String) {
        userMemory.systemPrompt = prompt
        saveMemory()
        print("🤖 System prompt updated")
    }
    
    /// Get the current system prompt
    func getSystemPrompt() -> String {
        return userMemory.systemPrompt
    }
    
    /// Reset system prompt to default
    func resetSystemPrompt() {
        userMemory.systemPrompt = "You are a helpful, friendly chat assistant. Keep your answers concise and use natural conversational language. If you don't know something, say so politely."
        saveMemory()
        print("🤖 System prompt reset to default")
    }
}

@Observable
class ChatViewModel {
    // MARK: Published properties
    var messages: [ChatMessage] = [] {
        didSet {
            // Only update memory manager if we're not in the middle of initialization
            if !isInitializing {
                memoryManager.updateCurrentSessionMessages(messages)
            }
        }
    }
    var userInput: String = ""
    var isResponding: Bool = false
    
    private var session: LanguageModelSession? = nil
    private let memoryManager: MemoryManager
    private var isInitializing: Bool = true
    
    // Callback for when a new AI message is added
    var onNewAIMessage: ((String) -> Void)?
    
    init(memoryManager: MemoryManager) {
        print("🔄 Initializing ChatViewModel...")
        self.memoryManager = memoryManager
        
        // Load messages from current session
        loadMessagesFromCurrentSession()
        
        // Add a welcome message if no messages exist
        if messages.isEmpty {
            addAIMessage("Hello! I'm your AI assistant. Initializing...")
        }
        
        // Mark initialization as complete
        isInitializing = false
        
        // Setup LLM session with system prompt from memory manager
        let instructions = memoryManager.getSystemPrompt()
        
        // Try to create session with better error handling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.session = LanguageModelSession(instructions: instructions)
            print("✅ LanguageModelSession created successfully with system prompt")
            
            // Update the welcome message if it's the initializing one
            if let lastMessageIndex = self.messages.firstIndex(where: { $0.sender == .llm && $0.text.contains("Initializing") }) {
                self.messages[lastMessageIndex] = ChatMessage(sender: .llm, text: "Hello! I'm your AI assistant. Ready to chat!")
                self.onNewAIMessage?("Hello! I'm your AI assistant. Ready to chat!")
            }
        }
    }
    
    /// Load messages from current chat session
    private func loadMessagesFromCurrentSession() {
        if let currentSession = memoryManager.getCurrentSession() {
            messages = currentSession.messages
            print("📝 Loaded \(currentSession.messages.count) messages from current session")
        } else {
            messages = []
            print("📝 No current session found, starting fresh")
        }
    }
    
    /// Switch to a different chat session
    func switchToSession(_ sessionId: UUID) {
        memoryManager.switchToSession(sessionId)
        loadMessagesFromCurrentSession()
        print("💬 Switched to session: \(sessionId)")
    }
    
    /// Create a new chat session
    func createNewChatSession() {
        let newSession = memoryManager.createNewChatSession()
        messages = []
        addAIMessage("Hello! I'm your AI assistant. Ready to chat!")
        print("💬 Created new chat session: \(newSession.title)")
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
    
    /// Update the system prompt and recreate the LanguageModelSession
    func updateSystemPrompt(_ prompt: String) {
        memoryManager.updateSystemPrompt(prompt)
        
        // Recreate the session with new instructions
        session = LanguageModelSession(instructions: prompt)
        print("🤖 LanguageModelSession recreated with new system prompt")
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

/// Text-to-Speech manager for speaking AI responses with enhanced voice quality
final class TextToSpeechManager: NSObject, ObservableObject {
    @Published var isSpeaking = false
    @Published var isEnabled = true
    @Published var selectedVoice: AVSpeechSynthesisVoice?
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var speechRate: Float = 0.5 // Slower for better comprehension
    @Published var speechPitch: Float = 1.0
    @Published var speechVolume: Float = 0.8
    
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
        setupVoices()
    }
    
    /// Sets up available voices and selects the best one
    private func setupVoices() {
        // Get all available voices
        availableVoices = AVSpeechSynthesisVoice.speechVoices()
        
        // Prefer high-quality voices in order of preference
        let preferredVoiceIdentifiers = [
            "com.apple.voice.enhanced.en-US.Samantha",      // Enhanced Samantha (best quality)
            "com.apple.voice.enhanced.en-US.Alex",          // Enhanced Alex
            "com.apple.voice.enhanced.en-US.Victoria",      // Enhanced Victoria
            "com.apple.voice.enhanced.en-US.Daniel",        // Enhanced Daniel
            "com.apple.ttsbundle.Samantha-compact",         // Standard Samantha
            "com.apple.ttsbundle.Alex-compact",             // Standard Alex
        ]
        
        // Find the best available voice
        for identifier in preferredVoiceIdentifiers {
            if let voice = availableVoices.first(where: { $0.identifier == identifier }) {
                selectedVoice = voice
                print("🎤 Selected voice: \(voice.name) (\(voice.identifier))")
                break
            }
        }
        
        // Fallback to any enhanced English voice
        if selectedVoice == nil {
            selectedVoice = availableVoices.first { voice in
                voice.language.hasPrefix("en") && voice.identifier.contains("enhanced")
            }
        }
        
        // Final fallback to any English voice
        if selectedVoice == nil {
            selectedVoice = availableVoices.first { $0.language.hasPrefix("en") }
        }
        
        print("🎤 Available voices: \(availableVoices.count)")
        print("🎤 Selected voice: \(selectedVoice?.name ?? "None")")
    }
    
    /// Speaks the given text with enhanced quality settings
    func speak(_ text: String) {
        guard isEnabled && !text.isEmpty else { return }
        
        // Stop any current speech
        stopSpeaking()
        
        var utterance = AVSpeechUtterance(string: text)
        
        // Use custom speech parameters
        utterance.rate = speechRate
        utterance.volume = speechVolume
        utterance.pitchMultiplier = speechPitch
        
        // Pre-process text for better speech
        let processedText = preprocessTextForSpeech(text)
        utterance = AVSpeechUtterance(string: processedText)
        
        // Use the selected voice
        utterance.voice = selectedVoice
        
        print("🎤 Speaking with voice: \(selectedVoice?.name ?? "Default") (\(selectedVoice?.identifier ?? "none"))")
        print("🎤 Speech settings - Rate: \(speechRate), Volume: \(speechVolume), Pitch: \(speechPitch)")
        print("🎤 Text: \(processedText.prefix(50))...")
        
        synthesizer.speak(utterance)
    }
    
    /// Pre-processes text for better speech quality
    private func preprocessTextForSpeech(_ text: String) -> String {
        var processedText = text
        
        // Replace common abbreviations and symbols for better pronunciation
        let replacements = [
            "AI": "A I",
            "API": "A P I",
            "URL": "U R L",
            "HTTP": "H T T P",
            "HTTPS": "H T T P S",
            "JSON": "J S O N",
            "XML": "X M L",
            "SQL": "S Q L",
            "CPU": "C P U",
            "GPU": "G P U",
            "RAM": "R A M",
            "SSD": "S S D",
            "HDD": "H D D",
            "USB": "U S B",
            "WiFi": "Wi Fi",
            "Bluetooth": "Blue tooth",
            "&": "and",
            "@": "at",
            "#": "hash",
            "$": "dollar",
            "%": "percent",
            "+": "plus",
            "=": "equals",
            "<": "less than",
            ">": "greater than",
            "|": "pipe",
            "\\": "backslash",
            "/": "slash",
            "*": "asterisk",
            "~": "tilde",
            "^": "caret",
            "`": "backtick",
        ]
        
        for (symbol, replacement) in replacements {
            processedText = processedText.replacingOccurrences(of: symbol, with: replacement)
        }
        
        return processedText
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
    
    /// Changes the selected voice
    func selectVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoice = voice
        print("🎤 Voice changed to: \(voice.name) (\(voice.identifier))")
        
        // Stop any current speech to apply the new voice immediately
        if isSpeaking {
            stopSpeaking()
        }
    }
    
    /// Updates speech rate (0.0 to 1.0)
    func updateSpeechRate(_ rate: Float) {
        speechRate = max(0.0, min(1.0, rate))
        print("🎤 Speech rate updated to: \(speechRate)")
    }
    
    /// Updates speech pitch (0.5 to 2.0)
    func updateSpeechPitch(_ pitch: Float) {
        speechPitch = max(0.5, min(2.0, pitch))
        print("🎤 Speech pitch updated to: \(speechPitch)")
    }
    
    /// Updates speech volume (0.0 to 1.0)
    func updateSpeechVolume(_ volume: Float) {
        speechVolume = max(0.0, min(1.0, volume))
        print("🎤 Speech volume updated to: \(speechVolume)")
    }
    
    /// Gets the current voice name for display
    var currentVoiceName: String {
        return selectedVoice?.name ?? "Default"
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
    // MARK: Memory and Chat Management
    @StateObject private var memoryManager = MemoryManager()
    @State private var viewModel: ChatViewModel?
    @FocusState private var inputFocused: Bool
    
    // MARK: Chat Session Management
    @State private var showChatSessions = false
    @State private var searchText = ""
    
    // MARK: Speech recognition states
    @State private var speechRecognizer: SpeechRecognizer?
    @State private var speechInputActive = false
    
    // MARK: Text-to-Speech states
    @StateObject private var ttsManager = TextToSpeechManager()
    @State private var showVoiceSettings = false
    
    // MARK: System Prompt states
    @State private var showSystemPromptSettings = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with chat session management
            HStack {
                // New Chat Button
                Button {
                    viewModel?.createNewChatSession()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("New Chat")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Current Chat Title
                Text(memoryManager.getCurrentSession()?.title ?? "New Chat")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // System Prompt Settings Button
                Button {
                    showSystemPromptSettings.toggle()
                } label: {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Configure AI system prompt")
                
                // Chat Sessions Button
                Button {
                    showChatSessions.toggle()
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .help("View all chat sessions")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel?.messages ?? []) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                }
                //.background(.secondary) // Removed as per instructions
                .onChange(of: viewModel?.messages.count ?? 0) {
                    if let lastID = viewModel?.messages.last?.id {
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
                            if let viewModel = viewModel {
                                if !viewModel.userInput.isEmpty {
                                    viewModel.userInput += " "
                                }
                                viewModel.userInput += speechRecognizer?.recognizedText ?? ""
                            }
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
                
                TextField("Type your message…", text: Binding(
                    get: { viewModel?.userInput ?? "" },
                    set: { viewModel?.userInput = $0 }
                ), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .lineLimit(1...6)
                    .disabled(viewModel?.isResponding ?? false)
                    .padding(.vertical, 8)
                    .onSubmit {
                        if let viewModel = viewModel,
                           !viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isResponding {
                            Task { await viewModel.sendMessage() }
                        }
                    }
                
                
                // Clear chat button
                Button {
                    viewModel?.clearChat()
                } label: {
                    Image(systemName: "trash.circle")
                        .font(.system(size: 24))
                        .tint(.secondary)
                }
                .disabled((viewModel?.messages.isEmpty ?? true) || (viewModel?.isResponding ?? false))
                .buttonStyle(PlainButtonStyle())
                .help("Clear chat history")
                
                // TTS toggle button with voice settings
                HStack(spacing: 4) {
                    Button {
                        ttsManager.toggleEnabled()
                    } label: {
                        Image(systemName: ttsManager.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 24))
                            .tint(ttsManager.isEnabled ? .accentColor : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(ttsManager.isEnabled ? "Text-to-Speech enabled" : "Text-to-Speech disabled")
                    
                    // Voice settings button
                    Button {
                        showVoiceSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .tint(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Voice settings")
                }
                
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
                    Task { await viewModel?.sendMessage() }
                } label: {
                    if viewModel?.isResponding ?? false {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .tint(.accentColor)
                    }
                }
                .disabled((viewModel?.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) || (viewModel?.isResponding ?? false))
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
            
            // Initialize viewModel with memory manager
            if viewModel == nil {
                viewModel = ChatViewModel(memoryManager: memoryManager)
            }
            
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
            viewModel?.onNewAIMessage = { [weak ttsManager] message in
                ttsManager?.speak(message)
            }
        }
        .sheet(isPresented: $showVoiceSettings) {
            VoiceSettingsView(ttsManager: ttsManager)
        }
        .sheet(isPresented: $showSystemPromptSettings) {
            SystemPromptSettingsView(memoryManager: memoryManager, viewModel: viewModel)
        }
        .sheet(isPresented: $showChatSessions) {
            ChatSessionsView(memoryManager: memoryManager, viewModel: viewModel, showChatSessions: $showChatSessions)
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

/// Voice settings view for customizing TTS parameters
struct VoiceSettingsView: View {
    @ObservedObject var ttsManager: TextToSpeechManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // Voice Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice")
                        .font(.headline)
                    
                    Picker("Select Voice", selection: Binding(
                        get: { ttsManager.selectedVoice },
                        set: { newVoice in
                            if let voice = newVoice {
                                ttsManager.selectVoice(voice)
                            }
                        }
                    )) {
                        ForEach(ttsManager.availableVoices.filter { $0.language.hasPrefix("en") }, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))")
                                .tag(voice as AVSpeechSynthesisVoice?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                // Speech Rate
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speech Rate")
                        .font(.headline)
                    
                    HStack {
                        Text("Slow")
                            .font(.caption)
                        Slider(value: Binding(
                            get: { ttsManager.speechRate },
                            set: { ttsManager.updateSpeechRate($0) }
                        ), in: 0.0...1.0)
                        Text("Fast")
                            .font(.caption)
                    }
                    
                    Text("Current: \(String(format: "%.1f", ttsManager.speechRate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Speech Pitch
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speech Pitch")
                        .font(.headline)
                    
                    HStack {
                        Text("Low")
                            .font(.caption)
                        Slider(value: Binding(
                            get: { ttsManager.speechPitch },
                            set: { ttsManager.updateSpeechPitch($0) }
                        ), in: 0.5...2.0)
                        Text("High")
                            .font(.caption)
                    }
                    
                    Text("Current: \(String(format: "%.1f", ttsManager.speechPitch))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Speech Volume
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speech Volume")
                        .font(.headline)
                    
                    HStack {
                        Text("Quiet")
                            .font(.caption)
                        Slider(value: Binding(
                            get: { ttsManager.speechVolume },
                            set: { ttsManager.updateSpeechVolume($0) }
                        ), in: 0.0...1.0)
                        Text("Loud")
                            .font(.caption)
                    }
                    
                    Text("Current: \(String(format: "%.1f", ttsManager.speechVolume))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Test Voice Button
                Button {
                    let testText = "Hello! This is \(ttsManager.currentVoiceName) speaking. You can hear how I sound with the current settings. My speech rate is \(String(format: "%.1f", ttsManager.speechRate)), my pitch is \(String(format: "%.1f", ttsManager.speechPitch)), and my volume is \(String(format: "%.1f", ttsManager.speechVolume))."
                    ttsManager.speak(testText)
                } label: {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("Test Voice")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ttsManager.isEnabled)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Voice Settings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }
}

/// Chat sessions view for managing multiple chat conversations
struct ChatSessionsView: View {
    @ObservedObject var memoryManager: MemoryManager
    let viewModel: ChatViewModel?
    @Binding var showChatSessions: Bool
    @State private var searchText = ""
    
    var filteredSessions: [ChatSession] {
        if searchText.isEmpty {
            return memoryManager.chatSessions.sorted { $0.lastModified > $1.lastModified }
        } else {
            return memoryManager.searchSessions(searchText).sorted { $0.lastModified > $1.lastModified }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search chats...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Chat sessions list
                List(filteredSessions) { session in
                    ChatSessionRow(
                        session: session,
                        isCurrentSession: session.id == memoryManager.currentSessionId,
                        onSelect: {
                            viewModel?.switchToSession(session.id)
                            showChatSessions = false
                        },
                        onDelete: {
                            memoryManager.deleteSession(session.id)
                        }
                    )
                }
                .listStyle(.plain)
            }
            .navigationTitle("Chat Sessions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        showChatSessions = false
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }
}

/// System prompt settings view for customizing AI behavior
struct SystemPromptSettingsView: View {
    @ObservedObject var memoryManager: MemoryManager
    let viewModel: ChatViewModel?
    @Environment(\.dismiss) private var dismiss
    @State private var currentPrompt: String = ""
    @State private var showingResetAlert = false
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Prompt")
                        .font(.headline)
                    
                    Text("Customize how the AI assistant behaves. This prompt sets the personality, tone, and instructions for the AI.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // System Prompt Text Editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt Text")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextEditor(text: $currentPrompt)
                        .frame(minHeight: 200)
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .font(.system(.body, design: .monospaced))
                }
                
                // Preset Prompts
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        PresetButton(title: "Helpful Assistant", prompt: "You are a helpful, friendly chat assistant. Keep your answers concise and use natural conversational language. If you don't know something, say so politely.")
                        
                        PresetButton(title: "Creative Writer", prompt: "You are a creative writing assistant. Help users with storytelling, character development, plot ideas, and creative expression. Be imaginative and inspiring.")
                        
                        PresetButton(title: "Technical Expert", prompt: "You are a technical expert and problem solver. Provide detailed, accurate technical information. Use clear explanations and include relevant examples when helpful.")
                        
                        PresetButton(title: "Casual Friend", prompt: "You are a casual, friendly companion. Use a relaxed, conversational tone. Be supportive, empathetic, and easy to talk to.")
                    }
                }
                
                Spacer()
                
                // Action Buttons
                HStack {
                    Button("Reset to Default") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Save & Apply") {
                        saveAndApply()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("System Prompt")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
        .onAppear {
            currentPrompt = memoryManager.getSystemPrompt()
        }
        .alert("Reset System Prompt", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetToDefault()
            }
        } message: {
            Text("This will reset the system prompt to the default helpful assistant behavior. Are you sure?")
        }
    }
    
    private func saveAndApply() {
        memoryManager.updateSystemPrompt(currentPrompt)
        viewModel?.updateSystemPrompt(currentPrompt)
        dismiss()
    }
    
    private func resetToDefault() {
        memoryManager.resetSystemPrompt()
        currentPrompt = memoryManager.getSystemPrompt()
        viewModel?.updateSystemPrompt(currentPrompt)
    }
    
    @ViewBuilder
    private func PresetButton(title: String, prompt: String) -> some View {
        Button {
            currentPrompt = prompt
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(prompt.prefix(60) + "...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Individual chat session row
struct ChatSessionRow: View {
    let session: ChatSession
    let isCurrentSession: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .foregroundColor(isCurrentSession ? .accentColor : .primary)
                
                Text("\(session.messages.count) messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(session.lastModified, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isCurrentSession {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark) // Enforce dark mode in preview
}
