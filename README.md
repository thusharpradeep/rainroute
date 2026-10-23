# RainRoute

RainRoute answers one question: **if I leave at this time, how much of my ride is likely to be wet?**

Type any start and destination. RainRoute finds the fastest driving route, splits it into roughly 10 km segments, estimates when you will reach each segment, and reads the hourly forecast for that place and time. You get a distance-weighted wet-risk percentage, a segment count, a route map coloured by forecast rain, a departure slider from now to +4 hours, and a best-time-to-leave suggestion.

RainRoute is a planning aid, not a safety device. Forecasts are hourly and roughly 9 km wide; local rain can be patchier than the map shows. A dry result is low risk, not a guarantee.

## Features

- Works for any typed start and destination, with autocomplete from Photon.
- Fastest driving route from OSRM, with per-edge timing where the public server supports annotations.
- ETA-matched hourly forecasts from Open-Meteo. The value labelled 15:00 covers 14:00–15:00, so an ETA of 14:37 uses the 15:00 bucket and 15:01 uses 16:00.
- Headline is the share of route distance whose segment is wet at the forecast ETA, rounded to the nearest 5%.
- A separate probability-weighted confidence line; probability is never blended into the headline.
- Route split into `max(3, min(30, round(total km / 10)))` equal-distance segments, sampled at each midpoint.
- Departure slider from now to +4 hours in 15-minute steps. Moving it recomputes from forecasts already fetched for the route.
- Best-departure search recommends waiting only if it removes at least one wet segment.
- Pace factor from 0.8× to 1.5×, persisted between launches, shared by the slider and the best-time search.
- Adjustable wet threshold from 0.1 to 2.0 mm/h (default 0.2).
- MapKit route coloured by forecast intensity, with start and destination markers.
- Light and dark mode, iPhone portrait, iOS 17+.
- No accounts, ads, analytics, paid keys, or app backend.

## Get the app

The GitHub Actions workflow builds an **unsigned** IPA for sideloading:

1. Open the [latest release](https://github.com/thusharpradeep/rainroute/releases/latest) and download `RainRoute-unsigned.ipa`.
   If there is no release yet, download the `rainroute-ipa` artifact from the latest successful [workflow run](https://github.com/thusharpradeep/rainroute/actions/workflows/ios-build.yml) and unzip it.
2. Follow [docs/INSTALL.md](docs/INSTALL.md) to install it with [iloader](https://iloader.app).

Free Apple ID signing normally expires after about 7 days. Re-sign with iloader, or use SideStore to refresh automatically.

You can also download the artifact from the command line:

```sh
gh run download --repo thusharpradeep/rainroute -n rainroute-ipa
```

## Build from source

Requirements: macOS with Xcode 16 or newer, XcodeGen, and an iOS 17+ simulator or device.

```sh
brew install xcodegen
xcodegen generate
open RainRoute.xcodeproj
```

Select the `RainRoute` scheme. For a device build, set your own development team in Xcode because the repository ships with no signing identity.

Run the unit tests:

```sh
xcodebuild test \
  -project RainRoute.xcodeproj \
  -scheme RainRoute \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro Max,OS=latest" \
  -only-testing:RainRouteTests \
  CODE_SIGNING_ALLOWED=NO
```

The tests use fixed inline fixtures and never call a live API. Tirur → Kochi appears only as a synthetic fixture inside the test target; no app logic or UI is tied to it.

The CI workflow on `main` runs the tests, builds the Release device target unsigned, packages `Payload/` into `RainRoute-unsigned.ipa`, and uploads it as the `rainroute-ipa` artifact.

## How the calculation works

1. **Geocode** both endpoints with Photon.
2. **Route** with the public OSRM server. `annotations=duration,distance` gives per-edge timing; if it is unavailable, a constant-speed profile scaled to OSRM's totals is used.
3. **Slice** the route into equal-distance segments. Each segment contributes one vote, weighted by its length in the headline. The map shows the full slice; the forecast is sampled at its midpoint.
4. **ETA** at each midpoint is `departure + paceFactor × cumulative OSRM duration`.
5. **Weather** is fetched in bulk for unique 0.1° grid cells, cached in memory for 30 minutes, and reduced to the hourly bucket that contains each ETA.
6. **Wetness**: a segment is wet when forecast precipitation is `>= threshold`. The headline is wet distance ÷ total distance, rounded to the nearest 5%. The probability-weighted line is the distance-weighted mean precipitation probability, shown separately and used only as a departure tie-breaker.
7. **Best departure** checks now through +4 hours every 15 minutes. It recommends waiting only when the wet-segment count falls; ties go to the lower probability-weighted share, then the earlier departure.

## Data sources and attribution

- Weather: [Open-Meteo](https://open-meteo.com/) — free, keyless hourly forecasts.
- Place search: [Photon](https://photon.komoot.io/) by Komoot — free, keyless autocomplete.
- Routing: [OSRM](https://project-osrm.org/) public demo server — free, keyless driving routes.
- Maps: Apple MapKit.
- Map data and routing data: © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright).

The public OSRM demo server is intended for light use. RainRoute sends one route request per check and does not poll it.

## Limitations

- One fastest route; no alternatives, live traffic, turn-by-turn navigation, or en-route alerts.
- No radar nowcasting. The forecast is hourly; moving the slider steps the result at hour boundaries.
- The forecast sample is one point per segment. Rain inside a segment can differ.
- No saved trips, history, current-location button, or background refresh in v1.
- The weather cache is in memory only and disappears when the app is terminated.
- Long rides can reach beyond the three-day forecast horizon; RainRoute shows a forecast-gap error instead of guessing.

## Project layout

```text
RainRoute/
  RainRouteApp.swift        app entry point
  Core/                     Foundation-only route, forecast, wetness, departure logic
  Services/                 Photon, OSRM, Open-Meteo, HTTP, weather cache
  ViewModels/               screen state and persisted settings
  UI/                       SwiftUI screen and cards
RainRouteTests/             deterministic unit tests and inline JSON fixtures
project.yml                 XcodeGen manifest
.github/workflows/          macOS tests + unsigned IPA
docs/INSTALL.md             iloader walkthrough
```

Design and implementation records are in [`docs/superpowers/`](docs/superpowers/).

## License

MIT. See [LICENSE](LICENSE).
