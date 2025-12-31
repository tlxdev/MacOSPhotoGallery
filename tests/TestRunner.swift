/**
 * TestRunner.swift
 * Simple test runner for PhotoViewer unit tests
 */

import Foundation

/// Simple test framework
struct TestRunner {
    private static var passedTests = 0
    private static var failedTests = 0
    private static var currentSuite = ""
    
    static func run(suite: String, _ block: () async throws -> Void) async {
        currentSuite = suite
        print("\n--- Running: \(suite) ---")
        
        do {
            try await block()
        } catch {
            print("  SUITE ERROR: \(error)")
            failedTests += 1
        }
    }
    
    static func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        if condition {
            passedTests += 1
            print("  PASS: \(message)")
        } else {
            failedTests += 1
            print("  FAIL: \(message) (\(file):\(line))")
        }
    }
    
    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, file: String = #file, line: Int = #line) {
        if actual == expected {
            passedTests += 1
            print("  PASS: \(message)")
        } else {
            failedTests += 1
            print("  FAIL: \(message) - Expected '\(expected)', got '\(actual)' (\(file):\(line))")
        }
    }
    
    static func assertNil<T>(_ value: T?, _ message: String, file: String = #file, line: Int = #line) {
        if value == nil {
            passedTests += 1
            print("  PASS: \(message)")
        } else {
            failedTests += 1
            print("  FAIL: \(message) - Expected nil, got '\(value!)' (\(file):\(line))")
        }
    }
    
    static func assertNotNil<T>(_ value: T?, _ message: String, file: String = #file, line: Int = #line) {
        if value != nil {
            passedTests += 1
            print("  PASS: \(message)")
        } else {
            failedTests += 1
            print("  FAIL: \(message) - Expected non-nil value (\(file):\(line))")
        }
    }
    
    static func printSummary() {
        print("\n========================================")
        print("Test Results:")
        print("  Passed: \(passedTests)")
        print("  Failed: \(failedTests)")
        print("  Total:  \(passedTests + failedTests)")
        print("========================================")
        
        if failedTests > 0 {
            print("\nSome tests failed!")
            exit(1)
        } else {
            print("\nAll tests passed!")
            exit(0)
        }
    }
}

// MARK: - Main Entry Point

@main
struct TestMain {
    static func main() async {
        print("PhotoViewer Unit Tests")
        print("======================")
        
        // Run all test suites
        await LRUCacheTests.runAll()
        await DateFormattersTests.runAll()
        await PhotoItemTests.runAll()
        
        // Print summary
        TestRunner.printSummary()
    }
}

