//
//  FoundationModelsTest.swift
//  llmt2
//
//  Created for debugging FoundationModels availability
//

import Foundation
import FoundationModels

/// Test class to verify FoundationModels framework availability
class FoundationModelsTest {
    
    static func testAvailability() -> String {
        var results: [String] = []
        
        // Test 1: Check if FoundationModels can be imported
        results.append("✅ FoundationModels framework imported successfully")
        
        // Test 2: Check if LanguageModelSession class exists
        if LanguageModelSession.self != nil {
            results.append("✅ LanguageModelSession class is available")
        } else {
            results.append("❌ LanguageModelSession class not found")
        }
        
        // Test 3: Try to create a basic session
        do {
            let testSession = LanguageModelSession()
            results.append("✅ LanguageModelSession can be created")
        } catch {
            results.append("❌ Failed to create LanguageModelSession: \(error)")
        }
        
        return results.joined(separator: "\n")
    }
    
    static func runTests() {
        print("🧪 Testing FoundationModels availability...")
        print(testAvailability())
    }
}
