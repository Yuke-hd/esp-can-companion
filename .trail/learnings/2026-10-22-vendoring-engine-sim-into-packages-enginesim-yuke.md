---
title: Vendoring engine-sim into Packages/EngineSim (GH-89)
author: Yuke
date: 2026-10-22
branch: claude/issue-89-4d44c3
cost: { minutes: 14, tokens: 198045 }
touches:
  - Packages/EngineSim/NOTICE
  - Packages/EngineSim/Package.swift
  - "\"Packages/EngineSim/Sources/EngineSimCore/compat/backslash-includes/..\\\\include\\\\connecting_rod.h\""
  - "\"Packages/EngineSim/Sources/EngineSimCore/compat/backslash-includes/..\\\\include\\\\engine.h\""
  - Packages/EngineSim/Sources/EngineSimCore/compat/include/delta.h
  - Packages/EngineSim/Sources/EngineSimCore/engine_sim_core.cpp
  - Packages/EngineSim/Sources/EngineSimCore/include/EngineSimCore.h
  - Packages/EngineSim/Sources/EngineSimCore/ls_v8_builder.cpp
  - Packages/EngineSim/Sources/EngineSimCore/ls_v8_builder.h
  - Packages/EngineSim/Sources/EngineSimCore/ls_v8_impulse_response.cpp
---

## Decided
- Vendor upstream unmodified under Sources/EngineSimCore/upstream; shims in compat/ (delta.h stub, backslash-include shims for Windows-style includes). Only three header patches (units.h, constants.h `extern constexpr`->`inline constexpr`; gas_system.h `Mix()` ctor), recorded in upstream/LOCAL_PATCHES.diff and NOTICE.
- Piranha .mr is not vendored, so the LS V8 is hand-ported in ls_v8_builder.cpp mirroring the script nodes' generate order. IR wav is embedded as bytes (C++ targets cannot use SwiftPM resources).
- Build flags needed: -fdelayed-template-parsing, -DNDEBUG, __forceinline=inline. Leveler target 20000 (stock 30000 clips at 3000 rpm hold).
- Two library products so the `EngineSim-Package` scheme exists. Use simulator id, not name (iPhone 16 name is ambiguous across OS versions).

## Tried and ruled out
- Clang flags alone cannot fix the gas_system.h default-initializer error; a ctor patch is required.

## Watch out
- zsh printf interprets `\c` in backslash-named shim files; create them with python. `ls *` does not match names starting with a dot.
- Real-time factor is only ~0.95x at 10 kHz on a Mac (0.5x in simulator); phone feasibility is unproven, device benchmark not yet run.
