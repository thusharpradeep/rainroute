# RainRoute Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build RainRoute, a SwiftUI iPhone app that estimates wet-route risk from ETA-matched hourly forecasts, and ship an unsigned IPA from GitHub Actions.

**Architecture:** Foundation-only core (geometry, route slicing, hourly bucket lookup, wetness, departure search) tested with fixed data; thin async services for Photon, OSRM, Open-Meteo with a 30-minute grid cache; one SwiftUI screen with typed autocomplete, MapKit route colouring, summary, departure slider, best-time card, and settings. XcodeGen generates the project on a macOS runner that runs unit tests and packages an unsigned device IPA.

**Tech Stack:** Swift 5 / iOS 17, SwiftUI, MapKit, Foundation URLSession, XcodeGen, GitHub Actions macOS 15.

**Spec:** `docs/superpowers/specs/2026-10-24-rainroute-design.md`

## Global Constraints

- Free/keyless services only: Photon, OSRM public server, Open-Meteo.
- No live API calls in tests.
- Route samples: `N = max(3, min(30, round(totalKm / 10)))`, equal-length segments, midpoint samples.
- Wet: precipitation at ETA `>= 0.2` mm/h default, configurable 0.1...2.0.
- Headline distance-share rounded to nearest 5%; show X of N; probability separate.
- ETA: `departure + pace × cumulative OSRM duration`; pace 0.8...1.5, default 1.0.
- Open-Meteo hourly value is the preceding hour; map ETA to next hour label.
- Best departure: 15-minute steps, now through +4 h; wait only if one segment saved.
- iOS 17.0, iPhone, portrait, bundle `com.thusharpradeep.rainroute`.
- Do not modify `C:\Users\Thushar\paisa` or its GitHub repository.
- Never claim success without fresh CI evidence.

## Review Focus

- An ETA exactly on an hour boundary must use that hour's preceding-hour bucket, not the next one.
- A missing forecast for a required ETA must be an error, never a silent dry segment.
- A route shorter than 30 km still gets at least 3 samples; a 300+ km route caps at 30.
- Pace changes must move ETAs and therefore change bucket selection, not only displayed clock times.
- The app must work for arbitrary typed endpoints; Tirur→Kochi appears only in tests.

---

### Task 1: Repository, design record, XcodeGen, CI skeleton

**Files:**
- Create: `project.yml`, `.gitignore`, `README.md`, `LICENSE`, `docs/INSTALL.md`, `.github/workflows/ios-build.yml`
- Create: `RainRoute/RainRouteApp.swift`, `RainRoute/Assets.xcassets/**`

**Interfaces:**
- Produces: scheme `RainRoute`, test target `RainRouteTests`, IPA artifact `rainroute-ipa`.

- [x] Write design and this plan.
- [x] Add XcodeGen manifest, assets, CI test + unsigned device build + IPA packaging.
- [ ] Verify first CI build reaches compilation.

### Task 2: Core geometry, route, forecast, slicer

**Files:**
- Create: `RainRoute/Core/Geo.swift`, `RainRoute/Core/Route.swift`, `RainRoute/Core/RouteSlicer.swift`, `RainRoute/Core/HourlyForecast.swift`
- Test: `RainRouteTests/RouteSlicerTests.swift`, `RainRouteTests/HourlyForecastTests.swift`

**Interfaces:**
- Produces: `GeoCoordinate`, `GridCell`, `Route`, `RouteSegment`, `RouteSlicer.segments(route:departure:paceFactor:)`, `RouteSlicer.gridCells(route:)`, `HourlyForecast.hour(containing:)`.

- [ ] Write tests for 3/12/30 segment counts, midpoint ETA, pace, slice endpoints, bucket edges.
- [ ] Implement until CI tests pass.

### Task 3: Wetness engine and departure planner

**Files:**
- Create: `RainRoute/Core/WetnessEngine.swift`, `RainRoute/Core/DeparturePlanner.swift`, `RainRoute/Core/RainIntensity.swift`
- Test: `RainRouteTests/WetnessEngineTests.swift`, `RainRouteTests/DeparturePlannerTests.swift`

**Interfaces:**
- Produces: `WetnessEngine.evaluate(route:departure:paceFactor:threshold:forecasts:) -> WetnessResult`; `DeparturePlanner.plan(route:now:paceFactor:threshold:forecasts:) -> DeparturePlan`; `WetnessResult.roundedWetPercent`.

- [ ] Write fixed Tirur→Kochi fixture and tests for wet count, threshold equality, rounding, probability line, best window, tie-break, no-improvement.
- [ ] Implement until CI tests pass.

### Task 4: Services and cache

**Files:**
- Create: `RainRoute/Services/APIError.swift`, `HTTP.swift`, `PhotonGeocoder.swift`, `OSRMRouter.swift`, `OpenMeteoWeatherService.swift`, `WeatherCache.swift`, `WeatherRepository.swift`
- Test: `RainRouteTests/GeocodingDecodingTests.swift`, `RoutingDecodingTests.swift`, `WeatherDecodingTests.swift`, `WeatherCacheTests.swift`

**Interfaces:**
- Produces: `PhotonGeocoder.search(_:) async throws -> [Place]`; `OSRMRouter.route(from:to:) async throws -> Route`; `OpenMeteoWeatherService.forecasts(for:now:) async throws -> [GridCell: HourlyForecast]`; `WeatherRepository.forecasts(for:now:forceRefresh:)`.

- [ ] Write inline JSON decoding fixtures and cache TTL tests.
- [ ] Implement annotation-first route profile with constant-speed fallback.
- [ ] Implement 0.1° cache, 30-minute TTL, chunked multi-location weather fetch.
- [ ] Verify CI tests pass.

### Task 5: View model and full SwiftUI UI

**Files:**
- Create: `RainRoute/ViewModels/AppSettings.swift`, `RainRoute/ViewModels/AppModel.swift`, `RainRoute/UI/*.swift`
- Modify: `RainRoute/RainRouteApp.swift`

**Interfaces:**
- Consumes: core and services above.
- Produces: typed search with debounce, check/refresh, slider/pace/threshold recompute from cache, map, summary, best-time, settings, attributions.

- [ ] Build screen states: idle, loading, error, result.
- [ ] Build autocomplete, swap, check, slider, best-time action, settings sheet.
- [ ] Build MapKit segment colours and camera fit.
- [ ] Verify CI simulator build and tests pass.

### Task 6: IPA verification and release

- [ ] Run macOS workflow on `main`.
- [ ] Confirm unit tests pass, Release device build passes, IPA artifact exists.
- [ ] Download IPA locally, create GitHub Release with IPA attached.
- [ ] Record install link and verification evidence in README / final report.
