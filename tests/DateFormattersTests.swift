/**
 * DateFormattersTests.swift
 * Unit tests for DateFormatters
 */

import Foundation

struct DateFormattersTests {
    static func runAll() async {
        await TestRunner.run(suite: "DateFormatters Tests") {
            testExifDateParsing()
            testExifDateParsingInvalid()
            testDisplayFormatNotEmpty()
            testFormatterReuse()
        }
    }
    
    static func testExifDateParsing() {
        let dateString = "2024:06:15 14:30:45"
        let parsed = DateFormatters.parseExifDate(dateString)
        
        TestRunner.assertNotNil(parsed, "Valid EXIF date string is parsed")
        
        if let date = parsed {
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            
            TestRunner.assertEqual(components.year, 2024, "Year is correct")
            TestRunner.assertEqual(components.month, 6, "Month is correct")
            TestRunner.assertEqual(components.day, 15, "Day is correct")
            TestRunner.assertEqual(components.hour, 14, "Hour is correct")
            TestRunner.assertEqual(components.minute, 30, "Minute is correct")
            TestRunner.assertEqual(components.second, 45, "Second is correct")
        }
    }
    
    static func testExifDateParsingInvalid() {
        let invalidStrings = [
            "",
            "invalid",
            "2024-06-15 14:30:45",  // Wrong format (dashes instead of colons)
            "2024:06:15",           // Missing time
        ]
        
        for dateString in invalidStrings {
            let parsed = DateFormatters.parseExifDate(dateString)
            TestRunner.assertNil(parsed, "Invalid EXIF date '\(dateString)' returns nil")
        }
    }
    
    static func testDisplayFormatNotEmpty() {
        let testDate = Date()
        let formatted = DateFormatters.formatForDisplay(testDate)
        
        TestRunner.assert(!formatted.isEmpty, "Display formatter produces non-empty string")
        TestRunner.assert(formatted.count > 5, "Display format has reasonable length")
    }
    
    static func testFormatterReuse() {
        // Verify that formatters are reused (same instance)
        let formatter1 = DateFormatters.displayFormatter
        let formatter2 = DateFormatters.displayFormatter
        
        TestRunner.assert(formatter1 === formatter2, "Display formatter is reused (same instance)")
        
        let exifFormatter1 = DateFormatters.exifFormatter
        let exifFormatter2 = DateFormatters.exifFormatter
        
        TestRunner.assert(exifFormatter1 === exifFormatter2, "EXIF formatter is reused (same instance)")
    }
}

