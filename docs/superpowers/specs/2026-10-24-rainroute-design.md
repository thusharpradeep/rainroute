# RainRoute Design

**Date:** 2026-10-24
**Status:** Decisions fixed by the product owner; implementation authorized in the same session.

## Intent

RainRoute is an iPhone app that answers a single question: **if I leave at this
time, how much of my ride is likely to be in rain?** The user types a start and a
destination. The app finds the fastest driving route, splits it into roughly
10 km segments, estimates when the rider reaches each segment, and reads the
hourly weather forecast for that segment at that ETA. The result is a wet-risk
percentage, a segment count, a route coloured by rain intensity, a departure
slider from now to +4 hours, and a best-time-to-leave suggestion.

Tirur to Kochi is used only as a unit-test fixture. Nothing in the app logic or
UI is specific to that route.

The product is a planning aid. It does not promise that a segment will be dry or
wet, and it must say so plainly: the forecast grid is about 9 km, and Kerala rain
is patchy.

## Goals

- Work for any start and destination the user types.
- Compute wet share from the weather forecast **at the ETA**, not current weather.
- Let the rider vary departure time from now to +4 hours without re-fetching weather.
- Expose a persisted pace factor so ETAs can match real riding speed.
- Show the route on a map, coloured by forecast rain intensity.
- Use only free, keyless, open services: Photon, OSRM, Open-Meteo.
- Ship an unsigned IPA from GitHub Actions for iloader sideloading.
- Keep core logic deterministic and unit-tested with fixed fake data; tests never
  call a live API.

## Non-goals / anti-goals

- No turn-by-turn navigation, live traffic, radar nowcasting, or en-route alerts.
- No claim of certainty. A green route is "low wet risk", not "guaranteed dry".
- No paid weather/routing keys, accounts, analytics, ads, or backend.
- No saved trips, history, social features, or cloud sync in v1.
- No current-location button, map-pin endpoint selection, or route alternatives in v1.
- No Android, iPad-specific layout, or landscape layout in v1.
- No attempt to resolve rain inside a 10 km segment beyond one forecast sample.

## Fixed decisions

### Wet-risk metric

- **Headline:** share of the route's distance whose segment is wet.
- A segment is wet when the forecast precipitation at its ETA is `>= threshold`.
- Default threshold: **0.2 mm/h**, configurable from 0.1 to 2.0 mm/h.
- The headline is rounded to the nearest **5%**.
- Under it: **"rain likely on X of N segments"**, where N is the number of samples.
- Rain probability is **not blended into the headline**.
- A separate line shows probability-weighted risk. The probability-weighted share is
  used only to break ties between departure times with the same wet-segment count.
- Copy uses "wet risk" / "likely", never "will rain" or a guarantee.

### Sampling and ETA

- The route is divided into `N = max(3, min(30, round(totalKm / 10)))` contiguous,
  equal-length segments. Each segment contributes one midpoint sample and one vote.
- Each segment's map slice runs boundary to boundary; its forecast is sampled at the
  midpoint.
- ETA at a point:
  `departure + paceFactor × cumulative OSRM duration at that point`.
- `paceFactor` defaults to **1.0**, range **0.8–1.5**, persisted in `UserDefaults`,
  labelled "ride slower/faster than the map estimate". No separate stop-time input.
- OSRM `annotations=duration,distance` supplies per-edge timing when the public
  server supports it. If annotations are missing or inconsistent, the fallback is a
  constant-speed profile scaled to OSRM's total distance and duration. The fallback
  is recorded in code and the app still works.
- The departure slider and the pace factor call the exact same evaluation function.

### Hourly forecast mapping

Open-Meteo precipitation is the sum over the **preceding hour**. Therefore the value
labelled `15:00` covers `14:00–15:00`.

- ETA `14:37` reads the `15:00` bucket.
- ETA exactly `15:00` reads the `15:00` bucket.
- ETA `15:01` reads the `16:00` bucket.
- No interpolation between hourly buckets in v1. The slider visibly steps when it
  crosses an hour; inventing a smooth rate would overstate the forecast's precision.
- All API times are requested in GMT (Unix timestamps where available) and converted
  to the device's local time only for display.

### Best departure

- Candidates every **15 minutes** from now through **+4 hours**.
- Compare the exact wet-segment count, not the rounded headline.
- Ties broken by lower probability-weighted share, then earlier departure.
- Recommend waiting only when it removes **at least one wet segment** versus leaving now.
- Otherwise say that leaving now is as good as it gets.
- The UI shows both the current and best values and offers "Use this time", which
  moves the slider to the recommended departure.

### Map colours

Intensity bands use the forecast precipitation rate, with anything below the user's
wet threshold drawn as dry:

| Band | Rate | Colour |
|---|---|---|
| Dry | below threshold | slate grey |
| Light | threshold to < 2.5 mm/h | cyan |
| Moderate | 2.5 to < 7.6 mm/h | blue |
| Heavy | >= 7.6 mm/h | purple |

## Approaches considered

### 1. Core as a local Swift package vs. app target only

A local Swift package would let a Mac run `swift test` without a simulator and
enforce that core logic imports no UI framework. It also adds public access levels,
package resolution, and XcodeGen package wiring. The app is small and CI already
runs an iOS test target.

**Chosen:** a separate `RainRoute/Core` folder compiled into the app target, with a
Foundation-only import policy and unit tests in `RainRouteTests`. This is the
simplest structure that still gives a hard logical boundary. The design doc records
the constraint rather than enforcing it with a package boundary.

### 2. Geocoding: Nominatim vs. Photon

Nominatim's usage policy requires one request per second and discourages
search-as-you-type. Photon is designed for autocomplete, needs no key, and returns
GeoJSON.

**Chosen:** Photon for typed search, with a custom User-Agent and a debounced,
cancelable request per field. No fallback geocoder in v1; a failure is shown to the
user. OSM attribution covers both.

### 3. Weather fetch shape: one request per segment vs. bulk grid cells

A route can have up to 30 sample points and many adjacent points snap to the same
0.1° cell. Fetching each point independently is wasteful and likely to hit rate
limits. Open-Meteo accepts multiple comma-separated coordinates in one request and
returns an array.

**Chosen:** unique grid cells, one multi-location request per chunk of up to 20
cells, cached per cell for 30 minutes. A 3-day hourly horizon covers now + 4 hours
of departure choice plus the ride. The departure slider then recomputes from the
cached forecast with no network traffic.

### 4. Map: MapKit vs. custom canvas

MapKit gives free Apple Maps tiles, gestures, camera fitting, and native polyline
content without an API key. Per-segment styling is possible with one `MapPolyline`
per segment.

**Chosen:** SwiftUI MapKit (iOS 17 APIs), standard map style, a base outline plus
coloured segment polylines, and start/destination annotations.

## Architecture

```text
RainRoute/
  RainRouteApp.swift            app entry point
  Core/                         Foundation-only, deterministic
    Geo.swift                   GeoCoordinate, GridCell, haversine distance
    Route.swift                 route geometry and cumulative timing profile
    RouteSlicer.swift           equal-distance segments, midpoint, width, ETA helpers
    HourlyForecast.swift        hourly series and preceding-hour bucket lookup
    WetnessEngine.swift         segment assessment, wet share, probability summary
    DeparturePlanner.swift      +4 h search and recommendation
    RainIntensity.swift         map colour classification
  Services/                     network and cache, no UI
    APIError.swift
    HTTP.swift
    PhotonGeocoder.swift
    OSRMRouter.swift
    OpenMeteoWeatherService.swift
    WeatherCache.swift
    WeatherRepository.swift
  ViewModels/
    AppModel.swift              screen state, debounced search, check/recompute
    AppSettings.swift           persisted pace factor and threshold
  UI/
    RootView.swift
    JourneySearchCard.swift
    RouteMapCard.swift
    WetnessSummaryCard.swift
    DepartureSliderCard.swift
    BestDepartureCard.swift
    SettingsSheet.swift
    AttributionFooter.swift
    Theme.swift
  Assets.xcassets/
RainRouteTests/                 unit tests, inline JSON fixtures, no live calls
project.yml                     XcodeGen manifest
.github/workflows/ios-build.yml macOS tests + unsigned IPA
docs/INSTALL.md                 iloader sideload walkthrough
```

### Core flow

1. `PhotonGeocoder.search` resolves typed text to `Place` values.
2. `OSRMRouter.route` returns a `Route` with coordinates, cumulative distance, and
   cumulative duration.
3. `RouteSlicer.gridCells` produces the unique snapped cells for the segment midpoints.
4. `WeatherRepository` returns `[GridCell: HourlyForecast]`, fetching only misses.
5. `WetnessEngine.evaluate` assesses each segment at its ETA and returns a
   `WetnessResult`.
6. `DeparturePlanner.plan` evaluates 17 departures and returns the recommendation.
7. The UI renders the selected result on the map and in the summary card; the slider
   and pace setting call steps 5–6 again with cached data.

### Weather cache

- Key: `GridCell` with latitude/longitude rounded to 0.1°.
- Value: parsed hourly forecast plus fetch timestamp.
- TTL: 30 minutes.
- Scope: in-memory for the app session. There is no disk cache in v1.
- Refresh: a toolbar refresh forces a new weather fetch for the current route.

### APIs

- **Photon:** `GET https://photon.komoot.io/api/?q=…&limit=6&lang=en`
- **OSRM:** `GET https://router.project-osrm.org/route/v1/driving/{lon},{lat};{lon},{lat}`
  with `overview=full&geometries=geojson&steps=true&annotations=duration,distance`
- **Open-Meteo:** `GET https://api.open-meteo.com/v1/forecast` with multi-coordinate
  latitude/longitude, `hourly=precipitation,precipitation_probability`,
  `forecast_days=3`, `timezone=GMT`, `timeformat=unixtime`

All requests carry
`User-Agent: RainRoute/1.0 (iOS; +https://github.com/thusharpradeep/rainroute)`.

### Error handling

- Empty or unresolved place: inline message under the search card.
- OSRM no-route / network / malformed response: inline error; no crash.
- Weather gap for a required ETA: error naming the missing forecast, not a silent dry.
- Missing probability field: headline still works; the confidence line says
  "Probability data unavailable".
- Cancelled autocomplete tasks do not surface errors.

## UI specification

- One scrollable screen, iPhone portrait, iOS 17+.
- Header: RainRoute title, a short "wet risk, not certainty" subtitle.
- Search card: start and destination fields, swap button, autocomplete results,
  custom "Check the route" button.
- Before a route: a calm empty-state card explaining the three-step model.
- After a route:
  - Map card with the route coloured by intensity, start/end markers, legend,
    distance and duration.
  - Wet-risk summary card: rounded percentage, X of N segments, probability-weighted
    line, departure/arrival, threshold used, and a caveat.
  - Departure slider card: now to +4 h in 15-minute steps, selected departure time.
  - Best-departure card: recommendation, saving in segments, "Use this time".
- Settings sheet: pace factor slider (0.8–1.5), wet threshold slider (0.1–2.0),
  data-source attributions, version.
- Footer: "Weather data by Open-Meteo.com", "© OpenStreetMap contributors",
  Photon and OSRM links.
- Light and dark mode follow the system. Minimum tap target 44 pt. Slider has an
  accessibility label and value.

## Testing strategy

- **Core tests:** route splitting (3/12/30 segment cases), ETA with pace, preceding-hour
  bucket edges, threshold equality, 5% rounding, X/N counts, probability summary,
  best-departure recommendation and ties, missing forecast errors.
- **Tirur→Kochi fixture:** fixed synthetic route coordinates and fixed fake hourly
  forecasts, including a dry window later in the ride. No live calls.
- **Decoder tests:** inline Photon, OSRM (with annotations), and Open-Meteo JSON.
- **Cache tests:** hit, miss, TTL expiry, and force refresh.
- All tests run on a macOS GitHub runner with an iOS Simulator destination.
- CI also builds the Release device target unsigned and packages the IPA.

## Distribution

- Fresh public GitHub repository `thusharpradeep/rainroute`; the Paisa repository is
  not modified.
- XcodeGen generates the project in CI; no `.xcodeproj` is committed.
- Workflow uploads `RainRoute-unsigned.ipa` as an artifact.
- A GitHub Release can carry the IPA for a durable download link.
- iloader signs the unsigned IPA with the user's Apple ID on Windows. Free-account
  installs expire after about 7 days and must be re-signed.

## Assumptions made while building (owner opted out of further questions)

1. Repository is **public**, so GitHub-hosted macOS Actions minutes are free.
2. Bundle identifier is `com.thusharpradeep.rainroute`; display name is **RainRoute**.
3. Deployment target is **iOS 17.0**, iPhone only, portrait only.
4. A single fastest OSRM route is used. Route alternatives are out of scope.
5. Photon is the only geocoder. Nominatim is not called, avoiding its one-request-per-
   second policy for search-as-you-type.
6. The app uses the device clock as "now"; a check captures that instant and the
   slider is relative to the captured instant. Refresh re-captures it.
7. Weather is fetched for three days, enough for now + 4 h plus any ride supported by
   the 30-segment cap; longer trips show a clear forecast-gap error rather than guesses.
8. Probability-weighted risk is the distance-weighted mean of
   `precipitation_probability` over all segments. It is displayed separately and used
   only as the departure tie-breaker.
9. Map intensity bands are physical rates, but values below the user threshold are
   drawn as dry so the map agrees with the headline.
10. No persisted trip, no location permission, no push notifications, no background
    refresh in v1.
11. The app is a planning aid, not a safety device. The UI repeats that limitation.
