---
title: "Fix CI: EngineSim submodule in app jobs, Release for EngineSim tests"
author: Yuke-hd
date: 2026-10-22
branch: claude/fix-failed-ci-main-45d420
cost: { minutes: 4, tokens: 48296 }
touches:
  - ".github/actions/fetch-enginesim/action.yml"
  - ".github/workflows/ci.yml"
  - Packages/EngineSim/Package.swift
---

## Decided
Every CI job that builds the app or the EngineSim package needs the EngineSim submodule and its nested simple-2d-constraint-solver submodule. Use the composite action .github/actions/fetch-enginesim. The EngineSim package tests run with -configuration Release.

## Tried and ruled out
Raising the render deadline in engine_sim_core.cpp: the Debug C++ build was simply too slow on the runner (about 46s vs about 2s in Release), so the deadline expired and render returned fewer frames (47734 vs 66150).

## Watch out
actions/checkout does not fetch submodules, so a new job fails with "Packages/EngineSim/Package.swift doesn't exist". Plain xcodebuild test defaults to Debug, which makes engine-sim rendering far too slow.
