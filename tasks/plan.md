# Auto-layout discovery implementation plan

GitHub milestone `auto-layout-discovery` and issues #41–#50 are the task source of truth. This plan records ordering and integration decisions; acceptance criteria and verification remain in each issue.

## Contract and scope

Use the reviewed firmware PR #255 contract at `251444d62600c7582943a409012b5f0c0ffef401` and its `extensible-live-v1` version 1 synthetic vectors. Firmware integration PR #265 is approved with passing CI but remains unmerged. App publication does not merge either repository or establish physical BLE compatibility.

The new app path requires extension version 1 / usable flag, both endpoints, and a complete valid catalog. Failures publish explicit telemetry-unavailable state with no legacy subscription/fallback. Existing layout 1/2 decoders remain available for historical compatibility and parity tests.

## Ordered issue index

1. Published stack: #42 [PR #62](https://github.com/Yuke-hd/esp-can-companion/pull/62) → #44 [PR #63](https://github.com/Yuke-hd/esp-can-companion/pull/63) → #43 [PR #64](https://github.com/Yuke-hd/esp-can-companion/pull/64) → #46 [PR #65](https://github.com/Yuke-hd/esp-can-companion/pull/65). This serializes integration and overlapping ownership even where issue dependencies allow independent work.
2. #45 [PR #66](https://github.com/Yuke-hd/esp-can-companion/pull/66) notifier lifecycle and bridge → #47 [PR #67](https://github.com/Yuke-hd/esp-can-companion/pull/67) negotiation.
3. #50 [PR #68](https://github.com/Yuke-hd/esp-can-companion/pull/68) catalog-backed fake adapter → #48 [PR #69](https://github.com/Yuke-hd/esp-can-companion/pull/69) curated projection → #50 [PR #70](https://github.com/Yuke-hd/esp-can-companion/pull/70) partial/faulted fake support. Both #50 prerequisite slices leave the issue open for named journeys.
4. #49 [PR #71](https://github.com/Yuke-hd/esp-can-companion/pull/71) generic discovered list → [PR #72](https://github.com/Yuke-hd/esp-can-companion/pull/72) deterministic preset-test gate → #50 [PR #73](https://github.com/Yuke-hd/esp-can-companion/pull/73) named actual-app fake journeys at `ee049c10492fcc7cb796e89348e9c7c51fa5a6e2`, pinned to the shared firmware integration fixture.
5. #41 integration/verification report follows final #50. Evidence is recorded in [auto-layout discovery verification](../docs/development/auto-layout-discovery.md). The report is based on final #50; physical gates remain separate.

## Verification checkpoints

- Codec: canonical catalog and stream bytes agree; malformed input is atomic; bounds, token invalidation, per-signal expiration, and brake demotion pass.
- Transport/client: one selected notifier; full catalog per connection; cancellation/generation safety; config regressions pass.
- Product: curated parity, automatic new-key/choice display, unavailable/failure/recovery journeys; actual Simulator screenshots, small phone and larger text.
- Publication: complete diffs reviewed, no conflicts, Code changes require passing CI before approval; documentation-only changes may be approved after diff review without waiting for CI under the owner instruction. Small focused PRs; no merge without owner request.

## Evidence status

Published PRs #62–#71 have passing required CI and root-reviewer approval at their pinned heads; none is merged. #49 PR #71 has an empty retry head `d8425521575edf286e501bcff864dcbb0aae97af`, with source unchanged from its verified `c66dea9` revision. Generic-list UI smoke passed 2/2 on iPhone 16, SE third generation, and SE at the largest accessibility text size; fifteen full portrait captures were inspected. The previously green/reviewed [PR #72](https://github.com/Yuke-hd/esp-can-companion/pull/72) patch now pins `d8e2cce862a2b50f5a8832ade6bc3e9c91e555f5` above #71 as a prerequisite after the existing busy preset-sync race recurred in #73 CI. It remains one test-only file; its rebased required CI is green and root reapproval complete.

The #50 regression baseline `9746d5399488bbbece1752eb1d70d003f2314919` passes host/iOS package 366/366, app 79/79, iPhone 16 new journeys 7/7, full baseline/UI 13/13 and SE journeys 7/7 including largest text. The final test-only scroll/capture correction passed all three affected checks on both phone sizes. Root reviewed the five-file journey diff and inspected full viewport new-choice, independent-expiration, reconnect clearing and largest-text signed-number captures. Software evidence meets the milestone's implementation verification criteria. PR #73 first CI passed Build and test plus 12/13 UI checks; a test-only terminal-layout wait correction passed two local unavailable-journey iterations with assertions preserved. After the preset race recurred, #73 was rebased onto #72 with its three journey patches unchanged by range-diff. Both required CI checks passed and root approval completed for #72 and prior #73 head `8d2c8b6e8aa850eaa930282ada0088bd87427442`. The latest reviewed #73 warning cleanup at `4611dc08c1d8d6aa1043042ca759af41b2be612c` passes local 366 package tests, host/iOS Swift 5 warnings-as-errors and YAML checks; CI confirmed the initial cleanup source warnings were gone, then identified an existing Simulator fake-branch/native-path warning. Final #73 head `ee049c10492fcc7cb796e89348e9c7c51fa5a6e2` fixes that compile-time path selection; 79 app tests plus Simulator and generic-device warnings-as-errors builds pass. Latest exact-head CI is pending. Documentation-only report approval follows complete diff review without waiting for CI under owner instruction; release still requires the physical gates below.

## Risks and deferred gates

Dependent PRs require ordered merges and retargeting as prerequisites land. Firmware PRs are unmerged. Physical phone/BLE/bench/vehicle tests, security/Service Changed/CCCD restoration on hardware, throughput, stack high-water and CAN/LED coexistence are separate release gates. Use synthetic data only.
