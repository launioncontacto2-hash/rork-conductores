//
//  TurnoEVUITests.swift
//  TurnoEVUITests
//
//  Created by Rork on August 16, 2026.
//

import XCTest

final class TurnoEVUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it's important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testAcquisitionProviderRequestVisualContract() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--acquisition-preview-provider"]
        app.launch()

        XCTAssertTrue(app.buttons["Solicitudes"].waitForExistence(timeout: 8))
        app.buttons["Solicitudes"].tap()
        let providerCard = app.descendants(matching: .any)
            .matching(identifier: "acquisition-provider-request-card").firstMatch
        XCTAssertTrue(providerCard.waitForExistence(timeout: 5))
        XCTAssertTrue(providerCard.label.contains("Solicitados"))
        XCTAssertTrue(providerCard.label.contains("$295,000"))
        XCTAssertTrue(app.buttons["Ver condiciones de entrega"].exists)
        XCTAssertFalse(app.staticTexts["Ver requisitos"].exists)
        keepScreenshot(named: "Proveedor-solicitud-aprobada")
    }

    @MainActor
    func testAcquisitionAdminRequestVisualContract() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--acquisition-preview-admin"]
        app.launch()

        XCTAssertTrue(app.buttons["Solicitudes"].waitForExistence(timeout: 8))
        app.buttons["Solicitudes"].tap()
        let adminCard = app.descendants(matching: .any)
            .matching(identifier: "acquisition-admin-request-card").firstMatch
        XCTAssertTrue(adminCard.waitForExistence(timeout: 5))
        XCTAssertTrue(adminCard.label.contains("Precio máximo: $295,000"))
        XCTAssertFalse(app.staticTexts["Ver solicitud"].exists)
        keepScreenshot(named: "DORI-solicitud-unificada")
    }

    @MainActor
    func testAcquisitionCalendarIsSpanish() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--acquisition-preview-calendar"]
        app.launch()

        let deadlinePicker = app.buttons["acquisition-request-deadline-picker"]
        XCTAssertTrue(deadlinePicker.waitForExistence(timeout: 5))
        deadlinePicker.tap()
        XCTAssertTrue(app.staticTexts["Fecha límite para recibir ofertas"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "September")
            ).firstMatch.exists
        )
        keepScreenshot(named: "Calendario-espanol")
    }

    @MainActor
    func testAcquisitionPhotoReviewUsesApprovedSpanishActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--acquisition-preview-photo-review"]
        app.launch()

        XCTAssertTrue(app.buttons["Repetir"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Usar foto"].exists)
        keepScreenshot(named: "Captura-repetir-usar-foto")
    }

    @MainActor
    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
