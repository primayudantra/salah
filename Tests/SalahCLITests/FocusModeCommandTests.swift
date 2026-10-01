import Foundation
import SalahCore
import XCTest
@testable import salah

final class FocusModeCommandTests: XCTestCase {
    private var configURL: URL!

    override func setUp() {
        super.setUp()
        configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("salah-pm-cli-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
        setenv("SALAH_CONFIG_PATH", configURL.path, 1)
    }

    override func tearDown() {
        unsetenv("SALAH_CONFIG_PATH")
        super.tearDown()
    }

    func testParsesSubcommands() throws {
        XCTAssertTrue(try Salah.parseAsRoot(["focus-mode"]) is FocusModeCommand.Status)
        XCTAssertTrue(try Salah.parseAsRoot(["focus-mode", "on"]) is FocusModeCommand.On)
        XCTAssertTrue(try Salah.parseAsRoot(["focus-mode", "off"]) is FocusModeCommand.Off)
        XCTAssertTrue(try Salah.parseAsRoot(["focus-mode", "status", "--json"]) is FocusModeCommand.Status)
    }

    func testOnOffRoundTripThroughConfig() async throws {
        let onCode = await Main.run(["focus-mode", "on"])
        XCTAssertEqual(onCode, 0)
        XCTAssertTrue(try ConfigStore(url: configURL).load().focusMode.enabled)
        let offCode = await Main.run(["focus-mode", "off"])
        XCTAssertEqual(offCode, 0)
        XCTAssertFalse(try ConfigStore(url: configURL).load().focusMode.enabled)
    }

    func testStatusJSONReflectsConfig() throws {
        var c = SalahConfig.default
        c.focusMode.enabled = true
        c.focusMode.prayers = [.asr, .isha]
        try ConfigStore(url: configURL).save(c)

        let s = try FocusModeCommand.Status.render(config: c, appRunning: false, output: try OutputOptions.parse(["--json"]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
        XCTAssertEqual(json["enabled"] as? Bool, true)
        XCTAssertEqual(json["prayers"] as? [String], ["Asr", "Isha"])
        XCTAssertEqual(json["appRunning"] as? Bool, false)
    }

    func testStatusNeverClaimsScheduling() throws {
        let s = try FocusModeCommand.Status.render(config: .default, appRunning: false, output: try OutputOptions.parse(["--plain"]))
        XCTAssertTrue(s.contains("only runs while the app is open"))
    }

    func testSavedMessageNeverClaimsRunningWhenAppIsNotRunning() {
        let msg = FocusModeCommand.savedMessage("Focus Mode on.", appRunning: false)
        XCTAssertEqual(msg, "Saved. Focus Mode on. Focus Mode takes effect when Salah.app is running.")
    }
}
