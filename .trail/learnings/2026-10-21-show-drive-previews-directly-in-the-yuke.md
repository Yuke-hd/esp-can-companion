---
title: Show Drive previews directly in the README
author: Yuke
date: 2026-10-21
branch: main
touches:
  - README.md
  - docs/README.md
  - docs/development/ui-verification.md
  - docs/development/getting-started.md
  - docs/images/drive-cluster.png
  - docs/images/drive-motorsport.png
---

## Decided
The README Preview / demo section embeds real Simulator screenshots of the Motorsport and Cluster Drive styles. The user requested a visual preview directly in the main README because the prior demo link led to a technical document. Keep the caption plain and identify the values as sample data.

## Tried and ruled out
An installation walkthrough alone did not meet this visual-preview request.

## Watch out
Captured the current app on iPhone 17 Pro, iOS 26.5, using -FakeController YES -DemoScenario driveLaps. Navigate to Drive after controller loading finishes and verify numeric readouts before capturing. Switch styles with the Drive style button. Raw simctl PNGs required a 90-degree rotation to display in landscape. Assets are docs/images/drive-motorsport.png and drive-cluster.png, each 2622 by 1206. Build succeeded and both images were visually inspected. No real vehicle data was used.
