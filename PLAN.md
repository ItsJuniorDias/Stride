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
| 5 | Progress | Weekly/monthly/yearly stats, personal records, streaks, challenges, shoe tracking | Done: week/month/year/all-time stats with charts and fair comparisons, yearly goal, weekly and daily streaks with heatmap, best efforts (1K to marathon) and records with summary, voice and run-detail badges, challenges (suggested and custom), shoe tracking with default shoe and wear alerts |
| 6 | Native integrations | Apple Health, Live Activity / Dynamic Island, widgets, Siri shortcuts | Done: iPhone and manual runs saved to Apple Health with route and pauses (weight and age read back), Live Activity on the Lock Screen, Dynamic Island and Watch Smart Stack with pause/resume, Home and Lock Screen widgets, Control Center control, Watch complications, Siri shortcuts (start, pause, resume, finish, this week, last run) |
| 7 | Social & cloud | CloudKit sync, friends, leaderboards | Done: runs, shoes and challenges synced with iCloud (private CloudKit), settings through iCloud key-value, friends by code over CloudKit's public database (opt-in sharing), weekly and monthly leaderboards with cheers on iPhone, a Friends widget and Apple Watch |
| 8 | Stride Pro | Subscription, paywall, Pro features, onboarding | Done: welcome pages on first launch (name, units, weekly goal, location, Apple Health, Apple Watch) followed by the paywall; Stride Pro yearly (US$ 39.99, 7-day free trial) and monthly (US$ 6.99) with StoreKit 2; Pro unlocks the 10K and Half plans, intervals, target-pace alerts, year and all-time stats and custom challenges; Profile shows the subscription with manage and restore; recording runs, history, Health, widgets, shoes, friends, week/month stats, First 5K and the Watch stay free |
| 9 | Pro training and sharing | Race predictions, training load, adaptive plans, custom workouts, intervals on Apple Watch, Instagram sharing | Done (to verify on device): race predictions from recent best efforts and training paces; training load vs your usual week with pace trend; plan sessions coached at your personal paces, with a gentle restart after a break; a custom interval workout builder (synced with iCloud) used on iPhone and sent to Apple Watch; interval workouts run on the Watch with a step card, haptics and spoken steps; share a run as an Instagram Story (card, route, your photo, transparent sticker), save it or send it anywhere |

Each phase ends compiling and tested in the Simulator with a simulated route.

## Architecture

- `StrideKit` (Swift package, shared iOS + watchOS): models, formatting, split/record math, workout definitions, design tokens.
- iOS: SwiftData, CoreLocation (`CLLocationUpdate.liveUpdates(.fitness)`, `CLBackgroundActivitySession`), MapKit, Swift Charts, AVSpeechSynthesizer, HealthKit.
- watchOS: HKWorkoutSession + HKLiveWorkoutBuilder, WatchConnectivity / workout mirroring.

## Before release

- **CloudKit schema:** run a Debug build once on an iPhone signed in to iCloud with the launch argument `-initCloudKitSchema` (Edit Scheme › Run › Arguments). It creates every record type and field in the Development environment. Then use **Deploy Schema Changes** in the [CloudKit Console](https://icloud.developer.apple.com) for `iCloud.alexandrejunior.Stride`. Repeat after any model change.
- **Capabilities:** in Xcode › Signing & Capabilities, check that the app has iCloud (CloudKit, container `iCloud.alexandrejunior.Stride`, key-value storage), Push Notifications, App Groups (`group.alexandrejunior.Stride`) and HealthKit; the Watch app and both widget extensions need the App Group.
- **Support email:** set `AppInfo.supportEmail` (Stride/Stride/App/AppInfo.swift). "Report Name" in Friends sends reports there (App Review 1.2).
- **Stride Pro (App Store Connect):**
  - Paid Apps Agreement, tax and banking active (without them the products don't load, even in sandbox). Enroll in the Small Business Program (15% commission).
  - Subscription group "Stride Pro" with `alexandrejunior.Stride.pro.annual` (1 year, US$ 39.99, introductory offer: 1 week free) and `alexandrejunior.Stride.pro.monthly` (1 month, US$ 6.99), both at the same level. Set the Brazil prices. Family Sharing on (can't be undone). Billing Grace Period on.
  - Display names, descriptions, a review screenshot of the paywall, and review notes. The first subscriptions go out with a new app version.
  - Set `AppInfo.privacyURL` (Stride/Stride/App/AppInfo.swift) and the same Privacy Policy URL in the listing; Terms of Use use Apple's standard EULA (`AppInfo.termsURL`).
  - Local testing: the shared Stride scheme runs with `Stride/Stride.storekit` (Xcode › Debug › StoreKit › Manage Transactions to renew, expire or refund). DEBUG launch argument `-StrideProOverride pro|free` forces either state.
- **Instagram sharing:** create a Meta app at developers.facebook.com and set its App ID in `AppInfo.facebookAppID`; Instagram's Stories composer expects it as `source_application`.
- **App Store Connect:** privacy policy URL; the privacy nutrition label must match `PrivacyInfo.xcprivacy` (name, user ID and fitness data, only when sharing with friends is on).
