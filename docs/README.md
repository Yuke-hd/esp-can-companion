# Documentation

Start with the documents relevant to the change. This follows the documentation
categories in the [controller repository](https://github.com/Yuke-hd/mazda-can-accessory-controller/tree/main/docs),
without creating empty categories or copying firmware specifications.

| Category | Purpose | Starting point |
| --- | --- | --- |
| Architecture | Module responsibilities, replaceable boundaries, and dependency direction. | [Module boundaries](architecture/module-boundaries.md) |
| Specs | Agreed feature and preview behavior, including explicitly identified implementation gaps. | [Preview scenarios](specs/ui/preview-scenarios.md), [design reference](specs/ui/design-reference.md) |
| Development | How contributors and agents build, preview, and verify changes. | [UI verification](development/ui-verification.md) |
| Decisions | Why a significant architectural choice was made and its alternatives. | [ADR index](decisions/README.md) |
| Templates | Reusable document formats. | [ADR template](templates/ADR.md) |

## Authority and implementation status

- Specs record agreed behavior. They explicitly mark checks that need future
  implementation; their existence does not imply that a feature works today.
- Architecture describes current boundaries and how to extend them. An ADR
  explains a decision; detailed workflows and feature behavior live separately.
- Design drafts guide appearance. They do not establish protocol support or
  override confirmed controller state, freshness, or configuration validation.
- GitHub issues track the remaining implementation work. An open issue or an old
  verification report is not evidence that the current app passes a check.
- The firmware repository owns the [BLE protocol](https://github.com/Yuke-hd/mazda-can-accessory-controller/blob/main/docs/specs/companion/ble-protocol.md),
  [config transfer](https://github.com/Yuke-hd/mazda-can-accessory-controller/blob/main/docs/specs/companion/config-transfer.md),
  and [live signal](https://github.com/Yuke-hd/mazda-can-accessory-controller/blob/main/docs/specs/companion/live-signals.md)
  contracts. Keep local codec examples tied to their source version.

Build setup, personal-device signing, and project orientation remain in the
[root README](../README.md). We do not maintain a second copy here.
