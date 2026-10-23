import Combine
import Foundation

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

    private let geocoder: PhotonGeocoder
    private let router: OSRMRouter
    private let weatherRepository: WeatherRepository
    private var forecasts: [GridCell: HourlyForecast] = [:]
    private var searchTask: Task<Void, Never>?
    private var geocodeCache: [String: [Place]] = [:]

    init(
        geocoder: PhotonGeocoder = PhotonGeocoder(),
        router: OSRMRouter = OSRMRouter(),
        weatherRepository: WeatherRepository = WeatherRepository()
    ) {
        self.geocoder = geocoder
        self.router = router
        self.weatherRepository = weatherRepository
    }

    var canCheck: Bool {
        let start = startQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return start.count >= 2 && destination.count >= 2 && !isLoading
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

    func query(for field: Field) -> String {
        switch field {
        case .start: return startQuery
        case .destination: return destinationQuery
        }
    }

    func updateQuery(_ value: String, for field: Field) {
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
        guard !isLoading else { return }
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

            statusMessage = "Finding the fastest route…"
            let route = try await router.route(
                from: start.coordinate,
                to: destination.coordinate
            )

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
        } catch is CancellationError {
            // The user moved on; no error needs to be shown.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(settings: AppSettings) async {
        await check(settings: settings, forceRefresh: true)
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

    func dismissError() {
        errorMessage = nil
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

    var errorDescription: String? {
        switch self {
        case .missingPlace(let label):
            return "Enter a \(label) with at least two letters."
        case .noPlace(let label, let query):
            return "No \(label) found for “\(query)”. Try a nearby town or landmark."
        case .samePlace:
            return "The start and destination are the same place."
        }
    }
}
