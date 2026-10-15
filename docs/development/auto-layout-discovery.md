# Auto-layout discovery verification

Integration report for [#41](https://github.com/Yuke-hd/esp-can-companion/issues/41),
verified on 2026-10-13. Child-issue software acceptance is supported by package,
app, integration and rendered journey evidence below. Physical release gates
remain unrun. GitHub issues track implementation; merges and deployment remain
separate owner decisions.

## Contract and fixture

The frozen wire contract is firmware [PR #255](https://github.com/Yuke-hd/mazda-can-accessory-controller/pull/255)
at `251444d62600c7582943a409012b5f0c0ffef401`. Firmware integration
[PR #265](https://github.com/Yuke-hd/mazda-can-accessory-controller/pull/265) is
pinned at `1800d825a95baa041c178645a2475302d4ac57f6`. Both are approved with
passing CI and remain unmerged; that status is separate from app validation.

The canonical synthetic fixture is `extensible-live-v1`, version 1, vendored at
`Packages/CompanionKit/Tests/CompanionProtocolTests/Fixtures/golden-vectors/extensible-live-v1.json`.
The integration coordinator confirmed byte-for-byte equality with the firmware
fixture using `cmp`. This fixture's provenance differs from the older
spec-derived files described by the existing golden-vector README. Re-copy the
canonical fixture when its source changes; do not hand-edit it. The vectors
contain no vehicle captures, identifiers, personal data, or secrets.
The 8,455-byte Swift fixture matches the supplied firmware oracle. This report
records byte agreement and Swift checks; it does not claim sibling C++ test
execution by the app agents.
The vendored fixture SHA-256 is
`f7211540848f8bf87ed72080ae3cc6fd2aa04414469be0a60d9f1a39fc2d06bc`;
this digest was rechecked in the #50 integration tree below.

The extensible path requires version 1, the usable capability flag, catalog and
stream endpoints, and a complete valid catalog. Missing or unusable capability,
missing endpoints, or discovery failure must produce telemetry-unavailable
state without subscribing to legacy telemetry. Historical layout 1/2 codecs
remain separately available for compatibility and parity tests.

## Dependency order and review units

These are focused stacked PRs, not one combined implementation PR. The actual
published chain serializes integration and overlapping ownership:

| Issue | Change | PR / pinned head | Base |
| --- | --- | --- | --- |
| #42 | Bounded catalog codec | [#62](https://github.com/Yuke-hd/esp-can-companion/pull/62), `c7906c90b48f2e9ae4ed85a2ab58350371f08cc9` | `main` |
| #44 | Optional endpoint routing | [#63](https://github.com/Yuke-hd/esp-can-companion/pull/63), `2e0611fc2a82f42b42b5147e62f832d9d75ed7ff` | #42 |
| #43 | Typed records and liveness | [#64](https://github.com/Yuke-hd/esp-can-companion/pull/64), `830d9af375f441d61bb628b24b23f2e3e78e3d76` | #44 |
| #46 | Connection-scoped catalog discovery | [#65](https://github.com/Yuke-hd/esp-can-companion/pull/65), `28f193775c21c9c3983157137683a40bb2a9356e` | #43 |
| #45 | Selected notifier lifecycle and bridge | [#66](https://github.com/Yuke-hd/esp-can-companion/pull/66), `3f213bffe8b4c1f4bef4a51122a74927ec6435c9` | #46 |
| #47 | Extensible negotiation | [#67](https://github.com/Yuke-hd/esp-can-companion/pull/67), `4764f20e0dc0a53a218a479fce3e1618c246b15e` | #45 |
| #50 prerequisite | Catalog-backed fake adapter | [#68](https://github.com/Yuke-hd/esp-can-companion/pull/68), `1fa44d6c4bfe544b306068bc0fa7eb2537d7005a` | #47 |
| #48 | Curated semantic projection | [#69](https://github.com/Yuke-hd/esp-can-companion/pull/69), `7ab47b0791eb5012e0b8dfc14d1914e32c364e36` | #50 adapter |
| #50 prerequisite | Partial/faulted fake journey support | [#70](https://github.com/Yuke-hd/esp-can-companion/pull/70), `f86f2e83ec1ca25aae302321767078b6757a03f8` | #48 |
| #49 | Generic discovered signal list | [#71](https://github.com/Yuke-hd/esp-can-companion/pull/71), `d8425521575edf286e501bcff864dcbb0aae97af` | #50 support |
| Test gate | Deterministic preset busy-refresh check | [#72](https://github.com/Yuke-hd/esp-can-companion/pull/72), `d8e2cce862a2b50f5a8832ade6bc3e9c91e555f5` | #49 |
| #50 final | Named discovery app journeys | [#73](https://github.com/Yuke-hd/esp-can-companion/pull/73), `ee049c10492fcc7cb796e89348e9c7c51fa5a6e2` | #72 test gate |

The two prerequisite slices of #50 remain separately reviewable; its final
journey PR follows the #72 test gate, and this report follows that PR. The full stack is
unmerged. Issue acceptance criteria and focused evidence remain in the linked
PRs rather than being replaced by the integration totals below.

## Software evidence available

The coordinator confirmed passing local host and iOS regressions for each
published slice. Focused coverage includes catalog bounds and golden vectors,
atomic record errors/liveness, connection-scoped rediscovery, selected notifier
leases, unavailable-without-fallback negotiation, curated parity, and partial or
faulted fake packets. Mutation checks failed as expected when guards or fixture
behavior were removed, then passed after restoration. Each linked PR retains
its focused validation details. All required CI on #62–#70 is green, and the
root reviewer approved those pinned heads on 2026-10-13. They remain unmerged.
PR #71's retry head has both required CI checks passing and root approval.
Its latest head is an empty CI retry commit; production source matches the
UI-verified `c66dea9f774dd6d82d542c311eb292795fa637b2` revision. The previous
UI check passed; Build and test failed in a pre-existing busy preset-sync test.
The retry passed both required checks. [PR #72](https://github.com/Yuke-hd/esp-can-companion/pull/72)
now pins `d8e2cce862a2b50f5a8832ade6bc3e9c91e555f5` on #71. Its one-file,
test-only correction makes the busy preset-refresh test deterministic. The
original reviewed head passed both CI checks, its host PresetSync suite passed
43 tests, and a mutation triggered two expected assertion failures. The
pre-existing race recurred in #73's Build and test job after the UI control
correction, so #72 is now an explicit prerequisite before #73. The same patch
was rebased without semantic changes. Both required CI checks pass at the
new #72 head, which has root reapproval. Its corrected fixture stays in the
base rather than the #73 journey diff.

Final #50 PR #73 pins `ee049c10492fcc7cb796e89348e9c7c51fa5a6e2`.
The first #73 CI run passed Build and test and 12/13 UI checks; the unavailable
journey tapped a moving dashboard control during a terminal-state transition.
CI artifact inspection showed the control moved between lookup and tap. The
final test-only correction waits for the expected terminal failure text before
opening the sheet, retaining the assertions and existing timeouts. Its focused
journey passed two local iterations covering all three unavailable recipes.
The matching log/result is `/private/tmp/gh73-unavailable-sync.{log,xcresult}`.
The subsequent #73 Build and test failure was the existing preset-sync race,
addressed by the #72 prerequisite above. Its three journey patches were rebased
unchanged, as verified by range-diff. The prior #73 head
`8d2c8b6e8aa850eaa930282ada0088bd87427442` passed both required CI checks and
had root approval. CI uses iPhone 16 Pro/iOS 26.2, while local evidence below uses iPhone
16 and SE/iOS 18.3. The owner explicitly permits documentation-only approval by complete diff
review without waiting for CI. Implementation changes retain their exact-head
CI and review gates.

The subsequent warning cleanup at source commit
`ff9c0319f21aaa6e2fa25f7d27b65aba1cdd434e` uses noncapturing `@Sendable`
demo closures and a `nonisolated` immutable restore identifier. Workflow commit
`4611dc08c1d8d6aa1043042ca759af41b2be612c` updates artifact upload to
`actions/upload-artifact@v6` with Node 24. The dedicated warning worker passed
366 local package tests, host and iOS Swift 5 warnings-as-errors checks, and
YAML validation. CI confirmed those source warnings were gone, then identified
an existing Simulator always-true fake branch/unreachable native-path warning
in `AppModel.launch`. Follow-up commit
`ee049c10492fcc7cb796e89348e9c7c51fa5a6e2` selects Simulator/native paths
at compile time with `#if targetEnvironment(simulator)`, preserving named
scenarios, device `FakeController` selection and native permission deferral.
The root-reviewed one-file correction passed all 79 app tests plus Simulator
and generic-device Swift warnings-as-errors builds. Latest #73 exact-head CI
is pending; prior green CI is not claimed for this revision.

The full regression baseline at #50 revision
`9746d5399488bbbece1752eb1d70d003f2314919` passed host package 366/366, iOS
package 366/366 and app 79/79. The iPhone 16 new-journey suite passed 7/7 and
its baseline-plus-journey UI suite passed 13/13. SE journeys including largest
accessibility text passed 7/7. A subsequent test-only scroll/capture correction
left production source unchanged; the three affected checks passed on both
phone sizes. The root reviewer reviewed the complete five-file journey diff
and inspected the final rendered evidence. These results support the software
exit criteria; they do not establish physical compatibility.

The commands below are recorded from retained logs. Run `swift test` and app
commands from the repository root, and the package `xcodebuild` command from
`Packages/CompanionKit`.
The destination IDs are iPhone SE third generation and iPhone 16 respectively:

```sh
swift test --disable-sandbox \
  --scratch-path /private/tmp/gh50-journey-host-build \
  --cache-path /private/tmp/gh50-swift-cache --package-path Packages/CompanionKit \
  > /private/tmp/gh50-journey-host-green.log 2>&1
xcodebuild test -scheme CompanionKit-Package \
  -destination 'platform=iOS Simulator,id=83DEA38F-D07D-4815-B944-1BA7CB18ED1C' \
  -derivedDataPath /private/tmp/gh50-journey-package-derived \
  -resultBundlePath /private/tmp/gh50-journey-package-green.xcresult CODE_SIGNING_ALLOWED=NO
xcodebuild test -project CANCompanion.xcodeproj -scheme CANCompanion \
  -destination 'platform=iOS Simulator,id=83DEA38F-D07D-4815-B944-1BA7CB18ED1C' \
  -derivedDataPath /private/tmp/gh50-journey-app-derived \
  -resultBundlePath /private/tmp/gh50-journey-app-full.xcresult CODE_SIGNING_ALLOWED=NO
xcodebuild test -project CANCompanion.xcodeproj -scheme 'CANCompanion UI Tests' \
  -destination 'platform=iOS Simulator,id=7BD0AD20-3A5C-4F5F-BC68-3389C1EC3132' \
  -derivedDataPath /private/tmp/gh50-journey-app-derived \
  -resultBundlePath /private/tmp/gh50-journey-ui16-final.xcresult CODE_SIGNING_ALLOWED=NO
```

The full UI command passed 13 checks at the regression baseline. Its matching log is
`/private/tmp/gh50-journey-ui16-final.log`. Passing regression logs are
`/private/tmp/gh50-journey-host-green.log`,
`/private/tmp/gh50-journey-package-green.log`, and
`/private/tmp/gh50-journey-app-full.log`. Use fresh result bundle paths when
reproducing a run; existing bundles cannot be overwritten by `xcodebuild`.

## Named actual-app journeys

The permanent scenarios are `discoveredSignals`, `discoveredPartial`,
`discoveredStalled`, `discoveredMalformed`, `discoveredReconnect`,
`discoveredUnsupported`, `discoveredUnusable`, and `discoveredCatalogFailure`.
Tests launch the actual app with `-FakeController YES -DemoScenario <name>`,
retain saved app data and start a new synthetic fake process for each recipe.
They operate the real dashboard and sheet controls, use outcome-based waits,
and inspect semantic row labels. No uninstall or personal Simulator erase was
used. Environment is Xcode 26.6 (`17F113`), iOS 18.3, portrait iPhone 16 and SE
third generation; largest text uses `UICTContentSizeCategoryAccessibilityXXXL`.

Root-inspected full viewport evidence is retained locally:

| Evidence | Observed result |
| --- | --- |
| `/private/tmp/gh50-journey-evidence-16/discovered-new-choice.png` | An unfamiliar key and additional enum choice appear without decoder or UI slot edits. |
| `/private/tmp/gh50-journey-evidence-16/partial-independent-expiration.png` | One reading clears after its deadline while peer traffic remains Fresh. |
| `/private/tmp/gh50-journey-evidence-16/remap-disconnected-cleared.png` | Old readings disappear during relinking; same-token rediscovery installs the new mapping. |
| `/private/tmp/gh50-final-evidence-se/large-text-scrolled-number.png` | The full wrapped `example.signed` key and signed value `-1.25` with unit are visible at largest text. |
| `/private/tmp/gh50-final-evidence-se/large-text-number-scroll-1.png`, `large-text-number-scroll-4.png` | Vertical scrolling reveals the oversized row's value, status, unit and evidence; Done remains reachable. |

The signed row spans more than one viewport at largest text and scrolls normally;
this is not a fixed-height cutoff. The new-choice, signed-number, partial-expiry,
stall, malformed-packet, unsupported/unusable capability, catalog-failure and
same-token reconnect journeys also pass accessibility assertions. Stall and
malformed traffic clear obsolete values, unavailable states expose no discovered
values, and closing/reopening the sheet preserves the working session.

## Rendered generic-list evidence

The retained #49 report is `/private/tmp/gh49-evidence-c66dea9/report.md`.
Environment: Xcode 26.6 (`17F113`), iOS Simulator 18.3, portrait iPhone 16 and
iPhone SE (third generation), normal content size plus the largest accessibility
text setting on SE. Production source was
unchanged during capture; a temporary app UI fixture drove the controls and
is removed before publication. Its retained copy is
`/private/tmp/gh49-SignalSheetSmokeTests.swift`.

Each check launched a new fake process with the connected or stalled synthetic
recipe while retaining saved app data. Real controls opened Discovered signals,
checked combined row labels and exact-byte key order, scrolled to changing RPM
while the sheet stayed open, reached the final wiper row, tapped Done, and
returned to the dashboard. A stalled launch showed Unknown/no-value state with
obsolete readings cleared. UI smoke checks passed 2/2 on each phone size and
2/2 on SE at accessibility-extra-extra-extra-large.

Fifteen full-screen screenshots under that report directory's `iphone16/`,
`se3/` and `se3-large/`
were inspected: metadata and enum choices wrap, values remain readable,
stalled values show dashes/status, the list scrolls and Done stays reachable.
The coordinator additionally inspected the SE top and iPhone 16 middle views.
These are full portrait viewport captures; earlier #48 cropped images do not
establish full viewport layout. Logs and result bundles are retained as
`/private/tmp/gh49-{iphone16,se3,se3-large}-ui.{log,xcresult}`; package/app logs are
`/private/tmp/gh49-final-{host,package,app}.log`.

At the largest text setting, long keys and metadata wrap over multiple lines;
the explanation and rows scroll without a fixed-height cutoff. RPM updates,
the final row and Done remain reachable, and stall clearing passes the
accessibility assertion. The curated dashboard's pre-existing compressed
freshness label at that extreme size remains outside the new sheet's scope.
Normal content size was restored after verification.
Accessibility hierarchy assertions cover the combined semantic key, type,
value/status, unit and catalog evidence labels plus stable reading order;
spoken VoiceOver behavior on a phone remains unverified. Loading, unavailable,
disconnected and empty states have app unit coverage; the rendered #49 captures
exercise connected and stalled states only. Permanent named failure/recovery scenarios are verified above. The
[UI verification](ui-verification.md) workflow remains the reproduction guide.

## Ordered merge and retarget procedure

No merge is authorized by this report. Once the owner requests merging:

1. Review the focused diff and exact head, required CI, independent review and
   conflict status for the lowest unmerged prerequisite.
2. Merge #62, then retarget #63 to `main`. Continue #63 through #71 in numeric
   order, then #72, #73 and this #41 report, retargeting the immediate next PR after its base
   lands. Keep independent ticket boundaries visible.
3. If squash merging changes ancestry, rebase the unpublished/dependent work
   onto the landed result so the next PR contains only its own changes. Do not
   merge branch histories or force-push shared work without authorization.
4. Recheck diff, conflicts and required CI after any retarget/rebase. Approval
   on an older head does not establish validation of the new head.
5. Revalidate integration if landed heads or the canonical contract change.
   Firmware merges and deployment remain separate owner decisions. Keep the
   deterministic #72 test gate before #73 so its regression suite has the
   corrected fixture.

## Unrun physical release gates

Simulator and fake-radio evidence cannot establish physical BLE, phone,
controller or vehicle compatibility. The following remain unrun here:

- Service Changed behavior, reconnect and restored CCCD selection on hardware.
- Accepted-bond access and protected catalog selector/read operations.
- Negotiated MTU, notification rate and sustained throughput.
- Firmware stack high-water and CAN/LED coexistence on the bench.
- Physical phone/controller interaction and explicitly scoped vehicle checks.

Track bench work in firmware [#167](https://github.com/Yuke-hd/mazda-can-accessory-controller/issues/167).
Keep these gaps and the unmerged firmware dependency visible before release.
Preserve receive-only CAN, fail-off lighting, provider availability and unset
brake freshness; software tests do not invent hardware freshness evidence.
