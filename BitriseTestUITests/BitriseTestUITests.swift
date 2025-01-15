//
//  BitriseTestUITests.swift
//  BitriseTestUITests
//
//  Created by Damien Murphy on 1/28/21.
//

import XCTest
import Swifter

class BitriseTestUITests: XCTestCase {

    private var app: XCUIApplication!
    private var server: HttpServer!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        server = HttpServer()
    }
    
    override func tearDown() {
        server.stop()
        server = nil
        app = nil
        super.tearDown()
    }
    
    func testHTTPCallSuccess() throws {
        // Start the mock server
        try server.start(8080)
        server.GET["/test"] = { _ in
            HttpResponse.ok(.text("Hello from UI Test!"))
        }
        
        // Launch the app
        app.launch()
        
        // Tap the Make HTTP Call button
        let makeCallButton = app.buttons["Make HTTP Call"]
        XCTAssertTrue(makeCallButton.exists)
        makeCallButton.tap()
        
        // Check for success message
        let successText = app.staticTexts["Success: Hello from UI Test!"]
        XCTAssertTrue(successText.waitForExistence(timeout: 5))
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
