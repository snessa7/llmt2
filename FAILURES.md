# LLMT2 Development Failures

This document tracks features that were attempted but failed during development, along with the reasons for failure and potential solutions for future implementation.

## Message Export Feature (Attempted: September 6, 2025)

### What Was Attempted
- Implemented SwiftUI `fileExporter` modifier for exporting chat history
- Created `ChatExportDocument` struct conforming to `FileDocument` protocol
- Added export button to UI with proper state management
- Used modern SwiftUI file export APIs instead of legacy `NSSavePanel`

### Why It Failed
1. **App Crashes**: The export functionality caused the app to crash consistently
2. **Multiple Initialization Issues**: The `ChatViewModel` was being initialized multiple times, causing memory issues
3. **SwiftUI File Export Complexity**: The `fileExporter` modifier proved more complex than expected in this context
4. **FoundationModels Integration Conflicts**: The export feature seemed to interfere with the `LanguageModelSession` initialization

### Technical Details
- **Error Pattern**: App would crash with "zsh: abort" when export button was clicked
- **Root Cause**: Likely related to SwiftUI's file export system conflicting with the app's existing architecture
- **Attempted Solutions**:
  - Used SwiftUI's native `fileExporter` instead of `NSSavePanel`
  - Added proper error handling and state management
  - Implemented `FileDocument` protocol correctly
  - Added comprehensive logging

### Files Modified
- `llmt2/ContentView.swift`: Added export functionality, then removed
- Added `UniformTypeIdentifiers` import
- Created `ChatExportDocument` struct
- Added export button and state management

### Future Implementation Suggestions
1. **Alternative Approach**: Consider using a simpler text file writing approach
2. **Separate Export Service**: Create a dedicated export service class
3. **Async Export**: Implement export as a background operation
4. **User Feedback**: Add better progress indicators and error messages
5. **Testing**: Implement comprehensive testing before adding to main app

### Status
- **Status**: CANCELLED
- **Date Removed**: September 6, 2025
- **Reason**: Causing app crashes and instability
- **Future**: Will revisit after core app stability is improved

---

*This document will be updated as new failures are encountered and resolved.*
