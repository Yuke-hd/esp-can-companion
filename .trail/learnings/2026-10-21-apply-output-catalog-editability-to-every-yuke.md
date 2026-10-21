---
title: Apply output catalog editability to every rules editor
author: Yuke
date: 2026-10-21
branch: codex/gh-82-83-output-catalog
touches:
  - App/Sources/Presets/EffectEditor.swift
  - App/Sources/Presets/OutputCatalogEditor.swift
  - App/Sources/Presets/SetupRulesView.swift
  - AppTests/OutputCatalogEditabilityTests.swift
---

## Decided
When an output catalog is active, use its editability decision in the legacy rule effect editor as well as in the catalog form. Known outputs omitted from the catalog and outputs with unsupported descriptor fields must have no mutation controls there. Preserve built-in fallback editing when no catalog is available.

## Tried and ruled out
Protecting only the dedicated catalog form leaves expanded rule cards able to mutate the same binding through the legacy editor.

## Watch out
Add coverage for both a known binding omitted from the catalog and one whose descriptor has an unsupported field kind. Keep a supported descriptor editable to guard the normal path.
