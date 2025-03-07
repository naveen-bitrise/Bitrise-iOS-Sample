//
//  BitriseTestUITests.swift
//  BitriseTestUITests
//
//  Created by Damien Murphy on 1/28/21.
//

import XCTest

class BitriseTestUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "Final State"
        add(attachment)
    }
    
    // Helper method for taking named screenshots during tests
    func takeScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()
        
        // Take a screenshot after launch
        takeScreenshot(name: "App Launched")

        // Use recording to get started writing UI tests.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
            
            // Take a screenshot after performance measurement
            takeScreenshot(name: "After Launch Performance Test")
        }
    }
    
    static var executionCount = 0
    
    func testWithCountBasedFailure() throws {
        // Track execution count for this test
        BitriseTestUITests.executionCount += 1
        
        let app = XCUIApplication()
        app.launch()
        
        takeScreenshot(name: "After Launch for testWithCountBasedFailure")
        
        // Fail on first two attempts, succeed on third
        XCTAssertGreaterThanOrEqual(BitriseTestUITests.executionCount, 3,
            "Simulating failure that should pass on 3rd attempt")
        
        // Rest of your test...
    }
}
