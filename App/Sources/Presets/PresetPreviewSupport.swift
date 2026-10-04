#if DEBUG
import Foundation
import CompanionFakes
import PresetSync

/// An in-memory controller for previews, running the factory config, with
/// enough delay to see the upload progress and the restart.
enum PresetPreviewSupport {
    static func link() -> FakePresetSyncLink {
        let controller = FakeController()
        let factory = (try? PresetCatalog.resource("factory.json")) ?? Data()
        controller.factoryDocument = factory
        controller.activeDocument = factory
        controller.writeDelay = .milliseconds(40)
        return FakePresetSyncLink(controller: controller, restartDelay: .seconds(2))
    }
}
#endif
