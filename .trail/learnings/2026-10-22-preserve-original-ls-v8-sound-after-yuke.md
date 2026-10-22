---
title: Preserve original LS V8 sound after listening comparison
author: Yuke
date: 2026-10-22
branch: codex/gh-90-engine-sim-bridge
touches:
  - ".github/workflows/ci.yml"
  - Packages/EngineSim
---

## Decided
The owner listened to matched original and RPM-filtered LS V8 demos and chose the original: the filtered version did not sound like an engine. Preserve native simulator sound. The #90 dominant-firing requirement is revised to verifying the expected fourth crank order is present within 3%, with actual crank RPM within 2%, rather than making that order globally loudest.

## Tried and ruled out
Two cascaded narrow band-pass filters centered on rpm/15 made 100/200/333.3 Hz strongest at 1500/3000/5000 RPM, but the owner rejected that voicing. Do not reintroduce a tracked output filter or synthetic tone to satisfy a dominant-note test. A local firing-order regression must honestly describe its band and must not claim global spectral dominance.

## Watch out
The earlier bridge ownership/spectrum learning describes an unresolved decision; this listening decision resolves it. Raw strongest lower-band peaks near 62.5/200/125 Hz are expected physical output. The firing test separates the fourth crank order from adjacent half-orders; full suite must pass without skipped or expected-failure pitch assertions.
