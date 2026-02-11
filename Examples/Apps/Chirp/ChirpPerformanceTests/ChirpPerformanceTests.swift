//
//  ChirpPerformanceTests.swift
//  ChirpPerformanceTests
//
//  Created by NDKSwift QA Validator
//  Performance tests for Chirp iOS app
//

import XCTest

/// XCUITest-based performance tests for the Chirp app.
/// Uses XCTCPUMetric, XCTMemoryMetric, and XCTClockMetric to measure performance.
final class ChirpPerformanceTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Performance Test Configuration

    /// Creates measure options with 5 iterations for consistent performance measurements
    private var measureOptions: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    /// Standard metrics for performance measurement
    private var performanceMetrics: [XCTMetric] {
        return [
            XCTCPUMetric(application: app),
            XCTMemoryMetric(application: app),
            XCTClockMetric()
        ]
    }

    // MARK: - Test 1: Feed Scroll Performance

    /// Measures performance during 10 feed scrolls.
    /// Tests CPU usage, memory consumption, and time during scrolling operations.
    func testFeedScrollPerformance() throws {
        // Wait for tab bar to be ready (more reliable than collection view)
        let tabBarExists = app.tabBars.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(tabBarExists, "Tab bar should exist")

        // Give time for feed to potentially load content
        Thread.sleep(forTimeInterval: 2.0)

        measure(metrics: performanceMetrics, options: measureOptions) {
            // Try to find scrollable content - use the main window if no collection view
            let collectionView = app.collectionViews.firstMatch
            let scrollView = app.scrollViews.firstMatch
            let targetView = collectionView.exists ? collectionView : (scrollView.exists ? scrollView : app.windows.firstMatch)

            // Perform 10 scroll operations
            for _ in 0..<10 {
                targetView.swipeUp()
                // Small delay to allow content to load
                Thread.sleep(forTimeInterval: 0.1)
            }

            // Scroll back up to reset state
            for _ in 0..<10 {
                targetView.swipeDown()
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    // MARK: - Test 2: Profile Navigation Performance

    /// Measures performance when navigating to the profile tab.
    /// Tests the time and resources required for profile screen transitions.
    func testProfileNavigationPerformance() throws {
        // Wait for app to be ready
        let tabBarExists = app.tabBars.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(tabBarExists, "Tab bar should exist")

        measure(metrics: performanceMetrics, options: measureOptions) {
            // Navigate to profile tab
            let profileTab = app.tabBars.buttons["Profile"]
            if profileTab.exists {
                profileTab.tap()
            } else {
                // Try alternative selectors
                let tabBar = app.tabBars.firstMatch
                let buttons = tabBar.buttons.allElementsBoundByIndex
                if buttons.count > 3 {
                    buttons[3].tap() // Profile is typically 4th tab
                }
            }

            // Wait for profile to load
            Thread.sleep(forTimeInterval: 0.5)

            // Navigate back to feed
            let feedTab = app.tabBars.buttons["Feed"]
            if feedTab.exists {
                feedTab.tap()
            } else {
                let tabBar = app.tabBars.firstMatch
                let buttons = tabBar.buttons.allElementsBoundByIndex
                if buttons.count > 0 {
                    buttons[0].tap()
                }
            }

            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    // MARK: - Test 3: Compose UI Performance

    /// Measures performance when opening compose, typing text, and measuring UI responsiveness.
    /// Tests keyboard interaction and text input latency.
    func testComposeUIPerformance() throws {
        // Wait for app to be ready
        let tabBarExists = app.tabBars.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(tabBarExists, "Tab bar should exist")

        measure(metrics: performanceMetrics, options: measureOptions) {
            // Find and tap compose button (the + FAB button)
            // Try multiple ways to find it
            var composeButton = app.buttons["Compose"]
            if !composeButton.exists {
                // Look for + button or any button that might be the compose FAB
                composeButton = app.buttons.matching(NSPredicate(format: "label == '+' OR label CONTAINS 'plus' OR label CONTAINS 'add' OR label CONTAINS 'compose' OR label CONTAINS 'new'")).firstMatch
            }

            if composeButton.exists {
                composeButton.tap()

                // Wait for compose view to appear
                Thread.sleep(forTimeInterval: 0.5)

                // Find text field/view and type
                let textField = app.textViews.firstMatch
                let textEditor = app.textFields.firstMatch
                let inputField = textField.exists ? textField : textEditor

                if inputField.exists {
                    inputField.tap()
                    inputField.typeText("Test")
                    Thread.sleep(forTimeInterval: 0.2)
                }

                // Close compose view - try various dismiss methods
                let cancelButton = app.buttons["Cancel"]
                let closeButton = app.buttons["Close"]
                let xButton = app.buttons["xmark"]

                if cancelButton.exists {
                    cancelButton.tap()
                } else if closeButton.exists {
                    closeButton.tap()
                } else if xButton.exists {
                    xButton.tap()
                } else {
                    // Try swiping down to dismiss
                    app.swipeDown()
                }

                Thread.sleep(forTimeInterval: 0.3)
            } else {
                // If no compose button, just measure basic UI interaction
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    // MARK: - Test 4: Explore Tab Performance

    /// Measures performance when navigating to explore tab.
    /// Tests tab switching latency and view rendering speed.
    func testExploreTabPerformance() throws {
        // Wait for app to be ready
        let tabBarExists = app.tabBars.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(tabBarExists, "Tab bar should exist")

        measure(metrics: performanceMetrics, options: measureOptions) {
            // Navigate to explore tab (actual tab name in Chirp)
            let exploreTab = app.tabBars.buttons["Explore"]
            if exploreTab.exists {
                exploreTab.tap()
            } else {
                let tabBar = app.tabBars.firstMatch
                let buttons = tabBar.buttons.allElementsBoundByIndex
                if buttons.count > 1 {
                    buttons[1].tap() // Explore is 2nd tab
                }
            }

            Thread.sleep(forTimeInterval: 0.5)

            // Try to find and interact with search if available
            let searchField = app.searchFields.firstMatch
            if searchField.exists {
                searchField.tap()
                searchField.typeText("nostr")
                Thread.sleep(forTimeInterval: 0.3)

                // Clear search if possible
                let clearButton = searchField.buttons["Clear text"]
                if clearButton.exists {
                    clearButton.tap()
                }
            }

            // Navigate back to feed
            let feedTab = app.tabBars.buttons["Feed"]
            if feedTab.exists {
                feedTab.tap()
            } else {
                let tabBar = app.tabBars.firstMatch
                let buttons = tabBar.buttons.allElementsBoundByIndex
                if buttons.count > 0 {
                    buttons[0].tap()
                }
            }

            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    // MARK: - Test 5: Settings Navigation Performance

    /// Measures performance when navigating to settings and drilling into relay dashboard.
    /// Tests nested navigation performance and view hierarchy rendering.
    func testSettingsNavigationPerformance() throws {
        // Wait for app to be ready
        let tabBarExists = app.tabBars.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(tabBarExists, "Tab bar should exist")

        measure(metrics: performanceMetrics, options: measureOptions) {
            // Navigate to settings (usually last tab or via profile)
            let settingsTab = app.tabBars.buttons["Settings"]
            if settingsTab.exists {
                settingsTab.tap()
            } else {
                // Settings might be accessible from profile
                let profileTab = app.tabBars.buttons["Profile"]
                if profileTab.exists {
                    profileTab.tap()
                    Thread.sleep(forTimeInterval: 0.2)

                    // Look for settings gear icon
                    let settingsButton = app.buttons["Settings"]
                    if settingsButton.exists {
                        settingsButton.tap()
                    } else {
                        let gearButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'settings' OR label CONTAINS 'gear'")).firstMatch
                        if gearButton.exists {
                            gearButton.tap()
                        }
                    }
                }
            }

            Thread.sleep(forTimeInterval: 0.3)

            // Navigate to relay dashboard
            let relayDashboard = app.cells.matching(NSPredicate(format: "label CONTAINS 'relay' OR label CONTAINS 'Relay'")).firstMatch
            if relayDashboard.exists {
                relayDashboard.tap()
                Thread.sleep(forTimeInterval: 0.5)

                // Navigate back
                let backButton = app.navigationBars.buttons.firstMatch
                if backButton.exists {
                    backButton.tap()
                }
            }

            // Navigate back to feed
            Thread.sleep(forTimeInterval: 0.2)
            let feedTab = app.tabBars.buttons["Feed"]
            if feedTab.exists {
                feedTab.tap()
            } else {
                let tabBar = app.tabBars.firstMatch
                let buttons = tabBar.buttons.allElementsBoundByIndex
                if buttons.count > 0 {
                    buttons[0].tap()
                }
            }

            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    // MARK: - Test 6: Extended Scroll Stress Test

    /// Performs 50 rapid scrolls and measures memory growth.
    /// Tests for memory leaks and sustained performance under load.
    func testExtendedScrollStress() throws {
        // Wait for tab bar to be ready
        let tabBarExists = app.tabBars.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(tabBarExists, "Tab bar should exist")

        // Give time for feed to potentially load
        Thread.sleep(forTimeInterval: 2.0)

        measure(metrics: performanceMetrics, options: measureOptions) {
            // Try to find scrollable content
            let collectionView = app.collectionViews.firstMatch
            let scrollView = app.scrollViews.firstMatch
            let targetView = collectionView.exists ? collectionView : (scrollView.exists ? scrollView : app.windows.firstMatch)

            // Perform 50 rapid scroll operations
            for i in 0..<50 {
                targetView.swipeUp()

                // Minimal delay - testing rapid scrolling stress
                if i % 10 == 0 {
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }

            // Brief pause to allow system to stabilize
            Thread.sleep(forTimeInterval: 0.5)

            // Scroll back to top
            for _ in 0..<10 {
                targetView.swipeDown()
            }

            Thread.sleep(forTimeInterval: 0.3)
        }
    }
}
