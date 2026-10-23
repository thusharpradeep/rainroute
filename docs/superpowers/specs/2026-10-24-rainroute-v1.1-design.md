# RainRoute v1.1 Design

**Date:** 2026-10-24
**Status:** Approved by the product owner. No further design questions; implementation authorised.
**Baseline:** v1.0.0, tag `v1.0.0`, commit `9ad5886`.

## Intent

v1.1 makes RainRoute usable for the ride itself. The rider can import the route
they already chose in Google Maps, choose how finely the route is sampled, see
every segment and its animated weather, open the same route in Google Maps or
Apple Maps, start a live ride using the phone's GPS, and watch the remaining-route
wet risk update without burning through free API quotas.

The existing premise stays unchanged: RainRoute is a planning aid. Wet means the
hourly forecast at the ETA is at or above the configured threshold. It is not a
promise of rain or dryness.

## Goals

- Import a Google Maps directions link by pasting it into RainRoute.
- Use the imported start, destination, and stops as routing anchors for OSRM.
- Let the rider choose the number of equal-distance segments: 3 to 60, default 12.
- Persist the chosen segment count, pace factor, and wet threshold.
- Name the wet segments in the wetness summary, not only report a count.
- List every segment with its distance range, ETA, precipitation, probability,
  and an animated icon; wet segments get a rain animation.
- Add "Open in Google Maps", "Open in Apple Maps", and "Start ride" below the map.
- While riding, use actual GPS position, show progress and remaining wet risk,
  and refresh weather at a conservative interval.
- Add a branded static launch screen plus a short animated in-app splash.
- Keep all APIs free and keyless. Tests never call a live API.

## Non-goals

- Apple Maps route-link import. Apple's public share flow does not expose enough
  consistent route information to justify a second parser in v1.1.
- Exact Google route geometry. Google does not put the chosen road geometry in a
  normal share link. RainRoute imports anchors and re-routes them with OSRM.
- Turn-by-turn navigation, voice guidance, background location, push alerts, or
  automatic rerouting.
- Paid Google Routes API, accounts, analytics, cloud storage, or a backend.
- GPX/KML import, saved trips, history, or Android/iPad layouts.

## Approaches Considered

### Route import

1. **Google Maps link paste, then OSRM through the imported anchors (chosen).**
   It is keyless, works with the existing router, and needs no new provider. The
   trade-off is that the road-level path can differ if Google chose a road OSRM
   would not; adding a via-stop in Google Maps pins the corridor.
2. **Google and Apple link paste.** Apple's URL format accepts a source,
   destination, and waypoint, but its share flow does not reliably preserve them.
   Supporting it would add a second parser and a worse result for little gain.
3. **GPX/KML file import.** It gives exact geometry, but it is not the copied-link
   flow the rider asked for and adds a file picker most riders will not use.
4. **Google Routes API with a user-supplied key.** It gives exact Google geometry
   and traffic ETAs, but requires billing, key storage, and a paid dependency.
   This conflicts with the keyless constraint.

### Live ride

1. **Actual GPS position (chosen).** The rider's real location determines progress
   and the remaining route. It is accurate when the rider stops, detours, or rides
   slower than the map estimate.
2. **Clock-and-pace simulation from the planned departure.** It needs no location
   permission, but it becomes wrong exactly when a live ride matters: traffic,
   stops, and detours.

### Segment count

1. **User-selected 3–60 segments (chosen).** The default is 12. A slider and a
   "Maximum" shortcut make the finer sampling explicit. More segments improve the
   distance and ETA granularity, but cannot beat the forecast grid's roughly 9 km
   resolution; the UI says so.
2. **Keep the v1 automatic roughly-10 km rule.** It is simpler, but it ignores the
   rider's request to control sampling and caps long routes at 30.
3. **Remove the cap and use one segment per forecast cell.** It sounds precise but
   the segment count would change with the weather grid, making the UI and tests
   unstable. A fixed 60 cap is predictable.

## Fixed Decisions

### Segment count

- Range: **3...60** inclusive.
- Default: **12**, persisted in `UserDefaults` under `rainroute.segmentCount`.
- Values outside the range are clamped when read and when set.
- Changing the count re-slices the current route, fetches any missing weather cells
  through the existing batched repository, and recomputes without re-routing.
- Segment count does not change the 0.1° weather-cell snapping or the 30-minute
  forecast cache.
- The wet percentage is still distance-weighted and rounded to the nearest 5%.
  The wet-segment count is not rounded.
- The route is divided into equal-distance segments using the supplied count. The
  segment midpoint is the forecast sample. Segment indices are 1-based in the UI.

### Google Maps import

- Accept a pasted Google Maps directions link, including `maps.app.goo.gl` short
  links, by resolving the redirect first.
- Accepted expanded forms:
  - `https://www.google.com/maps/dir/?api=1&origin=...&destination=...&waypoints=...`
  - `https://www.google.com/maps/dir/Origin/Waypoint/Destination/...`
  - The same paths on `maps.google.com` or regional `google.<tld>` hosts.
- Parse the first stop as origin, the last as destination, and the middle stops as
  waypoints. Ignore `@lat,lng,zoom`, `data=...`, `am=...`, and other Google view
  state.
- A stop is either a place/address string or a `lat,lng` coordinate. Place strings
  are geocoded with Photon; coordinates are used directly.
- Support at most **9 waypoints** (11 anchors), matching Google Maps' normal limit.
  More stops produce a clear error rather than an arbitrary truncation.
- Reject walking, cycling, and transit links. Only `driving` is supported.
- Reject a link whose origin is missing (for example a route that starts at "Your
  location") with instructions to set a start in Google Maps and share again.
- Reject a link whose origin and destination are within 25 m.
- Do not claim to use Google's road geometry. The import screen says RainRoute uses
  the link's start, destination, and stops, then routes between them with OSRM.
- Store the imported middle stops for the active route. Editing the start or
  destination, swapping them, clearing a field, or choosing a new place discards
  the imported anchors and returns to normal OSRM routing.
- Offer a visible "Use OSRM's default route" action on an imported route. It clears
  the anchors and re-runs the same start/destination through OSRM.
- If the link cannot be resolved or parsed, show the error in the import sheet and
  keep the existing route intact.
- Short-link resolution uses a normal HTTPS GET with redirect following. If Google
  returns a consent page or the final URL still cannot be parsed, the error tells
  the rider to open the link in Safari, copy the full `google.com/maps/...` URL,
  and paste that instead.

### OSRM with anchors

- Extend the router to accept an ordered list of 2–11 coordinates and join them
  with `;` in the route request.
- Keep `overview=full&geometries=geojson&steps=true&alternatives=false` and request
  `annotations=duration,distance`; retry once without annotations on HTTP 400.
- Merge annotation arrays across all returned legs. The public server returns one
  leg per pair of anchors. If the merged annotation count does not match the route
  geometry edge count, use the existing constant-speed fallback.
- Normalise the merged profile to OSRM's total distance and duration exactly as
  v1.0 does.
- A waypoint import is one OSRM request, not one per leg.

### Wet segments and segment list

- The wetness summary replaces the bare "rain likely on X of N" line with:
  - "Wet segments: 2, 5–7 — 3 of 12." for some wet segments.
  - "No segments are forecast wet." for none.
  - "All 12 segments are forecast wet." for all.
- Consecutive segment numbers are compressed into ranges. Formatting is a pure,
  tested core function.
- Add a "Segments" card immediately below the wetness summary. It lists every
  segment in order, including:
  - 1-based segment number.
  - Distance range in kilometres (one decimal).
  - ETA in the current locale's hour/minute format.
  - Precipitation rate in mm/h.
  - Probability as a percentage, or "probability unavailable".
  - A coloured status icon.
- Dry segments show a static weather icon. Wet segments show a continuous rain
  animation. Reduce Motion disables the falling movement and leaves a static rain
  icon. The animation is decorative and is hidden from accessibility; the row has
  a full text label.
- During a live ride, the list shows only segments still ahead, keeps their
  original numbers, and dims nothing that has already passed because passed
  segments are omitted.

### Map actions

- Place a row of "Open in Google Maps" and "Open in Apple Maps" buttons directly
  below the map. They open the current route's start and destination.
- Google Maps receives the imported middle stops as `waypoints`. Apple Maps has no
  reliable multi-stop URL, so it receives only start and destination.
- Prefer the installed Google Maps app via `comgooglemaps://`; fall back to the
  keyless Google Maps web directions URL. Apple Maps uses `maps.apple.com`.
- During a live ride, the links start at the current GPS position and include only
  imported waypoints that are still ahead. If there is no GPS fix, use the route
  start.
- Place a full-width "Start ride" button below the two map buttons. While a ride is
  active it becomes "End route" in the danger colour. Ending asks for confirmation.

### Live ride

- Use `CLLocationManager` with When-In-Use authorization only. Add
  `NSLocationWhenInUseUsageDescription`. No background location mode.
- Request permission when "Start ride" is tapped. If permission is denied or
  location services are off, do not start the session; show an actionable error.
- Once authorized, start updates with best accuracy and a 20 m distance filter.
  Keep the screen awake while the app is active and a ride is in progress.
- Show the rider's current position on the map and keep the route coloured by the
  remaining forecast. The planned route remains the reference geometry.
- Project the GPS fix onto the route polyline. Progress is the along-route distance
  of the nearest point; off-route distance is the distance from the fix to that
  point. The projection is a pure core function with tests.
- Recompute the live wetness result on each accepted GPS fix, without new network
  calls. Live ETAs use `now + paceFactor × (duration at segment midpoint − duration
  at current progress)`. The live result contains only segments with some distance
  still ahead.
- The live wet percentage is distance-weighted over the remaining part of the
  route. A partially passed segment contributes only its remaining length.
- Off-route warning appears when the nearest point is more than **500 m** away.
  Do not reroute automatically. Offer "Update route from here", which performs one
  OSRM request from the current position, keeps imported stops that are still
  ahead, refreshes the new route's weather, and continues the live session.
- Refresh weather for the route's cells every **10 minutes** while the app is in
  the foreground and a ride is active. Each refresh is one or more batched
  Open-Meteo requests; the existing chunk size of 20 and the 0.1° cell snapping
  remain. Do not geocode again during a ride.
- On background, pause location updates and the refresh timer but keep the session.
  On returning to the foreground, resume and refresh if the data is older than the
  interval. End the session when the rider ends it or the app is terminated.
- The planned departure slider and best-departure card are hidden during a ride.
  The wetness card is labelled as the remaining ride. The segment list shows
  remaining segments. The map toolbar refresh button refreshes live weather instead
  of re-routing.
- If the rider arrives at the destination, show an arrival message and keep the
  "End route" control. Do not end the session automatically.

### Splash

- Add a static iOS launch screen with the same deep-navy background as the app's
  branded splash; no logo asset is required on the static screen.
- Add a short in-app splash overlay on cold launch:
  - Deep-navy background.
  - A route line that draws in, a rain cloud, the RainRoute wordmark, and the line
    "Know the rain before the ride."
  - Roughly 1.6 seconds, then a 0.35-second fade.
  - Respect Reduce Motion by skipping the draw/fall animations and shortening the
    hold.
- The splash appears once per process launch, not on every foreground return.

### Versioning and release

- `MARKETING_VERSION` becomes **1.1.0**; `CURRENT_PROJECT_VERSION` becomes **2**.
- CI remains the only build environment: macOS 15, Xcode 16.4, XcodeGen.
- The test step selects an available iPhone simulator dynamically and creates one
  if the runner has none.
- Release v1.1.0 remains an unsigned IPA for iloader, with README and INSTALL
  updated for the new features and the location permission.

## Architecture

### New core files

- `Core/GoogleMapsLink.swift` — pure parser for resolved Google Maps directions
  URLs; stop and link value types; import errors.
- `Core/RouteProgress.swift` — nearest-point projection, along-route distance,
  off-route distance, and arrival detection.
- `Core/SegmentRanges.swift` — compresses 1-based segment indices into a display
  string.
- `Core/RouteLinks.swift` — builds Google/Apple Maps URLs and the Google Maps app
  URL from coordinates and waypoints.
- `Core/LiveWetness.swift` — `WetnessResult.remaining(after:at:remainingDuration:)`
  for partially completed routes.

### New service files

- `Services/GoogleMapsLinkResolver.swift` — resolves short links and extracts a
  parseable final URL, including canonical-link fallback.
- `Services/GoogleMapsRouteImporter.swift` — resolves, parses, geocodes place
  stops, validates, and returns `ImportedRoute`.
- `Services/RideLocationManager.swift` — thin CoreLocation wrapper with closures
  for location and authorization updates.

### Changed core files

- `RouteSlicer.swift` — explicit segment count parameter, range 3...60, default 12.
- `WetnessEngine.swift` — passes segment count through; adds remaining-route
  result construction and wet-segment index helpers.
- `DeparturePlanner.swift` — accepts segment count so planning and display use the
  same slices.
- `Route.swift` — no structural change expected; route progress is a separate
  type.

### Changed services

- `OSRMRouter.swift` — ordered-anchor route requests and multi-leg annotation
  merging.
- `HTTP.swift` — HTML request helper for short-link resolution (browser Accept
  header, no JSON constraint).

### Changed app state

- `AppSettings.swift` — persisted segment count with clamping.
- `AppModel.swift` — import orchestration, anchor-aware checks, segment-count
  reload, live session state, GPS handling, live weather loop, route relinking.
- `RootView.swift` — splash overlay, import sheet, new cards/buttons, scene-phase
  and idle-timer handling.

### New UI files

- `UI/GoogleMapsImportSheet.swift`
- `UI/RouteActionsCard.swift`
- `UI/SegmentListCard.swift`
- `UI/LiveRideCard.swift`
- `UI/SplashView.swift`

### Changed UI files

- `JourneySearchCard.swift` — "Import from Google Maps" action, imported-route
  badge, "Use OSRM's default route" action.
- `RouteMapCard.swift` — live current-position marker, remaining-route colouring,
  recenter control, imported/live labels.
- `WetnessSummaryCard.swift` — wet segment names and planning/live copy.
- `SettingsSheet.swift` — segment-count slider with a Maximum button and
  explanation.
- `RootView.swift` — composition and lifecycle.

## Data Flow

### Normal check

1. Resolve start and destination with Photon (or reuse selections).
2. Route through `[start] + importedWaypoints + [destination]` with OSRM.
3. Slice with `settings.segmentCount`; collect unique midpoint grid cells.
4. Fetch/cached batched Open-Meteo forecasts.
5. Evaluate planned wetness and departure plan.
6. Render the map, wetness summary, segment list, and departure controls.

### Google Maps import

1. Rider pastes a link in the sheet.
2. Resolver follows short-link redirects and returns a full URL.
3. Parser extracts origin, destination, and waypoints; rejects unsupported modes.
4. Importer geocodes place stops with Photon and keeps coordinate stops.
5. AppModel runs the normal route check through the anchors.
6. Only on full success does AppModel replace the search fields and mark the route
   as imported. On failure, the old route and fields remain.

### Live ride

1. Start ride after permission; show the current GPS fix.
2. Project the fix onto the planned route and compute progress.
3. Re-evaluate existing segment cells at live ETAs; filter to remaining distance.
4. Update map, remaining percentage, segment list, and live card without network.
5. Every 10 minutes, refresh all route cells in batches and rebuild the result.
6. If off route by more than 500 m, show the warning and the one-tap update action.
7. End route clears the live state and stops location updates.

## Error Handling

- Import errors are shown inside the import sheet and never destroy the current
  route.
- A short-link consent page produces a specific "open in Safari and paste the full
  URL" message.
- Unsupported travel modes, missing origin, too many stops, same endpoints, and
  unresolved place names each get a distinct message.
- OSRM or Open-Meteo failures during import leave the prior route untouched.
- Live weather refresh failures keep the last good result and show a small stale
  indicator; they do not end the ride.
- Location denial or unavailable services prevents the ride from starting and
  explains how to enable permission.
- Reduce Motion is honoured by the splash and rain animations.

## Testing

All tests are deterministic and offline.

- Google link parser: API query form, path form, regional hosts, encoded names,
  coordinate stops, `data`/`@` noise, empty origin, unsupported travel modes, too
  many waypoints, same endpoints, non-Google URLs, need-for-resolution.
- Importer: fake resolver and fake geocoder; place lookup failure; coordinate stops;
  duplicate anchors; successful imported route.
- OSRM decode: multi-leg annotations merged; mismatched annotation counts fall
  back; multi-anchor request shape (URL construction).
- Segment count: default 12, clamping at 3 and 60, custom counts produce equal
  lengths and correct midpoints, grid cells use the count.
- Wetness: existing tests updated for default 12; remaining-result maths with a
  partially passed segment; wet segment index/range formatting.
- Route progress: projection at start, middle, end; perpendicular off-route;
  nearest-segment selection; invalid/short route handling.
- Route links: Google web with waypoints, Google app URL encoding, Apple URL.
- Settings: segment-count persistence and clamping.
- Existing v1.0 tests continue to pass after count updates.

## Constraints

- iOS 17+, iPhone portrait, SwiftUI, MapKit, CoreLocation.
- Free keyless services only: Photon, OSRM demo, Open-Meteo.
- No new third-party dependencies.
- UK English in user-facing copy, consistent with v1.0.
- No modification to `C:\Users\Thushar\paisa`.
- Builds and tests run only through GitHub Actions; the local machine has no
  Xcode toolchain.
- Unsigned IPA for iloader must still be produced.

## Builder Notes

- Keep Core free of CoreLocation and SwiftUI so projection, parsing, and remaining
  wetness stay testable.
- Reuse the existing `HTTP`, `APIError`, `WeatherRepository`, and `Route` types.
- Do not introduce a second routing engine.
- Do not add network calls to unit tests.
- Keep user copy honest about Google not sharing exact road geometry and about the
  forecast grid limiting what extra segments can detect.
