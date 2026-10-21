import XCTest
import CompanionProtocol
@testable import CANCompanion

final class OutputCatalogEditabilityTests: XCTestCase {
    func testKnownOutputMissingFromCatalogIsReadOnly() throws {
        let catalog = try OutputCatalog(decoding: Data(#"{"outputs":[]}"#.utf8))
        let binding = try output(#"{"type":"led_fill","action":"brake","zone":{"start":0,"length":10,"direction":"start_to_end"},"color":{"red":255,"green":0,"blue":0}}"#)

        XCTAssertFalse(OutputCatalogEditor.isEditable(binding, in: catalog))
    }

    func testKnownOutputWithUnsupportedCatalogFieldKindIsReadOnly() throws {
        let catalog = try OutputCatalog(decoding: Data(#"{"outputs":[{"type":"led_fill","sink":"local_argb","fields":[{"name":"action","kind":"action","required":true},{"name":"future","kind":"vendor_custom","required":false}]}]}"#.utf8))
        let binding = try output(#"{"type":"led_fill","action":"brake","zone":{"start":0,"length":10,"direction":"start_to_end"},"color":{"red":255,"green":0,"blue":0}}"#)

        XCTAssertFalse(OutputCatalogEditor.isEditable(binding, in: catalog))
    }

    func testKnownOutputWithEditableCatalogRemainsEditable() throws {
        let catalog = try OutputCatalog(decoding: Data(#"{"outputs":[{"type":"led_fill","sink":"local_argb","fields":[{"name":"action","kind":"action","required":true},{"name":"zone","kind":"zone","required":true,"pixels":100,"directions":["start_to_end"]},{"name":"color","kind":"rgb","required":true,"min":0,"max":255}]}]}"#.utf8))
        let binding = try output(#"{"type":"led_fill","action":"brake","zone":{"start":0,"length":10,"direction":"start_to_end"},"color":{"red":255,"green":0,"blue":0}}"#)

        XCTAssertTrue(OutputCatalogEditor.isEditable(binding, in: catalog))
    }

    private func output(_ json: String) throws -> ControllerConfig.OutputBinding {
        try JSONDecoder().decode(ControllerConfig.OutputBinding.self, from: Data(json.utf8))
    }
}
