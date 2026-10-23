import Combine
import CoreLocation
import Foundation

enum RouteSource: Equatable {
    case typed
    case googleMaps
}

struct LiveRideSnapshot: Equatable {
    let location: GeoCoordinate
    let progress: RouteProgress
    let result: WetnessResult
    let updatedAt: Date
    let accuracyMeters: Double
}

@MainActor
final class AppModel: ObservableObject {
    enum Field: Hashable {
        case start
        case destination
    }

    @Published var startQuery = ""
    @Published var destinationQuery = ""
    @Published private(set) var startSelection: Place?
    @Published private(set) var destinationSelection: Place?
    @Published private(set) var activeField: Field?
    @Published private(set) var suggestions: [Place] = []
    @Published private(set) var isSearchingPlaces = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var route: Route?
    @Published private(set) var result: WetnessResult?
    @Published private(set) var plan: DeparturePlan?
    @Published private(set) var referenceNow: Date?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var mapRevision = 0
    @Published var departureOffsetMinutes: Double = 0

    @Published private(set) var routeSource: RouteSource = .typed
    @Published private(set) var importedStops: [Place] = []
    @Published private(set) var isImporting = false
    @Published private(set) var liveSnapshot: LiveRideSnapshot?
    @Published private(set) var isRiding = false
    @Published private(set) var isWaitingForGPS = false
    @Published private(set) var hasArrived = false
    @Published private(set) var liveErrorMessage: String?

    private let geocoder: PhotonGeocoder
    private let router: OSRMRouter
    private let weatherRepository: WeatherRepository
    private let importer: GoogleMapsRouteImporter
    private let locationManager = RideLocationManager()

    private var forecasts: [GridCell: HourlyForecast] = [:]
    private var searchTask: Task<Void, Never>?
    private var geocodeCache: [String: [Place]] = [:]
    private var segmentReloadGeneration = 0
    private var rideSettings: AppSettings?
    private var lastFix: (coordinate: GeoCoordinate, accuracy: Double)?
    private var liveRefreshTask: Task<Void, Never>?

    init(
        geocoder: PhotonGeocoder = PhotonGeocoder(),
        router: OSRMRouter = OSRMRouter(),
        weatherRepository: WeatherRepository = WeatherRepository(),
        importer: GoogleMapsRouteImporter = GoogleMapsRouteImporter()
    ) {
        self.geocoder = geocoder
        self.router = router
        self.weatherRepository = weatherRepository
        self.importer = importer
    }

    var canCheck: Bool {
        let start = startQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return start.count >= 2
            && destination.count >= 2
            && !isLoading
            && !isImporting
            && !isRiding
    }

    var selectedDeparture: Date? {
        guard let referenceNow else { return nil }
        return referenceNow.addingTimeInterval(departureOffsetMinutes * 60)
    }

    var isShowingSuggestions: Bool {
        activeField != nil && !suggestions.isEmpty
    }

    var hasResult: Bool {
        result != nil && route != nil
    }

    var isOffRoute: Bool {
        (liveSnapshot?.progress.offRouteMeters ?? 0) > 500
    }

    var liveResult: WetnessResult? {
        isRiding ? liveSnapshot?.result : result
    }

    var mapStartCoordinate: GeoCoordinate? {
        if isRiding {
            return lastFix?.coordinate ?? route?.coordinates.first
        }
        return startSelection?.coordinate ?? route?.coordinates.first
    }

    var mapDestinationCoordinate: GeoCoordinate? {
        destinationSelection?.coordinate ?? route?.coordinates.last
    }

    /// Imported middle stops that are still ahead during a live ride.
    var mapWaypoints: [Place] {
        guard routeSource == .googleMaps else { return [] }
        guard isRiding, let route, let progress = liveSnapshot?.progress else {
            return importedStops
        }
        return importedStops.filter { stop in
            RouteProgressTracker.project(stop.coordinate, onto: route)
                .distanceMeters > progress.distanceMeters + 25
        }
    }

    func query(for field: Field) -> String {
        switch field {
        case .start: return startQuery
        case .destination: return destinationQuery
        }
    }

    func updateQuery(_ value: String, for field: Field) {
        guard !isRiding else { return }
        clearRouteOrigin()
        switch field {
        case .start:
            startQuery = value
            startSelection = nil
        case .destination:
            destinationQuery = value
            destinationSelection = nil
        }
        clearResult()
        activeField = field
        scheduleSearch(for: field)
    }

    func beginEditing(_ field: Field) {
        activeField = field
        let text = query(for: field).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2 {
            scheduleSearch(for: field)
        }
    }

    func endEditing() {
        activeField = nil
        suggestions = []
        isSearchingPlaces = false
        searchTask?.cancel()
    }

    func select(_ place: Place, for field: Field) {
        guard !isRiding else { return }
        clearRouteOrigin()
        switch field {
        case .start:
            startSelection = place
            startQuery = place.displayName
        case .destination:
            destinationSelection = place
            destinationQuery = place.displayName
        }
        activeField = nil
        suggestions = []
        isSearchingPlaces = false
        searchTask?.cancel()
        clearResult()
    }

    func clear(_ field: Field) {
        guard !isRiding else { return }
        clearRouteOrigin()
        switch field {
        case .start:
            startQuery = ""
            startSelection = nil
        case .destination:
            destinationQuery = ""
            destinationSelection = nil
        }
        activeField = field
        suggestions = []
        clearResult()
    }

    func swapEndpoints() {
        guard !isRiding else { return }
        clearRouteOrigin()
        let query = startQuery
        startQuery = destinationQuery
        destinationQuery = query

        let selection = startSelection
        startSelection = destinationSelection
        destinationSelection = selection

        activeField = nil
        suggestions = []
        clearResult()
    }

    func check(settings: AppSettings, forceRefresh: Bool = false) async {
        guard !isLoading, !isRiding else { return }
        errorMessage = nil
        isLoading = true
        defer {
            isLoading = false
            statusMessage = nil
        }

        do {
            statusMessage = "Finding places…"
            let start = try await resolvePlace(
                query: startQuery,
                selection: startSelection,
                label: "start"
            )
            let destination = try await resolvePlace(
                query: destinationQuery,
                selection: destinationSelection,
                label: "destination"
            )

            guard start.coordinate.distance(to: destination.coordinate) > 25 else {
                throw AppModelError.samePlace
            }

            startSelection = start
            startQuery = start.displayName
            destinationSelection = destination
            destinationQuery = destination.displayName
            activeField = nil
            suggestions = []

            let waypoints = routeSource == .googleMaps ? importedStops : []
            try await loadRoute(
                start: start,
                destination: destination,
                waypoints: waypoints,
                settings: settings,
                forceRefresh: forceRefresh
            )
        } catch is CancellationError {
            // The user moved on; no error needs to be shown.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(settings: AppSettings) async {
        if isRiding {
            await refreshLiveWeather(force: true, settings: settings)
        } else {
            await check(settings: settings, forceRefresh: true)
        }
    }

    func importGoogleMapsLink(_ rawLink: String, settings: AppSettings) async throws {
        guard !isImporting, !isLoading, !isRiding else {
            throw AppModelError.importUnavailable
        }

        isImporting = true
        isLoading = true
        statusMessage = "Reading the Google Maps link…"
        defer {
            isImporting = false
            isLoading = false
            statusMessage = nil
        }

        let imported = try await importer.importRoute(from: rawLink)

        try await loadRoute(
            start: imported.origin,
            destination: imported.destination,
            waypoints: imported.waypoints,
            settings: settings,
            forceRefresh: false
        )

        startSelection = imported.origin
        startQuery = imported.origin.displayName
        destinationSelection = imported.destination
        destinationQuery = imported.destination.displayName
        importedStops = imported.waypoints
        routeSource = .googleMaps
        activeField = nil
        suggestions = []
    }

    func clearImportedRoute(settings: AppSettings) async {
        guard !isRiding else { return }
        guard routeSource == .googleMaps else { return }
        routeSource = .typed
        importedStops = []
        await check(settings: settings, forceRefresh: false)
    }

    func segmentCountChanged(settings: AppSettings) async {
        guard let route, !forecasts.isEmpty else { return }
        if isRiding {
            rideSettings = settings
        }

        segmentReloadGeneration += 1
        let generation = segmentReloadGeneration

        do {
            let cells = try RouteSlicer.gridCells(
                route: route,
                segmentCount: settings.segmentCount
            )
            let now = Date()
            let updated = try await weatherRepository.forecasts(
                for: cells,
                now: now,
                forceRefresh: false
            )
            guard generation == segmentReloadGeneration else { return }
            forecasts = updated
            lastUpdated = now
            recompute(settings: settings)
            updateLiveSnapshot(settings: settings)
        } catch is CancellationError {
            // A newer segment count won.
        } catch {
            guard generation == segmentReloadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func recompute(settings: AppSettings) {
        guard let route,
              let referenceNow,
              !forecasts.isEmpty else {
            return
        }

        do {
            let departure = referenceNow.addingTimeInterval(departureOffsetMinutes * 60)
            let result = try WetnessEngine.evaluate(
                route: route,
                departure: departure,
                paceFactor: settings.paceFactor,
                threshold: settings.wetThreshold,
                forecasts: forecasts,
                segmentCount: settings.segmentCount
            )
            let plan = try DeparturePlanner.plan(
                route: route,
                now: referenceNow,
                paceFactor: settings.paceFactor,
                threshold: settings.wetThreshold,
                forecasts: forecasts,
                segmentCount: settings.segmentCount
            )
            self.result = result
            self.plan = plan
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateDepartureOffset(_ minutes: Double, settings: AppSettings) {
        departureOffsetMinutes = min(max(minutes, 0), 240)
        recompute(settings: settings)
    }

    func useBestDeparture(settings: AppSettings) {
        guard let plan,
              plan.shouldWait,
              let referenceNow else {
            return
        }
        let minutes = plan.bestDeparture.timeIntervalSince(referenceNow) / 60
        departureOffsetMinutes = min(max(minutes, 0), 240)
        recompute(settings: settings)
    }

    /// Applies pace and threshold changes without refetching forecasts.
    func settingsChanged(settings: AppSettings) {
        if isRiding {
            rideSettings = settings
        }
        recompute(settings: settings)
        if isRiding {
            updateLiveSnapshot(settings: settings)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func startRide(settings: AppSettings) {
        guard !isRiding else { return }
        guard route != nil, result != nil else {
            errorMessage = "Check a route before starting a ride."
            return
        }
        guard RideLocationManager.locationServicesEnabled else {
            errorMessage = "Location Services are off. Turn them on in Settings to start a live ride."
            return
        }

        let status = locationManager.authorizationStatus
        if status == .denied || status == .restricted {
            errorMessage = "Location permission is off. Allow RainRoute in Settings > Privacy & Security > Location Services to start a live ride."
            return
        }

        liveErrorMessage = nil
        hasArrived = false
        isWaitingForGPS = true
        isRiding = true
        rideSettings = settings
        installLocationCallbacks()

        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            locationManager.start()
        }

        startLiveRefreshTask()

        if let firstCoordinate = route?.coordinates.first {
            lastFix = (firstCoordinate, 0)
            updateLiveSnapshot(settings: settings)
            isWaitingForGPS = true
        }
    }

    func endRide() {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
        locationManager.stop()
        locationManager.onLocation = nil
        locationManager.onAuthorization = nil
        rideSettings = nil
        lastFix = nil
        liveSnapshot = nil
        liveErrorMessage = nil
        isRiding = false
        isWaitingForGPS = false
        hasArrived = false
    }

    func pauseRideUpdates() {
        guard isRiding else { return }
        locationManager.stop()
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
    }

    func resumeRideUpdates(settings: AppSettings) async {
        guard isRiding else { return }
        locationManager.start()
        startLiveRefreshTask()

        if let lastUpdated,
           Date().timeIntervalSince(lastUpdated) < 600 {
            updateLiveSnapshot(settings: settings)
        } else {
            await refreshLiveWeather(force: true, settings: settings)
        }
    }

    func recalculateFromHere(settings: AppSettings) async {
        guard isRiding,
              let route,
              let fix = lastFix,
              let destination = destinationSelection else {
            return
        }

        let progress = RouteProgressTracker.project(fix.coordinate, onto: route)
        let remainingStops = importedStops.filter { stop in
            RouteProgressTracker.project(stop.coordinate, onto: route)
                .distanceMeters > progress.distanceMeters + 25
        }
        let currentLocation = Place(
            id: "current-location",
            name: "Current location",
            subtitle: "GPS position",
            coordinate: fix.coordinate
        )

        do {
            try await loadRoute(
                start: currentLocation,
                destination: destination,
                waypoints: remainingStops,
                settings: settings,
                forceRefresh: false
            )
            startSelection = currentLocation
            startQuery = currentLocation.displayName
            importedStops = remainingStops
            lastFix = (fix.coordinate, fix.accuracy)
            updateLiveSnapshot(settings: settings)
        } catch {
            liveErrorMessage = error.localizedDescription
        }
    }

    private func installLocationCallbacks() {
        locationManager.onLocation = { [weak self] coordinate, accuracy in
            self?.handleLocation(coordinate, accuracy: accuracy)
        }
        locationManager.onAuthorization = { [weak self] status in
            self?.handleAuthorization(status)
        }
    }

    private func handleLocation(_ coordinate: GeoCoordinate, accuracy: Double) {
        guard isRiding else { return }
        lastFix = (coordinate, accuracy)
        if let settings = rideSettings {
            updateLiveSnapshot(settings: settings)
        }
        isWaitingForGPS = false
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        guard isRiding else { return }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.start()
        case .denied, .restricted:
            errorMessage = "Location permission is needed for a live ride. Allow RainRoute in Settings > Privacy & Security > Location Services."
            endRide()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    private func updateLiveSnapshot(settings: AppSettings) {
        guard isRiding,
              let route,
              let fix = lastFix,
              !forecasts.isEmpty else {
            return
        }

        do {
            let now = Date()
            let progress = RouteProgressTracker.project(fix.coordinate, onto: route)
            let progressDuration = RouteSlicer.duration(
                at: progress.distanceMeters,
                route: route
            )

            if RouteProgressTracker.hasArrived(progress, route: route) {
                hasArrived = true
                return
            }

            let remainingDuration = max(
                0,
                settings.paceFactor * (route.totalDurationSeconds - progressDuration)
            )

            guard let remaining = try WetnessEngine.evaluateRemaining(
                route: route,
                now: now,
                paceFactor: settings.paceFactor,
                threshold: settings.wetThreshold,
                forecasts: forecasts,
                segmentCount: settings.segmentCount,
                progressDistanceMeters: progress.distanceMeters,
                remainingDuration: remainingDuration
            ) else {
                hasArrived = true
                return
            }

            liveSnapshot = LiveRideSnapshot(
                location: fix.coordinate,
                progress: progress,
                result: remaining,
                updatedAt: now,
                accuracyMeters: fix.accuracy
            )
            hasArrived = false
        } catch {
            liveErrorMessage = error.localizedDescription
        }
    }

    private func refreshLiveWeather(force: Bool, settings: AppSettings) async {
        guard let route else { return }

        do {
            let cells = try RouteSlicer.gridCells(
                route: route,
                segmentCount: settings.segmentCount
            )
            let now = Date()
            let updated = try await weatherRepository.forecasts(
                for: cells,
                now: now,
                forceRefresh: force
            )
            forecasts = updated
            lastUpdated = now
            recompute(settings: settings)
            updateLiveSnapshot(settings: settings)
            liveErrorMessage = nil
        } catch is CancellationError {
            // The ride ended or the app moved on.
        } catch {
            liveErrorMessage = error.localizedDescription
        }
    }

    private func startLiveRefreshTask() {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 600_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      let self,
                      self.isRiding,
                      let settings = self.rideSettings else {
                    return
                }
                await self.refreshLiveWeather(force: true, settings: settings)
            }
        }
    }

    private func loadRoute(
        start: Place,
        destination: Place,
        waypoints: [Place],
        settings: AppSettings,
        forceRefresh: Bool
    ) async throws {
        statusMessage = "Finding the fastest route…"
        let coordinates = [start.coordinate]
            + waypoints.map(\.coordinate)
            + [destination.coordinate]
        let route = try await router.route(through: coordinates)

        statusMessage = "Fetching hourly forecasts…"
        let cells = try RouteSlicer.gridCells(
            route: route,
            segmentCount: settings.segmentCount
        )
        let now = Date()
        let forecasts = try await weatherRepository.forecasts(
            for: cells,
            now: now,
            forceRefresh: forceRefresh
        )

        self.route = route
        self.forecasts = forecasts
        referenceNow = now
        lastUpdated = now
        departureOffsetMinutes = 0
        mapRevision += 1
        recompute(settings: settings)
    }

    private func resolvePlace(
        query: String,
        selection: Place?,
        label: String
    ) async throws -> Place {
        if let selection {
            return selection
        }

        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            throw AppModelError.missingPlace(label)
        }

        let places: [Place]
        if let cached = geocodeCache[text.lowercased()] {
            places = cached
        } else {
            places = try await geocoder.search(text)
            geocodeCache[text.lowercased()] = places
        }

        guard let first = places.first else {
            throw AppModelError.noPlace(label, text)
        }
        return first
    }

    private func scheduleSearch(for field: Field) {
        searchTask?.cancel()
        let text = query(for: field).trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.count >= 2 else {
            suggestions = []
            isSearchingPlaces = false
            return
        }

        if let cached = geocodeCache[text.lowercased()] {
            suggestions = cached
            isSearchingPlaces = false
            return
        }

        isSearchingPlaces = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.activeField == field,
                  self.query(for: field).trimmingCharacters(in: .whitespacesAndNewlines) == text else {
                return
            }

            do {
                let places = try await self.geocoder.search(text)
                guard !Task.isCancelled,
                      self.activeField == field,
                      self.query(for: field).trimmingCharacters(in: .whitespacesAndNewlines) == text else {
                    return
                }
                self.geocodeCache[text.lowercased()] = places
                self.suggestions = places
                self.isSearchingPlaces = false
            } catch {
                guard !Task.isCancelled else { return }
                self.suggestions = []
                self.isSearchingPlaces = false
            }
        }
    }

    private func clearRouteOrigin() {
        routeSource = .typed
        importedStops = []
    }

    private func clearResult() {
        route = nil
        result = nil
        plan = nil
        referenceNow = nil
        lastUpdated = nil
        forecasts = [:]
        departureOffsetMinutes = 0
    }
}

enum AppModelError: LocalizedError {
    case missingPlace(String)
    case noPlace(String, String)
    case samePlace
    case importUnavailable

    var errorDescription: String? {
        switch self {
        case .missingPlace(let label):
            return "Enter a \(label) with at least two letters."
        case .noPlace(let label, let query):
            return "No \(label) found for “\(query)”. Try a nearby town or landmark."
        case .samePlace:
            return "The start and destination are the same place."
        case .importUnavailable:
            return "Finish the current request before importing another route."
        }
    }
}
