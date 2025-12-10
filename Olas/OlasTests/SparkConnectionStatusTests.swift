import Testing
import SwiftUI
@testable import Olas

@Suite("SparkConnectionStatus")
struct SparkConnectionStatusTests {

    // MARK: - Icon

    @Suite("icon")
    struct IconTests {

        @Test("Disconnected shows slash icon")
        func disconnected_icon() {
            let status = SparkConnectionStatus.disconnected

            #expect(status.icon == "bolt.slash.fill")
        }

        @Test("Connecting shows horizontal bolt icon")
        func connecting_icon() {
            let status = SparkConnectionStatus.connecting

            #expect(status.icon == "bolt.horizontal.fill")
        }

        @Test("Connected shows bolt icon")
        func connected_icon() {
            let status = SparkConnectionStatus.connected

            #expect(status.icon == "bolt.fill")
        }

        @Test("Error shows warning icon")
        func error_icon() {
            let status = SparkConnectionStatus.error("Test error")

            #expect(status.icon == "exclamationmark.triangle.fill")
        }
    }

    // MARK: - Color

    @Suite("color")
    struct ColorTests {

        @Test("Disconnected is secondary color")
        func disconnected_color() {
            let status = SparkConnectionStatus.disconnected

            #expect(status.color == .secondary)
        }

        @Test("Connecting is orange")
        func connecting_color() {
            let status = SparkConnectionStatus.connecting

            #expect(status.color == .orange)
        }

        @Test("Connected is zap gold")
        func connected_color() {
            let status = SparkConnectionStatus.connected

            #expect(status.color == OlasTheme.Colors.zapGold)
        }

        @Test("Error is red")
        func error_color() {
            let status = SparkConnectionStatus.error("Test error")

            #expect(status.color == .red)
        }
    }

    // MARK: - Description

    @Suite("description")
    struct DescriptionTests {

        @Test("Disconnected description")
        func disconnected_description() {
            let status = SparkConnectionStatus.disconnected

            #expect(status.description == "Not Connected")
        }

        @Test("Connecting description")
        func connecting_description() {
            let status = SparkConnectionStatus.connecting

            #expect(status.description == "Connecting...")
        }

        @Test("Connected description")
        func connected_description() {
            let status = SparkConnectionStatus.connected

            #expect(status.description == "Connected")
        }

        @Test("Error description includes message")
        func error_description() {
            let status = SparkConnectionStatus.error("Network timeout")

            #expect(status.description == "Error: Network timeout")
        }

        @Test("Error with empty message")
        func error_emptyMessage_description() {
            let status = SparkConnectionStatus.error("")

            #expect(status.description == "Error: ")
        }
    }

    // MARK: - Equatable

    @Suite("Equatable")
    struct EquatableTests {

        @Test("Same status equals")
        func sameStatus_equals() {
            #expect(SparkConnectionStatus.disconnected == SparkConnectionStatus.disconnected)
            #expect(SparkConnectionStatus.connecting == SparkConnectionStatus.connecting)
            #expect(SparkConnectionStatus.connected == SparkConnectionStatus.connected)
        }

        @Test("Different status not equal")
        func differentStatus_notEqual() {
            #expect(SparkConnectionStatus.disconnected != SparkConnectionStatus.connecting)
            #expect(SparkConnectionStatus.connecting != SparkConnectionStatus.connected)
            #expect(SparkConnectionStatus.connected != SparkConnectionStatus.disconnected)
        }

        @Test("Error with same message equals")
        func errorSameMessage_equals() {
            let error1 = SparkConnectionStatus.error("Test")
            let error2 = SparkConnectionStatus.error("Test")

            #expect(error1 == error2)
        }

        @Test("Error with different message not equal")
        func errorDifferentMessage_notEqual() {
            let error1 = SparkConnectionStatus.error("Test 1")
            let error2 = SparkConnectionStatus.error("Test 2")

            #expect(error1 != error2)
        }

        @Test("Error not equal to other status")
        func error_notEqualToOther() {
            let error = SparkConnectionStatus.error("Test")

            #expect(error != SparkConnectionStatus.disconnected)
            #expect(error != SparkConnectionStatus.connecting)
            #expect(error != SparkConnectionStatus.connected)
        }
    }
}
