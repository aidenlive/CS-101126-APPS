import Foundation
import Observation
import CardsiteKit

/// Reference data every resource editor's pickers read: the targeting
/// vocabulary, the workspace's domains, projects and splash pages, and what
/// the plan includes.
///
/// Usage:
///
///     let options = ResourceOptionsModel(client: app.client)
///     options.onError = app.handle
///     …
///     .task { await options.loadIfNeeded() }
///     DisplayRulesSection(rules: $form.rules, options: options.targeting.value,
///                         loadFailed: options.targeting.error != nil,
///                         isLocked: !options.allowsTargeting)
///
/// Each piece loads on its own: a failed domain list never blocks the
/// targeting pickers. A plan that can't be read locks nothing, because the
/// server enforces every capability on write anyway; locking on a network
/// blip would only take away controls the user is entitled to.
@MainActor
@Observable
final class ResourceOptionsModel {
    private(set) var targeting: Loadable<TargetingOptions> = .idle
    /// Every domain in the workspace. Use ``usableDomains(keeping:)`` for a picker.
    private(set) var domains: [DomainOption] = []
    private(set) var projects: [ProjectOption] = []
    private(set) var splashPages: [SplashPageOption] = []
    /// nil until read, and after a failed read.
    private(set) var capabilities: PlanCapabilities?
    /// True when the domain, project or splash page list could not be read.
    private(set) var pickersFailed = false

    @ObservationIgnored var onError: @MainActor (any Error) -> Void = { _ in }

    private let client: APIClient
    private var loadedAt: Date?
    /// Domains, projects and splash pages change rarely; refetch after this.
    private let freshFor: TimeInterval = 300

    init(client: APIClient) {
        self.client = client
    }

    /// Preview and test seam: options already in hand.
    init(client: APIClient, targeting: TargetingOptions?, domains: [DomainOption] = [], projects: [ProjectOption] = [],
         splashPages: [SplashPageOption] = [], capabilities: PlanCapabilities? = .unrestricted) {
        self.client = client
        if let targeting { self.targeting = .loaded(targeting) }
        self.domains = domains
        self.projects = projects
        self.splashPages = splashPages
        self.capabilities = capabilities
        self.loadedAt = .now
    }

    var allowsTargeting: Bool { capabilities?.targeting ?? true }
    var allowsPasswordProtection: Bool { capabilities?.passwordProtection ?? true }

    /// Verified, enabled domains, plus `selectedID` if a resource already
    /// uses a domain that is no longer usable (so the picker can show it).
    func usableDomains(keeping selectedID: Int? = nil) -> [DomainOption] {
        domains.filter { $0.isUsable || $0.id == selectedID }
    }

    func loadIfNeeded() async {
        if let loadedAt, Date.now.timeIntervalSince(loadedAt) < freshFor, targeting.value != nil { return }
        await load()
    }

    func load() async {
        if targeting.value == nil { targeting = .loading }
        let client = self.client
        async let targetingResult = Self.capture { try await client.targetingOptions() }
        async let domainsResult = Self.capture { try await client.domainOptions() }
        async let projectsResult = Self.capture { try await client.projectOptions() }
        async let splashResult = Self.capture { try await client.splashPageOptions() }
        async let capabilitiesResult = Self.capture { try await client.planCapabilities() }

        let (targetingOutcome, domainsOutcome, projectsOutcome, splashOutcome, capabilitiesOutcome) =
            await (targetingResult, domainsResult, projectsResult, splashResult, capabilitiesResult)
        if Task.isCancelled { return }

        var pickersFailed = false
        switch targetingOutcome {
        case .success(let value): targeting = .loaded(value)
        case .failure(let error):
            report(error)
            if targeting.value == nil { targeting = .failed(error.asAPIError) }
        }
        switch domainsOutcome {
        case .success(let value): domains = value
        case .failure(let error): report(error); pickersFailed = true
        }
        switch projectsOutcome {
        case .success(let value): projects = value
        case .failure(let error): report(error); pickersFailed = true
        }
        switch splashOutcome {
        case .success(let value): splashPages = value
        case .failure(let error): report(error); pickersFailed = true
        }
        switch capabilitiesOutcome {
        case .success(let value): capabilities = value
        case .failure(let error): report(error)
        }
        self.pickersFailed = pickersFailed
        loadedAt = .now
    }

    private func report(_ error: any Error) {
        if error is CancellationError { return }
        onError(error)
    }

    nonisolated private static func capture<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, any Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}
