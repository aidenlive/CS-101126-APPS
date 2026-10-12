import Foundation

/// Reference data and pickers for resource editors.
extension APIClient {
    /// The targeting vocabulary. Public: no token needed, the same for everyone.
    public func targetingOptions() async throws -> TargetingOptions {
        try await send(.get, "api/v1/reference/targeting", authenticated: false)
    }

    /// Up to 100 projects in the current workspace, for pickers.
    public func projectOptions() async throws -> [ProjectOption] {
        let page: Page<ProjectOption> = try await sendPage("api/v1/projects", page: 1, query: ["results_per_page": "100"])
        return page.items
    }

    /// Up to 100 custom domains in the current workspace, verified or not.
    /// Filter with ``DomainOption/isUsable`` for an address picker.
    public func domainOptions() async throws -> [DomainOption] {
        let page: Page<DomainOption> = try await sendPage("api/v1/domains", page: 1, query: ["results_per_page": "100"])
        return page.items
    }

    /// Up to 100 splash pages in the current workspace, for pickers.
    public func splashPageOptions() async throws -> [SplashPageOption] {
        let page: Page<SplashPageOption> = try await sendPage("api/v1/splash-pages", page: 1, query: ["results_per_page": "100"])
        return page.items
    }

    /// What the plan includes, resolved the way the server resolves it
    /// (`UserRepository.GetEffectivePlanSettings`): the plan's own
    /// `settings` (the matching plan from `GET /plans`, else the default
    /// plan), with the account's `plan_settings` override laid over them key
    /// by key. `plan_settings` is `null` for most accounts (fixture 10a).
    public func planCapabilities() async throws -> PlanCapabilities {
        let account: JSONValue = try await send(.get, "api/v1/account/plan")
        let plans: [JSONValue]? = try await sendOptional(.get, "api/v1/plans")
        return PlanCapabilities.effective(
            plans: plans ?? [],
            planID: account["plan_id"]?.intValue,
            override: account["plan_settings"]?.objectValue ?? [:]
        )
    }
}
