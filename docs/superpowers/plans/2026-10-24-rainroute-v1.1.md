# RainRoute v1.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Google Maps link import, selectable segment count, named wet segments with an animated segment list, map hand-off buttons, a GPS live ride, and a branded splash to RainRoute v1.1.0.

**Architecture:** Keep all route parsing, projection, sampling, and wetness maths in Foundation-only Core files. Add two thin services: one resolves/imports Google Maps links, one wraps CoreLocation. AppModel orchestrates import and the live session; SwiftUI files render the new cards and controls. Every new core rule gets a deterministic unit test.

**Tech Stack:** Swift 5, SwiftUI, MapKit, CoreLocation, XCTest, XcodeGen, GitHub Actions (macOS 15, Xcode 16.4), Photon, OSRM demo, Open-Meteo.

**Spec:** `docs/superpowers/specs/2026-10-24-rainroute-v1.1-design.md`

## Global Constraints

- iOS 17.0+, iPhone portrait only.
- Segment count range **3...60**, default **12**, persisted in `UserDefaults`.
- Headline wet risk remains distance-weighted, rounded to the nearest 5%.
- A segment is wet when forecast precipitation is `>= threshold`; default threshold 0.2 mm/h.
- ETA = `departure + paceFactor × cumulative OSRM duration`; pace range 0.8...1.5.
- Weather cells snap to 0.1°; cache TTL 30 minutes; Open-Meteo requests batched.
- Google Maps import only; maximum 9 waypoints; driving only; keyless services only.
- No Apple Maps route import.
- Live ride uses actual GPS, When-In-Use permission only, no background location.
- Weather refresh during a ride every 10 minutes while foreground.
- No automatic rerouting; off-route threshold 500 m; manual update only.
- Builds and tests only through GitHub Actions; no local Xcode.
- Do not modify `C:\Users\Thushar\paisa`.
- UK English in user-facing copy.

## Review Focus

- **Google short-link redirects and consent/regional pages.** A normal copied link must either import or fail with a message that tells the rider how to paste the full URL. Test: parser accepts regional Google hosts and rejects short links with a resolution-needed error; importer uses a fake resolver.
- **Place names that Photon cannot find.** Import must not silently drop a stop or import a route missing a leg. Test: fake geocoder returns empty and importer reports the failed stop.
- **GPS near a parallel road or after a detour.** Projection must not jump to a distant road when a closer segment exists, and must report off-route distance. Test: perpendicular fix and a fix near the correct leg.
- **60-segment routes and weather batching.** Changing from 12 to 60 must not create duplicate cells or a request per segment, and must not crash the list. Test: custom count clamps and de-duplicates cells.
- **Reduce Motion and animation cost.** Wet-segment rain must become static with Reduce Motion and must not animate dry rows. Test is manual/visual plus an accessibility label check in the view.

---

### Task 1: Segment count core and settings

**Files:**
- Modify: `RainRoute/Core/RouteSlicer.swift`
- Modify: `RainRoute/Core/WetnessEngine.swift`
- Modify: `RainRoute/Core/DeparturePlanner.swift`
- Modify: `RainRoute/ViewModels/AppSettings.swift`
- Test: `RainRouteTests/RouteSlicerTests.swift`
- Test: `RainRouteTests/WetnessEngineTests.swift`
- Test: `RainRouteTests/AppSettingsTests.swift` (create)

**Interfaces:**
- Produces: `RouteSlicer.defaultSegmentCount: Int = 12`, `RouteSlicer.minimumSegments = 3`, `RouteSlicer.maximumSegments = 60`, `RouteSlicer.clampedSegmentCount(_ requested: Int) -> Int`, `RouteSlicer.segments(route:departure:paceFactor:segmentCount:)`, `RouteSlicer.gridCells(route:segmentCount:)`.
- Produces: `WetnessEngine.evaluate(route:departure:paceFactor:threshold:forecasts:segmentCount:)` with a default of `RouteSlicer.defaultSegmentCount`.
- Produces: `DeparturePlanner.plan(route:now:paceFactor:threshold:forecasts:segmentCount:window:step:)` with a default count.
- Produces: `AppSettings.segmentCount`, `AppSettings.setSegmentCount(_:)`, `AppSettings.segmentCountKey`, `AppSettings.segmentRange`, `AppSettings.defaultSegmentCount`.

- [ ] **Step 1: Write the failing segment-count and settings tests**

Add to `RouteSlicerTests`:
```swift
func testDefaultSegmentCountIsTwelve() {
    XCTAssertEqual(RouteSlicer.defaultSegmentCount, 12)
    XCTAssertEqual(RouteSlicer.clampedSegmentCount(1), 3)
    XCTAssertEqual(RouteSlicer.clampedSegmentCount(12), 12)
    XCTAssertEqual(RouteSlicer.clampedSegmentCount(60), 60)
    XCTAssertEqual(RouteSlicer.clampedSegmentCount(999), 60)
}

func testCustomSegmentCountProducesEqualLengthsAndEtas() throws {
    let route = TestSupport.simpleRoute(totalMeters: 60_000, durationSeconds: 3_600)
    let segments = try RouteSlicer.segments(
        route: route,
        departure: TestSupport.date(hour: 10),
        paceFactor: 1.0,
        segmentCount: 6
    )
    XCTAssertEqual(segments.count, 6)
    XCTAssertEqual(segments[0].lengthMeters, 10_000, accuracy: 0.001)
    XCTAssertEqual(segments[5].endDistanceMeters, 60_000, accuracy: 0.001)
}

func testGridCellsUseTheRequestedCount() throws {
    let route = TestSupport.simpleRoute(totalMeters: 60_000)
    XCTAssertEqual(try RouteSlicer.gridCells(route: route, segmentCount: 3).count, 3)
    XCTAssertEqual(try RouteSlicer.gridCells(route: route, segmentCount: 60).count, 60)
}
```

Add `AppSettingsTests`:
```swift
final class AppSettingsTests: XCTestCase {
    func testSegmentCountDefaultsToTwelveAndPersistsClamped() {
        let suite = UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suiteSuiteName) }
        let settings = AppSettings(defaults: suite)
        XCTAssertEqual(settings.segmentCount, 12)
        settings.setSegmentCount(60)
        XCTAssertEqual(settings.segmentCount, 60)
        settings.setSegmentCount(1)
        XCTAssertEqual(settings.segmentCount, 3)
        let reloaded = AppSettings(defaults: suite)
        XCTAssertEqual(reloaded.segmentCount, 3)
    }
}
```
Use a captured suite name constant rather than `suiteSuiteName` in the final code.

- [ ] **Step 2: Run tests to verify they fail**

Run via CI after the branch is pushed; locally there is no Xcode. Expected: compile failure because `segmentCount` parameters and `clampedSegmentCount` do not exist.

- [ ] **Step 3: Implement the segment count plumbing**

In `RouteSlicer`:
```swift
static let defaultSegmentCount = 12
static let minimumSegments = 3
static let maximumSegments = 60

static func clampedSegmentCount(_ requested: Int) -> Int {
    min(max(requested, minimumSegments), maximumSegments)
}
```
Add `segmentCount: Int = defaultSegmentCount` to `segments` and `gridCells`; use `clampedSegmentCount` instead of `segmentCount(for:)`. Delete the old automatic `segmentCount(for:)` and `preferredSegmentLengthMeters` if unused.

In `WetnessEngine`, add `segmentCount: Int = RouteSlicer.defaultSegmentCount` after `forecasts` and pass it to `RouteSlicer.segments`.

In `DeparturePlanner`, add `segmentCount: Int = RouteSlicer.defaultSegmentCount` after `forecasts` and pass it to every `WetnessEngine.evaluate` call.

In `AppSettings`:
```swift
static let segmentCountKey = "rainroute.segmentCount"
static let segmentRange = 3...60
static let defaultSegmentCount = 12
@Published private(set) var segmentCount: Int
```
Read/clamp from defaults in `init`, add `setSegmentCount(_:)` that clamps and writes only on change.

- [ ] **Step 4: Update existing tests for default 12**

The Tirur fixture now yields 12 segments, not 13. Update `WetnessEngineTests.testTirurKochiFixtureCountsWetSegmentsAtEta` expectations to derive the expected wet count from the first 12 segments rather than hardcoding 11, or set explicit `segmentCount: 13` in that test if the fixture intends 13. Prefer explicit `segmentCount: 13` to preserve the original fixture's intent. Update `RouteSlicerTests` to remove assertions on the deleted automatic count.

- [ ] **Step 5: Run the full test suite through CI and fix compile errors**

Push the branch and run `gh workflow run ios-build.yml --ref feat/v1.1.0`, then `gh run watch`. Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add RainRoute/Core RainRoute/ViewModels/AppSettings.swift RainRouteTests
git commit -m "feat: make segment count user-selectable"
```

---

### Task 2: Wet segment ranges and remaining-route wetness

**Files:**
- Create: `RainRoute/Core/SegmentRanges.swift`
- Create: `RainRoute/Core/LiveWetness.swift`
- Modify: `RainRoute/Core/WetnessEngine.swift`
- Test: `RainRouteTests/SegmentRangesTests.swift` (create)
- Test: `RainRouteTests/LiveWetnessTests.swift` (create)

**Interfaces:**
- Produces: `SegmentRanges.format(_ indices: [Int]) -> String`.
- Produces: `WetnessResult.wetSegmentIndices: [Int]` (1-based), `WetnessResult.wetSegmentSummary: String`.
- Produces: `WetnessResult.remaining(after distance: Double, at departure: Date, remainingDuration: TimeInterval) -> WetnessResult?`.

- [ ] **Step 1: Write the failing tests**

`SegmentRangesTests`:
```swift
func testCompressesConsecutiveRanges() {
    XCTAssertEqual(SegmentRanges.format([]), "")
    XCTAssertEqual(SegmentRanges.format([1]), "1")
    XCTAssertEqual(SegmentRanges.format([2, 5, 6, 7, 9]), "2, 5–7, 9")
    XCTAssertEqual(SegmentRanges.format([8, 9, 10, 11]), "8–11")
    XCTAssertEqual(SegmentRanges.format([4, 1, 3, 2, 2]), "1–4")
}
```

`LiveWetnessTests`:
```swift
func testRemainingResultDropsPassedSegmentsAndKeepsOriginalNumbers() throws {
    let route = TestSupport.simpleRoute(totalMeters: 120_000, durationSeconds: 7_200)
    let forecast = TestSupport.hourlyForecast(startHour: 10, values: [(0.5, 0.8), (0.0, 0.1), (0.0, 0.1)])
    let forecasts = try TestSupport.uniformForecasts(route: route, forecast: forecast)
    let all = try WetnessEngine.evaluate(
        route: route, departure: TestSupport.date(hour: 10),
        paceFactor: 1.0, threshold: 0.2, forecasts: forecasts, segmentCount: 12
    )
    let live = try XCTUnwrap(all.remaining(
        after: 55_000, at: TestSupport.date(hour: 10, minute: 30),
        remainingDuration: 3_900
    ))
    XCTAssertEqual(live.segments.first?.segment.index, 6)
    XCTAssertEqual(live.totalSegments, 7)
    XCTAssertEqual(live.departure, TestSupport.date(hour: 10, minute: 30))
    XCTAssertEqual(live.totalDistanceMeters, 65_000, accuracy: 0.001)
    XCTAssertEqual(live.totalDurationSeconds, 3_900, accuracy: 0.001)
}

func testRemainingResultWeightsPartiallyPassedSegmentByRemainingLength() throws {
    let route = TestSupport.simpleRoute(totalMeters: 120_000, durationSeconds: 7_200)
    let wet = TestSupport.hourlyForecast(startHour: 10, values: [(0.5, 1.0), (0.0, 0.0)])
    let forecasts = try TestSupport.uniformForecasts(route: route, forecast: wet)
    let all = try WetnessEngine.evaluate(
        route: route, departure: TestSupport.date(hour: 10),
        paceFactor: 1.0, threshold: 0.2, forecasts: forecasts, segmentCount: 12
    )
    let live = try XCTUnwrap(all.remaining(after: 5_000, at: TestSupport.date(hour: 10, minute: 10), remainingDuration: 6_600))
    XCTAssertEqual(live.totalDistanceMeters, 115_000, accuracy: 0.001)
}

func testRemainingResultIsNilAtTheDestination() throws {
    let route = TestSupport.simpleRoute(totalMeters: 30_000, durationSeconds: 3_600)
    let forecasts = try TestSupport.uniformForecasts(
        route: route,
        forecast: TestSupport.hourlyForecast(startHour: 10, values: [(0.0, 0.0)])
    )
    let all = try WetnessEngine.evaluate(
        route: route, departure: TestSupport.date(hour: 10),
        paceFactor: 1.0, threshold: 0.2, forecasts: forecasts, segmentCount: 12
    )
    XCTAssertNil(all.remaining(after: 30_000, at: TestSupport.date(hour: 11), remainingDuration: 0))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: missing `SegmentRanges`, `remaining`, `wetSegmentIndices`.

- [ ] **Step 3: Implement range formatting and wet segment summary**

`SegmentRanges.format` sorts unique positive indices, walks runs, and joins with `", "`; a run of two or more is `"\(first)–\(last)"`.

Add to `WetnessResult`:
```swift
var wetSegmentIndices: [Int] {
    segments.filter(\.isWet).map { $0.index + 1 }.sorted()
}

var wetSegmentSummary: String {
    let ranges = SegmentRanges.format(wetSegmentIndices)
    if wetSegmentCount == 0 { return "No segments are forecast wet." }
    if wetSegmentCount == totalSegments { return "All \(totalSegments) segments are forecast wet." }
    return "Wet segments: \(ranges) — \(wetSegmentCount) of \(totalSegments)."
}
```

- [ ] **Step 4: Implement `remaining(after:at:remainingDuration:)`**

For each assessment, compute:
```swift
let remainingLength = max(0, min(segment.endDistanceMeters, totalDistance)
    - max(segment.startDistanceMeters, distance))
```
Keep assessments with `remainingLength > 0.001`. Recompute `wetSegmentCount`, wet distance share, and probability-weighted share using `remainingLength` as the weight. Use the supplied `remainingDuration`; set `departure` to the supplied date. Return nil when no segment remains or `remainingDuration <= 0`.

- [ ] **Step 5: Run tests through CI**

Expected: new tests pass and existing wetness tests still pass.

- [ ] **Step 6: Commit**

```bash
git add RainRoute/Core RainRouteTests
git commit -m "feat: name wet segments and compute live remaining wetness"
```

---

### Task 3: Google Maps link parser and importer

**Files:**
- Create: `RainRoute/Core/GoogleMapsLink.swift`
- Create: `RainRoute/Services/GoogleMapsLinkResolver.swift`
- Create: `RainRoute/Services/GoogleMapsRouteImporter.swift`
- Modify: `RainRoute/Services/HTTP.swift`
- Test: `RainRouteTests/GoogleMapsLinkTests.swift` (create)
- Test: `RainRouteTests/GoogleMapsImporterTests.swift` (create)

**Interfaces:**
- Produces: `GoogleMapsStop { text: String; coordinate: GeoCoordinate? }`
- Produces: `GoogleMapsRouteLink { origin; waypoints; destination }`
- Produces: `GoogleMapsLinkParser.parse(_ url: URL) throws -> GoogleMapsRouteLink`
- Produces: `GoogleMapsLinkError` cases: `notGoogleMaps`, `needsResolution`, `unsupportedScheme`, `missingOrigin`, `noStops`, `tooManyWaypoints`, `unsupportedTravelMode`, `sameEndpoints`, `invalidLink`.
- Produces: `GoogleMapsLinkResolving.resolve(_ url: URL) async throws -> URL`.
- Produces: `PlaceSearching.search(_ query: String) async throws -> [Place]`; `PhotonGeocoder` conforms.
- Produces: `ImportedRoute { origin: Place; waypoints: [Place]; destination: Place }`.
- Produces: `GoogleMapsRouteImporter.importRoute(from rawLink: String) async throws -> ImportedRoute`.

- [ ] **Step 1: Write failing parser tests**

Cover:
```swift
func testParsesQueryDirectionsLink() throws {
    let url = URL(string: "https://www.google.com/maps/dir/?api=1&origin=Tirur%2C+Kerala&destination=Kochi%2C+Kerala&waypoints=Thrissur%2C+Kerala%7CAluva&travelmode=driving")!
    let link = try GoogleMapsLinkParser.parse(url)
    XCTAssertEqual(link.origin.text, "Tirur, Kerala")
    XCTAssertEqual(link.waypoints.map(\.text), ["Thrissur, Kerala", "Aluva"])
    XCTAssertEqual(link.destination.text, "Kochi, Kerala")
}

func testParsesPathDirectionsLinkAndIgnoresMapState() throws {
    let url = URL(string: "https://www.google.co.in/maps/dir/Tirur,+Kerala/Thrissur,+Kerala/Kochi,+Kerala/@10.5,76.2,9z/data=!4m2!4m1!3e0")!
    let link = try GoogleMapsLinkParser.parse(url)
    XCTAssertEqual(link.origin.text, "Tirur, Kerala")
    XCTAssertEqual(link.waypoints.map(\.text), ["Thrissur, Kerala"])
    XCTAssertEqual(link.destination.text, "Kochi, Kerala")
}

func testParsesCoordinateStops() throws {
    let url = URL(string: "https://www.google.com/maps/dir/10.9,75.9/10.5,76.2/9.9,76.3")!
    let link = try GoogleMapsLinkParser.parse(url)
    XCTAssertEqual(link.origin.coordinate, GeoCoordinate(latitude: 10.9, longitude: 75.9))
    XCTAssertEqual(link.destination.coordinate, GeoCoordinate(latitude: 9.9, longitude: 76.3))
}

func testRejectsWalkingAndShortLinksAndEmptyOrigins() {
    XCTAssertThrowsError(try GoogleMapsLinkParser.parse(URL(string: "https://www.google.com/maps/dir/A/B?travelmode=walking")!)) {
        XCTAssertEqual($0 as? GoogleMapsLinkError, .unsupportedTravelMode("walking"))
    }
    XCTAssertThrowsError(try GoogleMapsLinkParser.parse(URL(string: "https://maps.app.goo.gl/abc")!)) {
        XCTAssertEqual($0 as? GoogleMapsLinkError, .needsResolution)
    }
    XCTAssertThrowsError(try GoogleMapsLinkParser.parse(URL(string: "https://www.google.com/maps/dir//Kochi")!)) {
        XCTAssertEqual($0 as? GoogleMapsLinkError, .missingOrigin)
    }
}
```

- [ ] **Step 2: Write failing importer tests with fake protocols**

```swift
private struct FakeResolver: GoogleMapsLinkResolving {
    let resolved: URL
    func resolve(_ url: URL) async throws -> URL { resolved }
}
private struct FakeGeocoder: PlaceSearching {
    let results: [String: [Place]]
    func search(_ query: String) async throws -> [Place] { results[query] ?? [] }
}
```
Test success, unknown place error, coordinate stop bypassing the geocoder, duplicate consecutive anchors removed, and more than 9 waypoints rejected by the parser.

- [ ] **Step 3: Run tests to verify they fail**

Expected: missing types.

- [ ] **Step 4: Implement the parser**

Rules:
- Require `http`/`https`.
- Short hosts `maps.app.goo.gl` and `goo.gl` throw `.needsResolution`.
- Accept hosts equal to `google.com`, ending in `.google.com`, starting with `google.`, or containing `.google.`.
- Query form when `origin` and `destination` query items exist; `waypoints` split on `|`.
- Path form: after `/maps/dir/`, keep path components until a component starts with `@`, `data=`, `!`, `am=`, or `entry=`.
- Decode percent escapes, replace `+` with a space, trim.
- A stop is a coordinate when its first two comma-separated fields parse as a finite lat/lon in range.
- Missing first stop -> `.missingOrigin`; no destination -> `.noStops`.
- More than 9 waypoints -> `.tooManyWaypoints`.
- `travelmode` (or legacy `dirflg`) must be driving; `dirflg` values `w`, `b`, `r` reject.
- Origin and destination within 25 m -> `.sameEndpoints`.

- [ ] **Step 5: Implement resolver, importer, and HTTP HTML helper**

`HTTP.htmlRequest(url:)` sets `Accept: text/html,application/xhtml+xml`, `Accept-Language: en`, timeout 25, and the existing user agent.

`GoogleMapsLinkResolver.resolve`:
- If the host is not short, return the URL.
- GET with redirect following.
- Return `response.url` when it is no longer a short host and parses.
- Otherwise search the body for `<link rel="canonical" href="...">` or `og:url`, decode `&amp;`, and parse.
- If the final host is a consent host or no URL is found, throw `.resolutionFailed` with guidance to open in Safari and paste the full URL.

`GoogleMapsRouteImporter` resolves, parses, maps each stop to a `Place` (coordinate direct, name via Photon first result), deduplicates consecutive anchors within 25 m, and validates origin/destination not the same. Throw a typed error naming the failed stop.

- [ ] **Step 6: Run tests through CI**

Expected: parser and importer tests pass.

- [ ] **Step 7: Commit**

```bash
git add RainRoute/Core/GoogleMapsLink.swift RainRoute/Services/GoogleMapsLinkResolver.swift RainRoute/Services/GoogleMapsRouteImporter.swift RainRoute/Services/HTTP.swift RainRouteTests
git commit -m "feat: import Google Maps directions links"
```

---

### Task 4: OSRM multi-anchor routing and multi-leg annotations

**Files:**
- Modify: `RainRoute/Services/OSRMRouter.swift`
- Test: `RainRouteTests/RoutingDecodingTests.swift`

**Interfaces:**
- Produces: `OSRMRouter.route(through coordinates: [GeoCoordinate]) async throws -> Route`.
- Keeps: `OSRMRouter.route(from:to:)` as a two-coordinate wrapper.
- Produces: internal `OSRMRouter.routeURL(through:annotations:)` used by a test to assert anchor order.

- [ ] **Step 1: Write failing tests**

Add a JSON fixture with two legs:
```json
"geometry": {"coordinates": [[76.0,10.0],[76.01,10.0],[76.02,10.0]]},
"legs": [
  {"annotation":{"distance":[500],"duration":[60]}},
  {"annotation":{"distance":[500],"duration":[60]}}
]
```
Expect cumulative `[0, 500, 1000]` and durations `[0, 60, 120]`.

Add a test that builds a three-anchor URL:
```swift
let url = OSRMRouter.routeURL(
    baseURL: URL(string: "https://router.project-osrm.org")!,
    coordinates: [GeoCoordinate(latitude: 10, longitude: 76), GeoCoordinate(latitude: 10.1, longitude: 76.1), GeoCoordinate(latitude: 10.2, longitude: 76.2)],
    annotations: true
)
XCTAssertEqual(url.path, "/route/v1/driving/76.0,10.0;76.1,10.1;76.2,10.2")
```

Add a mismatch test where annotations sum to fewer edges than the geometry and expect the constant-speed fallback.

- [ ] **Step 2: Run tests to verify they fail**

Expected: missing `route(through:)`, `routeURL`, and multi-leg merge.

- [ ] **Step 3: Implement ordered anchors**

- Combine coordinates into `"lon,lat"` strings joined by `;`.
- Reject fewer than 2 anchors with `APIError.service("A route needs at least two points.")`.
- Keep the existing route request query and 400 fallback.
- Rename `fetchRoute(from:to:)` to accept `[GeoCoordinate]`.

- [ ] **Step 4: Merge annotations across legs**

- Collect every leg's `annotation.distance` and `.duration` in order.
- Require every leg to have both arrays.
- Require the combined count to equal `coordinates.count - 1`.
- Accumulate and normalise exactly as the current single-leg code does.
- Fall back to `Route.synthetic` when anything is missing or inconsistent.

- [ ] **Step 5: Run tests through CI**

Expected: single-leg, multi-leg, mismatch, and request-shape tests pass.

- [ ] **Step 6: Commit**

```bash
git add RainRoute/Services/OSRMRouter.swift RainRouteTests/RoutingDecodingTests.swift
git commit -m "feat: route through imported Google Maps anchors"
```

---

### Task 5: Route progress, link building, and parser edge cases

**Files:**
- Create: `RainRoute/Core/RouteProgress.swift`
- Create: `RainRoute/Core/RouteLinks.swift`
- Test: `RainRouteTests/RouteProgressTests.swift` (create)
- Test: `RainRouteTests/RouteLinksTests.swift` (create)

**Interfaces:**
- Produces: `RouteProgress { distanceMeters: Double; offRouteMeters: Double; fraction: Double }`.
- Produces: `RouteProgressTracker.project(_ point: GeoCoordinate, onto route: Route) -> RouteProgress`.
- Produces: `RouteProgressTracker.hasArrived(_ progress: RouteProgress, route: Route, tolerance: Double = 120) -> Bool`.
- Produces: `RouteLinks.googleMaps(start:destination:waypoints:) -> URL`.
- Produces: `RouteLinks.googleMapsApp(start:destination:waypoints:) -> URL?`.
- Produces: `RouteLinks.appleMaps(start:destination:) -> URL`.

- [ ] **Step 1: Write failing projection tests**

Use a straight route at latitude 10 from longitude 75.9 to 76.2, synthetic total 30,000 m:
```swift
func testProjectsStartMiddleAndEnd() {
    let route = TestSupport.simpleRoute(totalMeters: 30_000)
    XCTAssertEqual(RouteProgressTracker.project(route.coordinates[0], onto: route).distanceMeters, 0, accuracy: 1)
    let middle = GeoCoordinate(latitude: 10.0, longitude: 76.05)
    XCTAssertEqual(RouteProgressTracker.project(middle, onto: route).distanceMeters, 15_000, accuracy: 50)
    XCTAssertEqual(RouteProgressTracker.project(route.coordinates[1], onto: route).distanceMeters, 30_000, accuracy: 1)
}

func testReportsPerpendicularOffRouteDistance() {
    let route = TestSupport.simpleRoute(totalMeters: 30_000)
    let off = GeoCoordinate(latitude: 10.01, longitude: 76.05)
    let progress = RouteProgressTracker.project(off, onto: route)
    XCTAssertEqual(progress.offRouteMeters, 1_111, accuracy: 40)
    XCTAssertEqual(progress.distanceMeters, 15_000, accuracy: 60)
}

func testClampsBeforeStartAndAfterEnd() {
    let route = TestSupport.simpleRoute(totalMeters: 30_000)
    let before = GeoCoordinate(latitude: 10.0, longitude: 75.8)
    let after = GeoCoordinate(latitude: 10.0, longitude: 76.3)
    XCTAssertEqual(RouteProgressTracker.project(before, onto: route).distanceMeters, 0, accuracy: 1)
    XCTAssertEqual(RouteProgressTracker.project(after, onto: route).distanceMeters, 30_000, accuracy: 1)
}

func testArrivalUsesTolerance() {
    let route = TestSupport.simpleRoute(totalMeters: 30_000)
    let end = RouteProgress(distanceMeters: 29_950, offRouteMeters: 10, fraction: 0.998)
    XCTAssertTrue(RouteProgressTracker.hasArrived(end, route: route))
}
```

- [ ] **Step 2: Write failing link tests**

Assert host/path/query items for Google with two waypoints, Google app query decoding, and Apple start/destination with no waypoints. Assert decimal separators are dots.

- [ ] **Step 3: Run tests to verify they fail**

Expected: missing `RouteProgressTracker` and `RouteLinks`.

- [ ] **Step 4: Implement projection**

For each polyline edge, convert lat/lon to local metres using the edge midpoint latitude:
`x = Δlon × 111_320 × cos(midLat)` and `y = Δlat × 110_540`.
Project the point onto the edge, clamp `t` to `0...1`, and compute the distance to the projected point. Choose the edge with the smallest distance. Interpolate `distanceMeters` between `route.cumulativeDistances[i]` and `[i+1]` using `t`. `fraction = distanceMeters / totalDistanceMeters`. Return zero progress for a route with fewer than two coordinates.

- [ ] **Step 5: Implement link builders**

Use six-decimal coordinate strings with `Double` interpolation (never a locale-formatted number).
- Google web: `https://www.google.com/maps/dir/` with `api=1`, `origin`, `destination`, `waypoints` joined by `|`, `travelmode=driving`.
- Google app: `comgooglemaps://?saddr=...&daddr=...&waypoints=...&directionsmode=driving`; build the percent-encoded query with `URLComponents.percentEncodedQuery`.
- Apple: `https://maps.apple.com/` with `saddr`, `daddr`, `dirflg=d`.

- [ ] **Step 6: Run tests through CI**

Expected: projection and link tests pass.

- [ ] **Step 7: Commit**

```bash
git add RainRoute/Core/RouteProgress.swift RainRoute/Core/RouteLinks.swift RainRouteTests
git commit -m "feat: add GPS progress projection and map links"
```

---

### Task 6: AppModel import, anchors, segment reload, and live session

**Files:**
- Modify: `RainRoute/ViewModels/AppModel.swift`
- Create: `RainRoute/Services/RideLocationManager.swift`
- Test: none for the thin CoreLocation wrapper; all maths is covered in Tasks 2 and 5.

**Interfaces:**
- Consumes: `GoogleMapsRouteImporter`, `ImportedRoute`, `RouteProgressTracker`, `WetnessResult.remaining`, `AppSettings.segmentCount`.
- Produces published state:
  - `routeSource: RouteSource` (`.typed`, `.googleMaps`)
  - `importedStops: [Place]`
  - `isImporting: Bool`
  - `liveSnapshot: LiveRideSnapshot?`
  - `isRiding: Bool`
  - `isWaitingForGPS: Bool`
  - `isOffRoute: Bool`
  - `liveErrorMessage: String?`
- Produces methods:
  - `importGoogleMapsLink(_ raw: String, settings: AppSettings) async throws`
  - `clearImportedRoute(settings: AppSettings) async`
  - `segmentCountChanged(settings: AppSettings) async`
  - `startRide(settings: AppSettings)`
  - `endRide()`
  - `pauseRideUpdates()`
  - `resumeRideUpdates(settings: AppSettings) async`
  - `recalculateFromHere(settings: AppSettings) async`

- [ ] **Step 1: Refactor route loading without changing v1 behaviour**

Extract:
```swift
private func loadRoute(
    start: Place,
    destination: Place,
    waypoints: [Place],
    settings: AppSettings,
    forceRefresh: Bool
) async throws
```
It builds `[start.coordinate] + waypoints.map(\.coordinate) + [destination.coordinate]`, calls `router.route(through:)`, slices with `settings.segmentCount`, fetches forecasts, then sets route/forecasts/referenceNow/lastUpdated/departureOffset/mapRevision and recomputes. `check` resolves places and calls it, catching errors into `errorMessage`. `refresh` keeps re-checking when not riding.

- [ ] **Step 2: Add import orchestration**

- `importGoogleMapsLink` calls the importer, then `loadRoute` with imported anchors, then sets start/destination selections and queries, `importedStops`, and `routeSource = .googleMaps`.
- Do not replace the current route or fields if any step throws.
- Call `clearRouteOrigin()` in `updateQuery`, `select`, `clear`, and `swapEndpoints`.
- `clearImportedRoute` sets `.typed`, clears stops, and runs `check`.

- [ ] **Step 3: Add segment-count reload**

`segmentCountChanged` recomputes the current route's cells with the new count, fetches through `WeatherRepository` (cache-aware), stores forecasts, calls `recompute`, and updates the live snapshot if riding. Do not reroute or re-geocode.

- [ ] **Step 4: Add the CoreLocation wrapper**

`RideLocationManager` owns `CLLocationManager`, exposes `onLocation: ((GeoCoordinate, Double) -> Void)?` and `onAuthorization: ((CLAuthorizationStatus) -> Void)?`, calls `requestWhenInUseAuthorization()` when not determined, starts updates with `kCLLocationAccuracyBest`, `distanceFilter = 20`, `pausesLocationUpdatesAutomatically = false`, `allowsBackgroundLocationUpdates = false`, and stops on `stop()`.

- [ ] **Step 5: Add live ride session state and maths**

- `startRide` guards on route/result, checks location services, sets `isRiding`, starts the manager, starts a 10-minute refresh task, and creates an initial snapshot at the route start.
- On each accepted fix (accuracy <= 100 m, fresh timestamp):
  - Project onto the planned route.
  - Store progress and off-route distance.
  - Compute `progressDuration = RouteSlicer.duration(at: progress.distanceMeters, route: route)`.
  - Evaluate the full route with `departure = now - paceFactor × progressDuration`, using the current segment count and cached forecasts.
  - Build `live = result.remaining(after: progress.distanceMeters, at: now, remainingDuration: paceFactor × (route.totalDurationSeconds - progressDuration))`.
  - Publish `LiveRideSnapshot(location:progress:offRoute:result:updatedAt:)`.
  - Set `isWaitingForGPS = false`; set `isOffRoute = offRoute > 500`.
- On arrival, keep the last snapshot and publish an `hasArrived` flag.
- On permission denial or services off, do not start; set `errorMessage` with Settings guidance.
- `endRide` cancels the refresh task, stops updates, clears live state, and leaves the planned route/result intact.
- `pauseRideUpdates` stops location and cancels the timer without ending the session. `resumeRideUpdates` restarts them and refreshes if older than 10 minutes.
- `refresh` while riding calls the live weather refresh, not `check`.

- [ ] **Step 6: Add live weather refresh and manual relink**

- `refreshLiveWeather(force:settings:)` fetches all cells for the planned route through `WeatherRepository`, updates `forecasts`, `lastUpdated`, `recompute`, and rebuilds the live snapshot. Errors set `liveErrorMessage` but keep the last good result.
- The 10-minute loop calls this with `forceRefresh: true`.
- `recalculateFromHere` routes from the current GPS position to the destination, keeps imported anchors projected ahead of current progress, refreshes weather, updates the route state, and continues the session at progress zero. Set the start query to "Current location" and its selection to a Place at the GPS fix.

- [ ] **Step 7: Verify with CI**

Push and run the workflow. Expected: app target compiles; existing tests pass. Fix all concurrency/main-actor and CoreLocation errors from the log.

- [ ] **Step 8: Commit**

```bash
git add RainRoute/ViewModels/AppModel.swift RainRoute/Services/RideLocationManager.swift
git commit -m "feat: add imported anchors and GPS live ride state"
```

---

### Task 7: UI for import, map actions, segments, live ride, and splash

**Files:**
- Create: `RainRoute/UI/GoogleMapsImportSheet.swift`
- Create: `RainRoute/UI/RouteActionsCard.swift`
- Create: `RainRoute/UI/SegmentListCard.swift`
- Create: `RainRoute/UI/LiveRideCard.swift`
- Create: `RainRoute/UI/SplashView.swift`
- Modify: `RainRoute/UI/JourneySearchCard.swift`
- Modify: `RainRoute/UI/RouteMapCard.swift`
- Modify: `RainRoute/UI/WetnessSummaryCard.swift`
- Modify: `RainRoute/UI/SettingsSheet.swift`
- Modify: `RainRoute/UI/RootView.swift`
- Modify: `RainRoute/UI/Theme.swift`
- Test: manual/visual; no UI test target.

**Interfaces:**
- Consumes all published state and methods from Task 6.
- Produces no new core interfaces.

- [ ] **Step 1: Add import UI**

- Add a secondary "Import from Google Maps" button under "Check the route".
- Sheet contents: instructions, multi-line link field, "Paste from clipboard", primary import button with progress, inline error, honest geometry note.
- On success dismiss; on failure keep the sheet open and show the error.
- Show an imported-route badge with stop count and a "Use OSRM's default route" action after a successful import.

- [ ] **Step 2: Add map action buttons and start/end control**

- `RouteActionsCard` sits directly below the map.
- Google button uses `comgooglemaps://` when `canOpenURL` succeeds, otherwise the web URL. Apple button uses `maps.apple.com`.
- Full-width Start/End button. End shows a confirmation dialog.
- While riding, Google uses the live position and only waypoints ahead; Apple uses the live position and destination.

- [ ] **Step 3: Add wet segment naming and the segment list**

- Replace the bare count line in `WetnessSummaryCard` with `result.wetSegmentSummary`.
- Add planning/live copy variants: "of the ride likely wet" vs "of the remaining ride likely wet"; "Leave"/"Arrive" vs "Now"/"ETA".
- `SegmentListCard` rows show number, km range, ETA, precipitation, probability, and status.
- Wet rows use a custom falling-rain icon; dry rows use a static `cloud.sun.fill` or `cloud.fill`.
- Use `TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion))` for wet rows only; draw three small capsules falling under a cloud. Reduce Motion freezes the drops.
- Accessibility label contains segment number, km range, wet/dry, rate, probability, and ETA. Hide decorative glyphs.
- Use `LazyVStack` so a 60-row list stays light.

- [ ] **Step 4: Add live map and live card**

- RouteMapCard takes optional live snapshot and shows the GPS position with a white-ringed blue dot.
- While riding, draw the full route in grey, then the remaining live segments in intensity colours; hide the start marker.
- Add a recenter button when a live location exists.
- LiveRideCard shows a progress bar, distance done/to go, ETA, GPS accuracy, last weather refresh, and the off-route warning with "Update route from here".

- [ ] **Step 5: Add splash and root composition**

- Add `LaunchBackground` to `Theme` and the asset catalog.
- `SplashView` uses a navy background, drawn route line, rain cloud, wordmark, tagline, and Reduce Motion support.
- RootView overlays the splash for ~1.6 s on first appearance, fades it out, and never shows it again for that process.
- Compose content in this order: map, actions, live card (when riding), wetness, segments, departure controls (when not riding), best departure (when not riding).
- On `isRiding` changes, set `UIApplication.shared.isIdleTimerDisabled`.
- On scene phase changes, pause/resume ride updates and the idle timer.
- On `settings.segmentCount` changes, call `model.segmentCountChanged`.
- On `settings.paceFactor`/`wetThreshold` changes, recompute planned and live results.

- [ ] **Step 6: Add segment-count settings UI**

In SettingsSheet, add a section with a slider for 3...60 (step 1), the current value, "3" and "60" labels, a "Maximum (60)" shortcut, and a footer explaining that 12 is the default and that more segments refine distance/ETA detail but cannot beat the ~9 km forecast grid.

- [ ] **Step 7: Build through CI**

Push and run the workflow. Expected: app and tests compile; IPA builds. Fix any SwiftUI/MapKit/CoreLocation compile errors from the log.

- [ ] **Step 8: Commit**

```bash
git add RainRoute/UI RainRoute/Assets.xcassets
git commit -m "feat: add import, live ride, segment list, and splash UI"
```

---

### Task 8: Project configuration, docs, and CI hardening

**Files:**
- Modify: `project.yml`
- Modify: `.github/workflows/ios-build.yml`
- Modify: `README.md`
- Modify: `docs/INSTALL.md`
- Modify: `RainRoute/Services/HTTP.swift` user-agent version
- Modify: `RainRoute/Assets.xcassets/LaunchBackground.colorset/Contents.json` (created in Task 7)

- [ ] **Step 1: Update project.yml**

- `MARKETING_VERSION: "1.1.0"`, `CURRENT_PROJECT_VERSION: "2"`.
- `NSLocationWhenInUseUsageDescription`: "RainRoute uses your location only while you ride to show progress and keep the remaining-route rain forecast up to date."
- `LSApplicationQueriesSchemes: [comgooglemaps]`.
- `UILaunchScreen: { UIColorName: LaunchBackground }`.

- [ ] **Step 2: Harden CI simulator selection**

Replace the hardcoded destination with a shell step that:
- Lists available iPhone simulators as JSON.
- Chooses the first available iPhone.
- If none exist, creates one from the newest iOS runtime and the first available iPhone device type.
- Writes the chosen UDID to `$GITHUB_ENV`.
- Runs `xcodebuild test -destination "platform=iOS Simulator,id=$SIMULATOR_UDID"`.
- Keeps the test-result upload and unsigned IPA packaging unchanged.

- [ ] **Step 3: Update documentation**

- README features: Google Maps import, 12–60 segments, wet segment names, segment list, map buttons, live ride, splash, location permission.
- Replace the automatic segment formula with the user-selected range.
- Document the Google geometry limitation and the OSRM re-route.
- Document live refresh cadence, foreground-only limitation, and off-route behaviour.
- INSTALL: mention location permission on first Start ride and that denying it prevents live mode only.
- Update the test destination/version references.
- Update App Attestation/limitations copy from "no en-route" to the new live mode while keeping the safety disclaimer.

- [ ] **Step 4: Build and test through CI**

Expected: full test suite + unsigned device build + IPA artifact all pass.

- [ ] **Step 5: Commit**

```bash
git add project.yml .github/workflows/ios-build.yml README.md docs/INSTALL.md RainRoute/Services/HTTP.swift
git commit -m "chore: prepare v1.1.0 release"
```

---

### Task 9: Verification and release

**Files:**
- No code changes expected.

- [ ] **Step 1: Run a fresh CI build on the final branch**

`gh workflow run ios-build.yml --ref feat/v1.1.0`, then watch to success. Confirm the test count, device build, and IPA artifact.

- [ ] **Step 2: Independent compile and requirement audit**

Dispatch a fresh reviewer/agent to check:
- All new Swift files are in the target sources (XcodeGen picks up the folder).
- No missing imports or inaccessible private methods.
- Every requirement in the v1.1 design has a corresponding implementation.
- No live API calls in tests.
- Segment default is 12; max is 60; range clamping works.
- Google import is Google-only and Apple import is absent.
- Location usage string and query scheme are present.
- Splash appears once.
- README/INSTALL match behaviour.

- [ ] **Step 3: Merge to main and run release CI**

Fast-forward/merge the feature branch into `main`, push, and wait for the `main` push workflow to pass.

- [ ] **Step 4: Tag and publish v1.1.0**

- Create and push tag `v1.1.0`.
- Download the IPA artifact from the successful run.
- Compute SHA-256.
- Create the GitHub release `v1.1.0` with `RainRoute-unsigned.ipa`, release notes, and the checksum.
- Verify the release asset URL and size.

- [ ] **Step 5: Final report**

Report:
- Feature summary.
- Test count and CI run URL.
- Release URL and IPA checksum.
- Any residual limitations (Google geometry, Apple import absent, foreground-only live mode).
