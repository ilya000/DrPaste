//
//  ActionPaletteSheet.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  REMOVED in 0.17.0.
//
//  Originally the "Browse" button in Settings → Actions opened this sheet,
//  showing every available action grouped by category. It was useful when
//  disabled actions were hidden from the main list, but became redundant
//  in 0.12.0 once the unified Settings → Actions list started showing
//  disabled rows greyed-out alongside enabled ones (two-surface principle:
//  Settings manages everything, HUD runs what's enabled-and-applicable).
//
//  Enabling a previously-disabled action is now a single click on its
//  checkbox in the main list — the Browse sheet just added a layer of
//  navigation for the same outcome. Removed per UX cleanup.
//
//  File left in place as a tombstone so anyone searching the codebase
//  for "ActionPaletteSheet" lands on this note instead of a "no results"
//  void. Once Xcode / SwiftPM source enumeration moves to be path-only
//  this file can be deleted from disk; until then keeping it empty is
//  the simplest portable removal.
//
