# LLMT2 Development Agents

## Development Environment Requirements

This project requires specific Apple development tools and frameworks that are only available in beta versions:

### Required Software Versions
- **macOS**: 26.0 Beta (Tahoe) - Development and target platform
- **Xcode**: 26.0 Beta
- **macOS SDK**: 26.0 Beta
- **Target macOS**: 26.0+

### Critical Framework Dependencies

#### FoundationModels Framework
- **Availability**: iOS 26.0+, iPadOS 26.0+, macOS 26.0+, visionOS 26.0+ (Beta)
- **Import**: `import FoundationModels`
- **Key Classes**:
  - `LanguageModelSession`: Core class for interacting with on-device language models
  - `SystemLanguageModel`: Default system language model
  - `Instructions`: For configuring model behavior
  - `Transcript`: For maintaining conversation history

#### LanguageModelSession Usage
```swift
import FoundationModels

// Create a session with custom instructions
let session = LanguageModelSession(instructions: """
    You are a helpful, friendly chat assistant. Keep your answers concise and use natural conversational language.
    """)

// Send a prompt and get response
let response = try await session.respond(to: "Hello, how are you?")
```

### Development Notes

#### Why Beta Software is Required
- `FoundationModels` is a new framework introduced in iOS 26 beta
- This framework provides on-device language model capabilities
- The framework is not available in stable iOS versions
- Xcode 26 beta includes the necessary SDK headers and frameworks

#### Speech Recognition Integration
- Uses standard `Speech` framework (available in stable macOS)
- Requires microphone permissions via `AVCaptureDevice`
- Integrates with `LanguageModelSession` for voice-to-text-to-LLM workflow

#### Project Structure
- SwiftUI-based chat interface
- `@Observable` pattern for state management
- Persistent message storage using `UserDefaults`
- Dark mode optimized UI

### Troubleshooting

#### Common Issues
1. **Build Errors**: Ensure Xcode 26 beta is installed and project targets macOS 26.0+
2. **Import Errors**: Verify `FoundationModels` is available in your Xcode version
3. **Runtime Crashes**: Check that you're running macOS 26 beta
4. **Speech Recognition**: Verify microphone permissions are granted in System Preferences

#### Development Workflow
1. Use Xcode 26 beta for all development
2. Test on macOS 26 beta
3. Ensure all team members have access to beta software
4. Document any beta-specific workarounds or limitations

### Future Considerations

When macOS 26 becomes stable:
- Update deployment targets to stable versions
- Remove beta-specific workarounds
- Update documentation to reflect stable availability
- Consider backward compatibility strategies

---

**Note**: This project leverages cutting-edge Apple AI capabilities that are currently in beta. Ensure all development team members have access to the required beta software and understand the limitations of working with pre-release frameworks.
