# Stride — Plan

Running app for iPhone + Apple Watch, inspired by adidas Running. Swift 6, SwiftUI, iOS 18+ / watchOS 11+. UI in English.

Design system: https://claude.ai/artifact/AXgXamUybY5LSk9rdefbJa

## Phases

| # | Phase | Deliverable | Status |
|---|---|---|---|
| 0 | Foundation | Xcode project (iOS app + watchOS app + shared `StrideKit` package), design system in SwiftUI (colors, fonts, components), tab navigation | Done |
| 1 | Run tracking (iPhone) | Run setup, 3-2-1 countdown, GPS tracking, pause/auto-pause, hold-to-finish, save, post-run summary | Done |
| 2 | Apple Watch | Standalone Watch workout (HKWorkoutSession + live heart rate, zones), iPhone↔Watch mirroring, Watch run history sync | Done: standalone workout, zones, sync, live mirroring to iPhone, Start on Watch |
| 3 | History & detail | Monthly list, detail with pace-colored map, splits, pace/elevation/HR charts, edit, manual entry, share card | Done: list, detail, pace-colored map, splits, zones, pace/elevation/HR charts with shared scrubbing, edit, manual entry, share card |
| 4 | Coach | Voice feedback, distance/time goals, target pace alerts, intervals, training plans (5K, 10K, half) | Done: voice coach over music, split/goal announcements, target pace alerts, interval presets with live step card, 5K/10K/half plans with progress, restorable coach state |
| 5 | Progress | Weekly/monthly/yearly stats, personal records, streaks, challenges, shoe tracking | Not started |
| 6 | Native integrations | Apple Health, Live Activity / Dynamic Island, widgets, Siri shortcuts | Not started |
| 7 | Social & cloud | CloudKit sync, friends, leaderboards | Not started |

Each phase ends compiling and tested in the Simulator with a simulated route.

## Architecture

- `StrideKit` (Swift package, shared iOS + watchOS): models, formatting, split/record math, workout definitions, design tokens.
- iOS: SwiftData, CoreLocation (`CLLocationUpdate.liveUpdates(.fitness)`, `CLBackgroundActivitySession`), MapKit, Swift Charts, AVSpeechSynthesizer, HealthKit.
- watchOS: HKWorkoutSession + HKLiveWorkoutBuilder, WatchConnectivity / workout mirroring.
