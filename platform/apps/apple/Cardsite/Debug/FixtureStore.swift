#if DEBUG
import Foundation
import CardsiteKit

typealias FixtureObject = [String: JSONValue]

/// The fixture server's state: one account, seeded on first use from the
/// contract fixtures in `Debug/Fixtures` (each `{_request, response}`; the
/// `response` is what is served or used as a row template). Every route
/// follows the observed contract in `ContractTests/README.md`: `data:null`
/// for an empty list, `{page, per_page, total}` meta, the error envelope,
/// 401 for a wrong password on credential checks, and so on.
///
/// The account's password is ``FixtureMode/password``; the 2FA code is
/// ``FixtureMode/twoFactorCode``.
actor FixtureStore {
    private let startsEmpty: Bool
    private let now = Date()
    private var seeded = false

    private var user: FixtureObject = [:]
    private var plan: FixtureObject = [:]
    private var password = FixtureMode.password
    private var twoFactorEnabled = false
    private var accountDeleted = false
    private var preferences: FixtureObject = [:]
    private var tokenScopes: [JSONValue] = []

    /// Link-shaped rows of every type: link, biolink, vcard, event,
    /// payment_link, file, static.
    private var resources: [FixtureObject] = []
    /// Every other collection, keyed by its path segment (`qr-codes`, `projects`, …).
    private var tables: [String: [FixtureObject]] = [:]
    private var workspaces: [FixtureObject] = []
    /// Members by workspace id.
    private var members: [Int: [FixtureObject]] = [:]

    private var nextID = 1000
    private var cache: [String: JSONValue] = [:]

    init(empty: Bool = false) {
        self.startsEmpty = empty
    }

    // MARK: Routing

    func respond(to request: FixtureRequest) -> FixtureReply {
        if !seeded {
            seed()
            seeded = true
        }
        let segments = request.path
        let method = request.method
        let body = request.body

        /// Matches `segments` against a pattern such as `links/{}/duplicate`
        /// and returns the `{}` captures.
        func match(_ verb: String, _ pattern: String) -> [String]? {
            guard verb == method else { return nil }
            let parts = pattern.split(separator: "/").map(String.init)
            guard parts.count == segments.count else { return nil }
            var captures: [String] = []
            for (part, segment) in zip(parts, segments) {
                if part == "{}" {
                    captures.append(segment)
                } else if part != segment {
                    return nil
                }
            }
            return captures
        }

        // Public routes.
        if match("POST", "auth/login") != nil { return signIn(body) }
        if match("POST", "auth/register") != nil { return register(body) }
        if match("POST", "auth/lost-password") != nil {
            return .message("If an account exists with that email, a reset link has been sent")
        }
        if match("POST", "auth/reset-password") != nil { return .message("Password has been reset") }
        if match("GET", "reference/targeting") != nil { return passthrough("21k-reference-targeting-200") }
        if match("GET", "plans") != nil { return passthrough("10b-plans-200") }

        // Everything else needs the bearer token.
        guard request.hasBearer else { return .error(401, "Unauthorized") }
        guard !accountDeleted else { return .error(401, "Invalid or expired token") }
        if let workspace = request.workspaceID, !workspaces.contains(where: { $0["workspace_id"]?.intValue == workspace }) {
            return .error(403, "You are not a member of this workspace")
        }

        // Account.
        if match("GET", "user") != nil { return .ok(.object(user)) }
        if match("PUT", "account") != nil { return updateAccount(body) }
        if match("DELETE", "account") != nil { return deleteAccount(body) }
        if match("GET", "account/plan") != nil { return .ok(.object(plan)) }
        if match("PUT", "account/password") != nil { return changePassword(body) }
        if match("GET", "account/preferences") != nil { return .ok(.object(preferences)) }
        if match("PUT", "account/preferences") != nil {
            preferences = body
            return .ok(.object(preferences))
        }
        if match("GET", "account/tokens") != nil {
            return .ok(["scopes": .array(tokenScopes), "tokens": .array(rows("tokens").map(JSONValue.object))])
        }
        if match("POST", "account/tokens") != nil { return createToken(body) }
        if let id = match("DELETE", "account/tokens/{}") {
            return remove(from: "tokens", id: id[0], idKey: "id", message: "Token revoked", missing: "Token not found")
        }

        // Two-factor.
        if match("POST", "auth/2fa/setup") != nil {
            let email = user["email"]?.stringValue ?? "you@example.com"
            return .ok([
                "secret": "JBSWY3DPEHPK3PXP",
                "provisioning_url": .string("otpauth://totp/Cardsite:\(email)?secret=JBSWY3DPEHPK3PXP&issuer=Cardsite"),
            ])
        }
        if match("POST", "auth/2fa/verify") != nil {
            guard body["code"]?.stringValue == FixtureMode.twoFactorCode else { return .error(401, "Invalid 2FA code") }
            twoFactorEnabled = true
            user["twofa_enabled"] = true
            let codes = (1...10).map { JSONValue.string(String(format: "CSFX-%04d-%04d", $0 * 1373 % 10_000, $0 * 7919 % 10_000)) }
            return .ok(["message": "2FA enabled successfully", "recovery_codes": .array(codes)])
        }
        if match("GET", "auth/2fa/recovery-codes") != nil {
            return .ok(["remaining": .int(twoFactorEnabled ? 10 : 0), "twofa_enabled": .bool(twoFactorEnabled)])
        }
        if match("DELETE", "auth/2fa") != nil {
            guard body["password"]?.stringValue == password else { return .error(401, "Invalid password") }
            twoFactorEnabled = false
            user["twofa_enabled"] = false
            return .message("2FA disabled successfully")
        }

        // Workspaces.
        if match("GET", "workspaces") != nil { return .ok(.array(workspaces.map(JSONValue.object))) }
        if match("POST", "workspaces") != nil { return createWorkspace(body) }
        if match("GET", "workspaces/activity") != nil { return activity(limit: Int(request.query["limit"] ?? "") ?? 25) }
        if let id = match("PUT", "workspaces/{}") { return renameWorkspace(id[0], body) }
        if let id = match("DELETE", "workspaces/{}") { return deleteWorkspace(id[0]) }
        if let id = match("POST", "workspaces/{}/leave") { return deleteWorkspace(id[0], leaving: true) }
        if let id = match("GET", "workspaces/{}/members") {
            guard let workspace = Int(id[0]), let list = members[workspace] else { return .error(404, "Workspace not found") }
            return .ok(.array(list.map(JSONValue.object)))
        }
        if let id = match("POST", "workspaces/{}/members") { return addMember(id[0], body) }
        if let ids = match("PUT", "workspaces/{}/members/{}") { return updateMember(ids[0], ids[1], body) }
        if let ids = match("DELETE", "workspaces/{}/members/{}") { return removeMember(ids[0], ids[1]) }

        // Dashboard and statistics.
        if match("GET", "statistics") != nil { return summary() }
        if let id = match("GET", "statistics/{}") { return statistics(id[0], request.query) }
        if match("GET", "resources/recent") != nil {
            let limit = min(max(Int(request.query["limit"] ?? "") ?? 5, 1), 50)
            let recent = resources.sorted(by: Self.newestFirst).prefix(limit).map { row -> JSONValue in
                // Quirk 6: these columns are not selected by the recent query.
                var row = row
                row["lifecycle_state"] = ""
                row["last_used_at"] = "0001-01-01T00:00:00Z"
                row["lifecycle_state_at"] = "0001-01-01T00:00:00Z"
                return .object(row)
            }
            return .ok(.array(recent))
        }
        if match("GET", "spotlight") != nil { return spotlight(request.query["q"] ?? "") }

        // Reference lists.
        if match("GET", "qr-codes/types") != nil { return passthrough("23a-qr-codes-types-200") }
        if match("GET", "pixels/types") != nil { return passthrough("21f-pixels-types-200") }
        if match("GET", "biolink-blocks/types") != nil { return passthrough("24b-biolink-blocks-types-200") }
        if match("POST", "qr-codes/generate") != nil { return generateQRCode(body) }

        // Resource specials.
        if let id = match("GET", "biolinks/{}") {
            guard let page = resource(id[0], kind: "biolink") else { return .error(404, "Biolink not found") }
            let blocks = rows("biolink-blocks")
                .filter { $0["link_id"]?.intValue == page["id"]?.intValue }
                .sorted { ($0["order"]?.intValue ?? 0) < ($1["order"]?.intValue ?? 0) }
            return .ok(["biolink": .object(page), "blocks": .array(blocks.map(JSONValue.object))])
        }
        if let id = match("POST", "links/{}/duplicate") { return duplicateLink(id[0]) }
        if let id = match("POST", "domains/{}/verify") {
            return update(in: "domains", id: id[0], with: ["is_verified": true], missing: "Domain not found")
        }
        if match("POST", "biolink-blocks/order") != nil { return reorderBlocks(body) }
        if let id = match("PUT", "biolink-blocks/{}") { return updateBlock(id[0], body) }

        // Inbox.
        if match("GET", "internal-notifications/unread") != nil {
            let unread = rows("internal-notifications").filter { $0["is_read"]?.boolValue == false }.sorted(by: Self.newestFirst)
            return .ok([
                "notifications": unread.isEmpty ? .null : .array(unread.prefix(5).map(JSONValue.object)),
                "unread_count": .int(unread.count),
            ])
        }
        if match("POST", "internal-notifications/read-all") != nil {
            tables["internal-notifications"] = rows("internal-notifications").map { row -> FixtureObject in
                var row = row
                row["is_read"] = true
                return row
            }
            return .message("All notifications marked as read")
        }
        if let id = match("POST", "internal-notifications/{}/read") {
            let reply = update(in: "internal-notifications", id: id[0], with: ["is_read": true], missing: "Notification not found")
            return reply.status == 200 ? .message("Notification marked as read") : reply
        }

        // Link-shaped collections.
        if let segment = segments.first, let kind = Self.resourceKinds[segment] {
            let missing = Self.missingTitles[segment] ?? "Resource not found"
            if match("GET", segment) != nil {
                return list(resources.filter { $0["type"]?.stringValue == kind }, query: request.query)
            }
            if let id = match("GET", segment + "/{}") {
                guard let row = resource(id[0], kind: kind) else { return .error(404, missing) }
                return .ok(.object(row))
            }
            if match("POST", segment) != nil { return createResource(kind: kind, body) }
            if let id = match("PUT", segment + "/{}") { return updateResource(id[0], kind: kind, body, missing: missing) }
            if let id = match("DELETE", segment + "/{}") {
                guard let index = resources.firstIndex(where: { "\($0["id"]?.intValue ?? -1)" == id[0] && $0["type"]?.stringValue == kind }) else {
                    return .error(404, missing)
                }
                resources.remove(at: index)
                return .message(kind == "link" ? "Link deleted" : "Deleted")
            }
        }

        // Every other collection.
        if let segment = segments.first, Self.tableNames.contains(segment) {
            let idKey = segment == "uploads" ? "upload_id" : "id"
            let missing = Self.missingTitles[segment] ?? "Not found"
            if match("GET", segment) != nil { return list(rows(segment), query: request.query) }
            if let id = match("GET", segment + "/{}") {
                guard let row = rows(segment).first(where: { "\($0[idKey]?.intValue ?? -1)" == id[0] }) else {
                    return .error(404, missing)
                }
                return .ok(.object(row))
            }
            if match("POST", segment) != nil, Self.creatable.contains(segment) { return create(in: segment, body) }
            if let id = match("PUT", segment + "/{}") { return update(in: segment, id: id[0], with: body, missing: missing) }
            if let id = match("DELETE", segment + "/{}") {
                let message = segment == "uploads" ? "Upload deleted" : segment == "data" ? "Data deleted" : "Deleted"
                return remove(from: segment, id: id[0], idKey: idKey, message: message, missing: missing)
            }
        }

        return .notFound
    }

    private static let resourceKinds: [String: String] = [
        "links": "link", "biolinks": "biolink", "vcards": "vcard", "events": "event",
        "payment-links": "payment_link", "files": "file", "static": "static",
    ]
    private static let tableNames: Set<String> = [
        "qr-codes", "projects", "domains", "pixels", "splash-pages", "uploads", "data",
        "internal-notifications", "logs", "biolink-blocks",
    ]
    private static let creatable: Set<String> = [
        "qr-codes", "projects", "domains", "pixels", "splash-pages", "uploads", "biolink-blocks",
    ]
    private static let missingTitles: [String: String] = [
        "links": "Link not found", "biolinks": "Biolink not found", "events": "Event not found",
        "payment-links": "Payment link not found", "files": "File link not found",
        "qr-codes": "QR code not found", "projects": "Project not found", "domains": "Domain not found",
        "pixels": "Pixel not found", "data": "Data record not found", "biolink-blocks": "Block not found",
        "internal-notifications": "Notification not found",
    ]

    // MARK: Auth and account

    private func signIn(_ body: FixtureObject) -> FixtureReply {
        guard !accountDeleted, body["password"]?.stringValue == password else {
            return .error(401, "Invalid email or password")
        }
        if twoFactorEnabled {
            let code = body["twofa_token"]?.stringValue ?? ""
            let recovery = body["recovery_code"]?.stringValue ?? ""
            if code.isEmpty && recovery.isEmpty { return .ok(["twofa_required": true]) }
            if !recovery.isEmpty {
                return .ok(["token": .string(FixtureMode.token), "user": .object(user), "recovery_codes_remaining": 9])
            }
            guard code == FixtureMode.twoFactorCode else { return .error(401, "Invalid 2FA code") }
        }
        return .ok(["token": .string(FixtureMode.token), "user": .object(user)])
    }

    private func register(_ body: FixtureObject) -> FixtureReply {
        let email = body["email"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        let newPassword = body["password"]?.stringValue ?? ""
        guard email.contains("@") else { return .error(400, "Invalid email address") }
        guard (8...64).contains(newPassword.count) else { return .error(400, "Password must be between 8 and 64 characters") }
        user["email"] = .string(email)
        user["name"] = .string(body["name"]?.stringValue ?? "")
        user["total_logins"] = 0
        password = newPassword
        accountDeleted = false
        return .ok(["token": .string(FixtureMode.token), "user": .object(user)], status: 201)
    }

    private func updateAccount(_ body: FixtureObject) -> FixtureReply {
        if let name = body["name"]?.stringValue {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return .error(400, "Name is required") }
            user["name"] = .string(name)
        }
        for key in ["timezone", "language", "is_newsletter_subscribed"] {
            if let value = body[key] { user[key] = value }
        }
        return .ok(.object(user))
    }

    private func deleteAccount(_ body: FixtureObject) -> FixtureReply {
        let given = body["password"]?.stringValue ?? ""
        guard !given.isEmpty else { return .error(400, "Password is required to confirm account deletion") }
        guard given == password else { return .error(401, "Password is incorrect") }
        accountDeleted = true
        return .message("Account deleted successfully")
    }

    private func changePassword(_ body: FixtureObject) -> FixtureReply {
        guard body["current_password"]?.stringValue == password else { return .error(401, "Current password is incorrect") }
        let next = body["new_password"]?.stringValue ?? ""
        guard (8...64).contains(next.count) else { return .error(400, "New password must be between 8 and 64 characters") }
        password = next
        return .message("Password updated")
    }

    private func createToken(_ body: FixtureObject) -> FixtureReply {
        let name = body["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return .error(400, "Name is required") }
        let scopes = body["scopes"]?.arrayValue ?? []
        if let unknown = scopes.first(where: { !tokenScopes.contains($0) }) {
            return .error(400, "Unknown scope: \(unknown.stringValue ?? "")")
        }
        var token = row("26c-account-tokens-create-201", path: "token")
        token["id"] = .int(makeID())
        token["name"] = .string(name)
        token["scopes"] = .array(scopes)
        token["created_at"] = timestamp(0)
        tables["tokens", default: []].append(token)
        return .ok([
            "secret": .string("cst_fixture_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"),
            "notice": "Store this secret now — it is shown only once.",
            "token": .object(token),
        ], status: 201)
    }

    // MARK: Workspaces

    private func createWorkspace(_ body: FixtureObject) -> FixtureReply {
        let name = body["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return .error(400, "Name is required") }
        var workspace = workspaces.first ?? [:]
        let id = makeID()
        workspace["workspace_id"] = .int(id)
        workspace["name"] = .string(name)
        workspace["is_personal"] = false
        workspace["role"] = "owner"
        workspace["storage_bytes"] = 0
        workspace["created_at"] = timestamp(0)
        workspaces.append(workspace)
        members[id] = [member(name: user["name"]?.stringValue ?? "", email: user["email"]?.stringValue ?? "",
                              userID: userID, role: "owner", workspace: id, age: 0)]
        return .ok(.object(workspace), status: 201)
    }

    private func renameWorkspace(_ id: String, _ body: FixtureObject) -> FixtureReply {
        guard let index = workspaces.firstIndex(where: { "\($0["workspace_id"]?.intValue ?? -1)" == id }) else {
            return .error(404, "Workspace not found")
        }
        if let name = body["name"]?.stringValue, !name.isEmpty { workspaces[index]["name"] = .string(name) }
        return .ok(.object(workspaces[index]))
    }

    private func deleteWorkspace(_ id: String, leaving: Bool = false) -> FixtureReply {
        guard let index = workspaces.firstIndex(where: { "\($0["workspace_id"]?.intValue ?? -1)" == id }) else {
            return .error(404, "Workspace not found")
        }
        guard workspaces[index]["is_personal"]?.boolValue != true else {
            return .error(400, leaving ? "You cannot leave your personal workspace" : "Personal workspaces cannot be deleted")
        }
        workspaces.remove(at: index)
        return .message(leaving ? "Left workspace" : "Workspace deleted")
    }

    private func addMember(_ id: String, _ body: FixtureObject) -> FixtureReply {
        guard let workspace = Int(id), let owner = workspaces.first(where: { $0["workspace_id"]?.intValue == workspace }) else {
            return .error(404, "Workspace not found")
        }
        guard owner["is_personal"]?.boolValue != true else {
            return .error(400, "Personal workspaces cannot have additional members")
        }
        let role = body["role"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? "member"
        guard role == "member" || role == "admin" else { return .error(400, "Role must be member or admin") }
        let email = body["email"]?.stringValue?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard !email.isEmpty else { return .error(400, "Email is required") }
        if members[workspace, default: []].contains(where: { $0["email"]?.stringValue == email }) {
            return .error(409, "User is already a member")
        }
        let name = email.split(separator: "@").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? email
        let row = member(name: name, email: email, userID: makeID(), role: role, workspace: workspace, age: 0)
        members[workspace, default: []].append(row)
        return .ok(.object(row), status: 201)
    }

    private func updateMember(_ id: String, _ userID: String, _ body: FixtureObject) -> FixtureReply {
        guard let workspace = Int(id), let index = members[workspace]?.firstIndex(where: { "\($0["user_id"]?.intValue ?? -1)" == userID }) else {
            return .error(404, "Member not found")
        }
        let role = body["role"]?.stringValue ?? ""
        guard role == "member" || role == "admin" else { return .error(400, "Role must be member or admin") }
        members[workspace]?[index]["role"] = .string(role)
        return .message("Role updated")
    }

    private func removeMember(_ id: String, _ userID: String) -> FixtureReply {
        guard let workspace = Int(id), let index = members[workspace]?.firstIndex(where: { "\($0["user_id"]?.intValue ?? -1)" == userID }) else {
            return .error(404, "Member not found")
        }
        members[workspace]?.remove(at: index)
        return .message("Member removed")
    }

    private func activity(limit: Int) -> FixtureReply {
        let name = user["name"]?.stringValue ?? ""
        var events: [FixtureObject] = resources.sorted(by: Self.newestFirst).map { row -> FixtureObject in
            [
                "action": "resource.created",
                "actor_user_id": .int(userID),
                "actor_name": .string(name),
                "subject_type": row["type"] ?? "link",
                "subject_id": row["id"] ?? 0,
                "link_id": row["id"] ?? 0,
                "at": row["created_at"] ?? timestamp(0),
            ]
        }
        for workspace in members.values {
            for member in workspace where member["role"]?.stringValue != "owner" {
                events.append([
                    "action": "member.joined",
                    "actor_user_id": member["user_id"] ?? 0,
                    "actor_name": member["name"] ?? "",
                    "at": member["created_at"] ?? timestamp(0),
                ])
            }
        }
        events.sort { ($0["at"]?.stringValue ?? "") > ($1["at"]?.stringValue ?? "") }
        return .ok(.array(events.prefix(min(max(limit, 1), 100)).map(JSONValue.object)))
    }

    // MARK: Statistics

    private func summary() -> FixtureReply {
        func count(_ type: String) -> Int { resources.filter { $0["type"]?.stringValue == type }.count }
        return .ok([
            "links": .int(count("link")),
            "biolinks": .int(count("biolink")),
            "qr_codes": .int(rows("qr-codes").count),
            "projects": .int(rows("projects").count),
            "domains": .int(rows("domains").count),
            "pixels": .int(rows("pixels").count),
            "total_clicks": .int(resources.reduce(0) { $0 + ($1["clicks"]?.intValue ?? 0) }),
        ])
    }

    /// `GET /statistics/{id|all}`: a deterministic daily series shaped by
    /// each resource's click count, or a breakdown by `type`. A resource
    /// with no clicks gets `null`, as the server sends.
    private func statistics(_ id: String, _ query: [String: String]) -> FixtureReply {
        let clicks: Int
        let seed: Int
        if id == "all" {
            clicks = resources.reduce(0) { $0 + ($1["clicks"]?.intValue ?? 0) }
            seed = 7
        } else {
            guard let row = resources.first(where: { "\($0["id"]?.intValue ?? -1)" == id }) else {
                return .error(404, "Link not found")
            }
            clicks = row["clicks"]?.intValue ?? 0
            seed = row["id"]?.intValue ?? 1
        }
        guard clicks > 0 else { return .ok(.null) }

        let start = query["start_date"].flatMap { CardsiteJSON.parseDay($0) } ?? now.addingTimeInterval(-29 * 86_400)
        let end = query["end_date"].flatMap { CardsiteJSON.parseDay($0) } ?? now
        let days = min(max(Int(end.timeIntervalSince(start) / 86_400) + 1, 1), 400)
        let perDay = max(Double(clicks) / 30, 1)
        var series: [FixtureObject] = []
        for offset in 0..<days {
            let day = start.addingTimeInterval(Double(offset) * 86_400)
            let index = Double(Int(day.timeIntervalSince1970 / 86_400) + seed)
            let slow: Double = 0.25 * sin(index / 3.1)
            let weekly: Double = 0.15 * sin(index * 2 * Double.pi / 7)
            let wave: Double = 0.6 + slow + weekly
            let views = max(0, Int((perDay * wave).rounded()))
            series.append([
                "date": .string(CardsiteJSON.dayString(day)),
                "pageviews": .int(views),
                "visitors": .int(Int((Double(views) * 0.72).rounded())),
            ])
        }

        let type = query["type"] ?? "overview"
        if type == "overview" { return .ok(.array(series.map(JSONValue.object))) }

        guard let labels = Self.breakdownLabels[type] else { return .ok(.null) }
        let total = series.reduce(0) { $0 + ($1["pageviews"]?.intValue ?? 0) }
        guard total > 0 else { return .ok(.null) }
        let weights = [0.36, 0.22, 0.15, 0.11, 0.08, 0.05, 0.03]
        let breakdown: [JSONValue] = zip(labels, weights).compactMap { pair -> JSONValue? in
            let (label, weight) = pair
            let views = Int((Double(total) * weight).rounded())
            return views > 0 ? ["label": .string(label), "pageviews": .int(views)] : nil
        }
        return .ok(breakdown.isEmpty ? .null : .array(breakdown))
    }

    private static let breakdownLabels: [String: [String]] = [
        "referrer": ["instagram.com", "google.com", "t.co", "linkedin.com", "news.ycombinator.com", "facebook.com", "duckduckgo.com"],
        "country_code": ["GB", "US", "DE", "FR", "CA", "NL", "AU"],
        "continent_code": ["EU", "NA", "OC", "AS", "SA", "AF"],
        "city_name": ["London", "Manchester", "New York", "Berlin", "Paris", "Toronto", "Amsterdam"],
        "device_type": ["mobile", "desktop", "tablet"],
        "os_name": ["iOS", "Android", "macOS", "Windows", "Linux"],
        "browser_name": ["Safari", "Chrome", "Firefox", "Edge", "Samsung Internet"],
        "language": ["en", "de", "fr", "es", "nl"],
        "utm_source": ["newsletter", "instagram", "podcast"],
        "utm_medium": ["email", "social", "audio"],
        "utm_campaign": ["launch", "spring", "summer"],
    ]

    private func spotlight(_ query: String) -> FixtureReply {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 2 else { return .ok(.array([])) }
        let hits: [JSONValue] = resources
            .filter { $0["is_enabled"]?.boolValue == true }
            .filter { row in
                let title = row["settings"]?["title"]?.stringValue ?? ""
                return (row["url"]?.stringValue ?? "").lowercased().contains(needle) || title.lowercased().contains(needle)
            }
            .prefix(10)
            .map { row -> JSONValue in
                let slug = row["url"] ?? ""
                return [
                    "type": row["type"]?.stringValue == "biolink" ? "biolink" : "link",
                    "id": row["id"] ?? 0,
                    "label": slug,
                    "url": slug,
                ]
            }
        return .ok(.array(hits))
    }

    // MARK: Lists

    private func list(_ all: [FixtureObject], query: [String: String]) -> FixtureReply {
        var filtered = all
        for key in ["link_id", "biolink_block_id", "project_id", "type", "kind"] {
            guard let wanted = query[key], !wanted.isEmpty else { continue }
            filtered = filtered.filter { Self.text($0[key]) == wanted }
        }
        if let search = query["search"]?.lowercased(), !search.isEmpty {
            filtered = filtered.filter { row in
                ["url", "name", "location_url", "title", "host", "original_name"].contains { key in
                    Self.text(row[key])?.lowercased().contains(search) == true
                } || Self.text(row["settings"]?["title"])?.lowercased().contains(search) == true
            }
        }
        if filtered.first?["order"] != nil {
            filtered.sort { ($0["order"]?.intValue ?? 0) < ($1["order"]?.intValue ?? 0) }
        } else {
            filtered.sort(by: Self.newestFirst)
        }
        let perPage = max(Int(query["results_per_page"] ?? query["per_page"] ?? "") ?? 25, 1)
        let page = max(Int(query["page"] ?? "") ?? 1, 1)
        let slice = filtered.dropFirst((page - 1) * perPage).prefix(perPage)
        return .page(slice.map(JSONValue.object), page: page, perPage: perPage, total: filtered.count)
    }

    private static func newestFirst(_ a: FixtureObject, _ b: FixtureObject) -> Bool {
        let left = a["created_at"]?.stringValue ?? a["datetime"]?.stringValue ?? ""
        let right = b["created_at"]?.stringValue ?? b["datetime"]?.stringValue ?? ""
        if left != right { return left > right }
        return (a["id"]?.intValue ?? a["upload_id"]?.intValue ?? 0) > (b["id"]?.intValue ?? b["upload_id"]?.intValue ?? 0)
    }

    private static func text(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let text)?: return text
        case .int(let number)?: return String(number)
        case .bool(let flag)?: return flag ? "true" : "false"
        default: return nil
        }
    }

    // MARK: Link-shaped resources

    private func resource(_ id: String, kind: String) -> FixtureObject? {
        resources.first { "\($0["id"]?.intValue ?? -1)" == id && $0["type"]?.stringValue == kind }
    }

    private func createResource(kind: String, _ body: FixtureObject) -> FixtureReply {
        let slug = body["url"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !slug.isEmpty else { return .error(400, "URL is required") }
        guard !resources.contains(where: { $0["url"]?.stringValue == slug }) else {
            return .error(409, "That address is already taken")
        }
        if kind == "payment_link" {
            let checkout = body["location_url"]?.stringValue ?? ""
            guard checkout.hasPrefix("http://") || checkout.hasPrefix("https://") else {
                return .error(422, "The checkout URL must start with http:// or https://")
            }
        }
        var row = template(for: kind)
        row["id"] = .int(makeID())
        row["url"] = .string(slug)
        row["clicks"] = 0
        row["is_enabled"] = true
        row["created_at"] = timestamp(0)
        row["updated_at"] = .null
        row["last_used_at"] = timestamp(0)
        row["lifecycle_state"] = "active"
        row["lifecycle_state_at"] = timestamp(0)
        if kind == "vcard" || kind == "event" {
            // POST takes flat `vcard_*` / `event_*` fields and files them under settings.
            var settings = (row["settings"]?.objectValue ?? [:]).mapValues { value -> JSONValue in
                value.arrayValue != nil ? .array([]) : value.boolValue != nil ? value : ""
            }
            for (key, value) in body where key.hasPrefix(kind + "_") || key == "expiration_url" || key == "sensitive_content" {
                settings[key] = value
            }
            row["settings"] = .object(settings)
        } else if kind == "file" || kind == "static" {
            var settings = row["settings"]?.objectValue ?? [:]
            if let filename = body["file.filename"] { settings["file"] = filename }
            row["settings"] = .object(settings)
        } else if kind == "link" {
            row["settings"] = .null
        }
        apply(body.filter { key, _ in !key.hasPrefix("vcard_") && !key.hasPrefix("event_") && !key.hasSuffix(".filename") && key != "url" }, to: &row)
        resources.append(row)
        return .ok(.object(row), status: 201)
    }

    private func updateResource(_ id: String, kind: String, _ body: FixtureObject, missing: String) -> FixtureReply {
        guard let index = resources.firstIndex(where: { "\($0["id"]?.intValue ?? -1)" == id && $0["type"]?.stringValue == kind }) else {
            return .error(404, missing)
        }
        if let slug = body["url"]?.stringValue, slug != resources[index]["url"]?.stringValue,
           resources.contains(where: { $0["url"]?.stringValue == slug }) {
            return .error(409, "That address is already taken")
        }
        // PUT ignores the flat `vcard_*` / `event_*` fields (quirk 8): settings replace whole.
        apply(body.filter { key, _ in !key.hasPrefix("vcard_") && !key.hasPrefix("event_") && !key.hasSuffix(".filename") }, to: &resources[index])
        if let filename = body["file.filename"] {
            var settings = resources[index]["settings"]?.objectValue ?? [:]
            settings["file"] = filename
            resources[index]["settings"] = .object(settings)
        }
        resources[index]["updated_at"] = timestamp(0)
        return .ok(.object(resources[index]))
    }

    private func duplicateLink(_ id: String) -> FixtureReply {
        guard var copy = resource(id, kind: "link") else { return .error(404, "Link not found") }
        let base = (copy["url"]?.stringValue ?? "link") + "-copy"
        var slug = base
        var counter = 2
        while resources.contains(where: { $0["url"]?.stringValue == slug }) {
            slug = "\(base)-\(counter)"
            counter += 1
        }
        copy["id"] = .int(makeID())
        copy["url"] = .string(slug)
        copy["is_enabled"] = false
        copy["clicks"] = 0
        copy["created_at"] = timestamp(0)
        copy["updated_at"] = .null
        resources.append(copy)
        return .ok(.object(copy), status: 201)
    }

    /// Merges a request body into a row the way the handlers do: `settings`
    /// replaces the whole object (keeping `password_hash` unless `password`
    /// is sent), `password` sets or clears the hash, `pixels_ids` is stored
    /// as a string holding a JSON array, and `null` removes a key.
    private func apply(_ body: FixtureObject, to row: inout FixtureObject) {
        for (key, value) in body {
            switch key {
            case "id", "upload_id", "user_id", "workspace_id", "type", "created_at", "version":
                continue
            case "settings":
                var settings = value.objectValue ?? [:]
                if settings["password_hash"] == nil, body["password"] == nil,
                   let hash = row["settings"]?["password_hash"] {
                    settings["password_hash"] = hash
                }
                row["settings"] = settings.isEmpty ? .null : .object(settings)
            case "password":
                var settings = row["settings"]?.objectValue ?? body["settings"]?.objectValue ?? [:]
                settings["password_hash"] = value.stringValue?.isEmpty == false ? "<redacted-hash>" : nil
                row["settings"] = .object(settings)
            case "pixels_ids":
                if let ids = value.arrayValue {
                    row[key] = ids.isEmpty ? nil : .string("[" + ids.compactMap { $0.intValue.map(String.init) }.joined(separator: ",") + "]")
                } else {
                    row[key] = value.isNull ? nil : value
                }
            default:
                row[key] = value.isNull ? nil : value
            }
        }
    }

    // MARK: Other collections

    private func rows(_ table: String) -> [FixtureObject] {
        tables[table] ?? []
    }

    private func create(in table: String, _ body: FixtureObject) -> FixtureReply {
        var row: FixtureObject
        switch table {
        case "qr-codes":
            let name = body["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !name.isEmpty else { return .error(400, "Name is required") }
            row = qrTemplate()
            row["project_id"] = nil
            row["link_id"] = nil
            apply(body, to: &row)
            let target = row["settings"]?["url"]?.stringValue
                ?? row["link_id"]?.intValue.flatMap { id in resources.first { $0["id"]?.intValue == id }?["url"]?.stringValue }
            row["embedded_data"] = .string(target ?? "")
            row["type"] = body["type"] ?? "url"
        case "uploads":
            guard let filename = body["file.filename"]?.stringValue else { return .error(400, "File is required") }
            row = Self.row(data("26z2-uploads-list-200"))
            let ext = (filename as NSString).pathExtension.lowercased()
            row["upload_id"] = .int(makeID())
            row["original_name"] = .string(filename)
            row["name"] = .string(filename)
            row["extension"] = .string(ext)
            row["mime_type"] = .string(ext == "pdf" ? "application/pdf" : ext == "png" ? "image/png" : ext == "jpg" || ext == "jpeg" ? "image/jpeg" : "application/octet-stream")
            row["type"] = body["type"] ?? "file"
            row["size"] = 24_576
        case "biolink-blocks":
            guard let linkID = body["link_id"]?.intValue, resource(String(linkID), kind: "biolink") != nil else {
                return .error(404, "Biolink not found")
            }
            row = Self.row(data("24g-biolink-blocks-list-200"))
            row["location_url"] = nil
            apply(body, to: &row)
            row["order"] = .int(rows(table).filter { $0["link_id"]?.intValue == linkID }.count)
            row["version"] = 1
            row["clicks"] = 0
            row["is_enabled"] = body["is_enabled"] ?? true
            row["last_editor_user_id"] = .int(userID)
        default:
            let template = ["projects": "21c-projects-list-200", "domains": "21e-domains-list-200",
                            "pixels": "21h-pixels-list-200", "splash-pages": "21j-splash-pages-list-200"][table] ?? ""
            row = Self.row(data(template))
            apply(body, to: &row)
            if table == "domains" { row["is_verified"] = false }
        }
        if table != "uploads" { row["id"] = .int(makeID()) }
        row["created_at"] = timestamp(0)
        if row["updated_at"] != nil { row["updated_at"] = .null }
        tables[table, default: []].append(row)
        return .ok(.object(row), status: 201)
    }

    private func update(in table: String, id: String, with body: FixtureObject, missing: String) -> FixtureReply {
        let idKey = table == "uploads" ? "upload_id" : "id"
        guard let index = rows(table).firstIndex(where: { "\($0[idKey]?.intValue ?? -1)" == id }) else {
            return .error(404, missing)
        }
        var row = rows(table)[index]
        apply(body, to: &row)
        if row["updated_at"] != nil { row["updated_at"] = timestamp(0) }
        tables[table]?[index] = row
        return .ok(.object(row))
    }

    private func remove(from table: String, id: String, idKey: String, message: String, missing: String) -> FixtureReply {
        guard let index = rows(table).firstIndex(where: { "\($0[idKey]?.intValue ?? -1)" == id }) else {
            return .error(404, missing)
        }
        tables[table]?.remove(at: index)
        return .message(message)
    }

    private func updateBlock(_ id: String, _ body: FixtureObject) -> FixtureReply {
        guard let index = rows("biolink-blocks").firstIndex(where: { "\($0["id"]?.intValue ?? -1)" == id }) else {
            return .error(404, "Block not found")
        }
        var block = rows("biolink-blocks")[index]
        let current = block["version"]?.intValue ?? 1
        if let sent = body["version"]?.intValue, sent != current {
            return .error(409, "\(user["name"]?.stringValue ?? "Someone") changed this block — reload it and reapply your change", extras: [
                "at": block["updated_at"] ?? timestamp(0),
                "last_editor": ["name": user["name"] ?? "", "user_id": .int(userID)],
            ])
        }
        apply(body, to: &block)
        block["version"] = .int(current + 1)
        block["updated_at"] = timestamp(0)
        block["last_editor_user_id"] = .int(userID)
        tables["biolink-blocks"]?[index] = block
        return .ok(.object(block))
    }

    private func reorderBlocks(_ body: FixtureObject) -> FixtureReply {
        let ids = body["biolink_block_ids"]?.arrayValue?.compactMap(\.intValue) ?? []
        guard !ids.isEmpty else { return .error(400, "biolink_block_ids is required") }
        tables["biolink-blocks"] = rows("biolink-blocks").map { block -> FixtureObject in
            var block = block
            if let id = block["id"]?.intValue, let position = ids.firstIndex(of: id) {
                block["order"] = .int(position)
            }
            return block
        }
        return .message("Blocks reordered")
    }

    private func generateQRCode(_ body: FixtureObject) -> FixtureReply {
        let settings = body["settings"]?.objectValue ?? [:]
        let payload = settings.values.compactMap(\.stringValue).first { !$0.isEmpty }
            ?? body["link_id"]?.intValue.flatMap { id in resources.first { $0["id"]?.intValue == id }?["url"]?.stringValue }
        guard let payload else { return .error(400, "Failed to generate QR code: no data to encode") }
        return .ok(["png": data("23b-qr-codes-generate-200")["png"] ?? "", "embedded_data": .string(payload)])
    }

    // MARK: Fixture files

    /// The `response` of `Debug/Fixtures/<name>.fixture.json`.
    private func fixture(_ name: String) -> JSONValue {
        if let cached = cache[name] { return cached }
        var value = JSONValue.null
        if let url = Bundle.main.url(forResource: name + ".fixture", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(JSONValue.self, from: data) {
            value = file["response"] ?? .null
        }
        cache[name] = value
        return value
    }

    private func data(_ name: String) -> JSONValue {
        fixture(name)["data"] ?? .null
    }

    private func passthrough(_ name: String) -> FixtureReply {
        let response = fixture(name)
        return response.isNull ? .error(500, "Missing fixture \(name)") : FixtureReply(status: 200, body: response)
    }

    /// The first row of a list, or the object itself.
    private static func row(_ value: JSONValue, _ index: Int = 0) -> FixtureObject {
        value[index]?.objectValue ?? value.objectValue ?? [:]
    }

    private func row(_ name: String, path key: String) -> FixtureObject {
        data(name)[key]?.objectValue ?? [:]
    }

    private func template(for kind: String) -> FixtureObject {
        let name: String
        switch kind {
        case "biolink": name = "24j-biolinks-list-200"
        case "vcard": name = "25d-vcards-list-200"
        case "event": name = "25h-events-list-200"
        case "payment_link": name = "25l-payment-links-list-200"
        case "file": name = "25o-files-list-200"
        case "static": name = "25q-static-list-200"
        default: name = "06c-links-get-200"
        }
        var row = Self.row(data(name))
        row["user_id"] = .int(userID)
        row["workspace_id"] = workspaces.first?["workspace_id"] ?? row["workspace_id"]
        return row
    }

    private func qrTemplate() -> FixtureObject {
        var row = Self.row(data("23d-qr-codes-create-styled-201"))
        row["user_id"] = .int(userID)
        row["workspace_id"] = workspaces.first?["workspace_id"] ?? row["workspace_id"]
        return row
    }

    private var userID: Int { user["user_id"]?.intValue ?? 4 }

    private func makeID() -> Int {
        nextID += 1
        return nextID
    }

    /// RFC 3339 with fractional seconds, `days` before launch.
    private func timestamp(_ days: Double) -> JSONValue {
        .string(now.addingTimeInterval(-days * 86_400).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    /// The local `YYYY-MM-DDTHH:mm` an event takes, `days` after launch.
    private func localDateTime(daysAhead days: Int, hour: Int) -> JSONValue {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(byAdding: .day, value: days, to: now) ?? now
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return .string(String(format: "%04d-%02d-%02dT%02d:00", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1, hour))
    }

    private func member(name: String, email: String, userID: Int, role: String, workspace: Int, age: Double) -> FixtureObject {
        var row = Self.row(data("26z7-workspaces-members-200"))
        row["workspace_id"] = .int(workspace)
        row["user_id"] = .int(userID)
        row["name"] = .string(name)
        row["email"] = .string(email)
        row["role"] = .string(role)
        row["created_at"] = timestamp(age)
        return row
    }

    // MARK: Seed

    /// One believable account: a Pro plan, a personal and a team workspace,
    /// short links with traffic (one disabled, one with every setting), bio
    /// pages with blocks, one of each other resource type, QR codes, an
    /// inbox with unread items, uploads, form data, tokens and sign-in logs.
    /// `-CardsiteFixturesEmpty` keeps only the user, plan and workspace.
    private func seed() {
        let plans = data("10b-plans-200").arrayValue ?? []
        let pro = plans.first { $0["id"]?.intValue == 3 }?.objectValue ?? [:]

        user = Self.row(data("04a-user-200"))
        user["email"] = "avery@example.com"
        user["name"] = "Avery Quinn"
        user["plan_id"] = pro["id"] ?? 3
        user["plan_settings"] = pro["settings"] ?? .null
        user["timezone"] = "Europe/London"
        user["total_logins"] = 42
        user["created_at"] = timestamp(240)
        user["last_activity"] = timestamp(0)

        plan = data("10a-account-plan-200").objectValue ?? [:]
        plan["plan_id"] = pro["id"] ?? 3
        plan["plan_settings"] = pro["settings"] ?? .null
        plan["plan_expiration_date"] = timestamp(-200)

        var personal = Self.row(data("05-workspaces-200"))
        personal["owner_user_id"] = .int(userID)
        personal["created_at"] = timestamp(240)
        personal["storage_bytes"] = 48_234_496
        workspaces = [personal]
        let personalID = personal["workspace_id"]?.intValue ?? 234
        let name = user["name"]?.stringValue ?? ""
        let email = user["email"]?.stringValue ?? ""
        members[personalID] = [member(name: name, email: email, userID: userID, role: "owner", workspace: personalID, age: 240)]

        preferences = data("26a-account-preferences-200").objectValue ?? [:]
        tokenScopes = data("26e-account-tokens-list-200")["scopes"]?.arrayValue ?? []

        guard !startsEmpty else { return }

        var team = personal
        team["workspace_id"] = 339
        team["name"] = "Northwind Studio"
        team["is_personal"] = false
        team["created_at"] = timestamp(120)
        team["storage_bytes"] = 12_582_912
        workspaces.append(team)
        members[339] = [
            member(name: name, email: email, userID: userID, role: "owner", workspace: 339, age: 120),
            member(name: "Jordan Lee", email: "jordan@example.com", userID: 41, role: "admin", workspace: 339, age: 3),
            member(name: "Sam Patel", email: "sam@example.com", userID: 42, role: "member", workspace: 339, age: 18),
        ]

        seedOrganise()
        seedResources()
        seedBlocks()
        seedQRCodes()
        seedAccountTables()
    }

    private func seedOrganise() {
        // Project colours come from the block-type palette in the fixtures,
        // so no colour literal lives in app code.
        let palette = (data("24b-biolink-blocks-types-200").arrayValue ?? []).compactMap { $0["color"]?.stringValue }
        var launch = Self.row(data("21c-projects-list-200"))
        launch["id"] = 3
        launch["user_id"] = .int(userID)
        var clients = launch
        clients["id"] = 4
        clients["name"] = "Clients"
        if palette.count > 3 { clients["color"] = .string(palette[3]) }
        clients["created_at"] = timestamp(60)
        tables["projects"] = [clients, launch]

        var domain = Self.row(data("21e-domains-list-200"))
        domain["id"] = 3
        domain["host"] = "links.northwind.example"
        domain["is_verified"] = true
        domain["ssl_is_enabled"] = true
        domain["created_at"] = timestamp(100)
        var pending = domain
        pending["id"] = 4
        pending["host"] = "go.avery.example"
        pending["is_verified"] = false
        pending["ssl_is_enabled"] = false
        pending["created_at"] = timestamp(4)
        tables["domains"] = [pending, domain]

        var pixel = Self.row(data("21h-pixels-list-200"))
        pixel["id"] = 3
        pixel["name"] = "Meta ads"
        pixel["created_at"] = timestamp(80)
        var analytics = pixel
        analytics["id"] = 4
        analytics["type"] = "google_analytics"
        analytics["name"] = "Site analytics"
        analytics["pixel"] = "G-FIXTURE01"
        analytics["created_at"] = timestamp(40)
        tables["pixels"] = [analytics, pixel]

        var splash = Self.row(data("21j-splash-pages-list-200"))
        splash["id"] = 3
        splash["name"] = "Launch countdown"
        splash["created_at"] = timestamp(70)
        tables["splash-pages"] = [splash]
    }

    private func seedResources() {
        struct Seed {
            var kind: String
            var slug: String
            var age: Double
            var clicks: Int
            var enabled = true
            var destination: String?
            var settings: FixtureObject?
        }
        let seeds: [Seed] = [
            Seed(kind: "link", slug: "launch", age: 1, clicks: 932, destination: "https://example.com/blog/introducing-northwind"),
            Seed(kind: "link", slug: "spring-menu", age: 2, clicks: 1284, destination: "https://example.com/menu/spring"),
            Seed(kind: "biolink", slug: "avery", age: 3, clicks: 2210,
                 settings: ["title": "Avery Quinn", "description": "Designer and maker in Manchester."]),
            Seed(kind: "link", slug: "portfolio", age: 9, clicks: 402, destination: "https://example.com/work"),
            Seed(kind: "event", slug: "open-evening", age: 11, clicks: 64),
            Seed(kind: "link", slug: "podcast-ep-42", age: 14, clicks: 218, destination: "https://podcasts.example.com/episodes/42"),
            Seed(kind: "vcard", slug: "avery-card", age: 20, clicks: 133),
            Seed(kind: "biolink", slug: "northwind", age: 25, clicks: 640,
                 settings: ["title": "Northwind Studio", "description": "Brand and web for independents."]),
            Seed(kind: "link", slug: "summer-sale", age: 30, clicks: 0, enabled: false, destination: "https://shop.example.com/sale"),
            Seed(kind: "payment_link", slug: "tips", age: 35, clicks: 19, destination: "https://buy.example.com/checkout/tip-jar"),
            Seed(kind: "link", slug: "newsletter", age: 45, clicks: 77, destination: "https://example.com/subscribe"),
            Seed(kind: "file", slug: "media-kit", age: 50, clicks: 28),
            Seed(kind: "link", slug: "booking", age: 60, clicks: 51, destination: "https://cal.example.com/avery"),
            Seed(kind: "static", slug: "launch-page", age: 70, clicks: 9),
            Seed(kind: "biolink", slug: "workshops", age: 80, clicks: 96,
                 settings: ["title": "Workshops", "description": "Upcoming classes and talks."]),
            Seed(kind: "link", slug: "press-kit", age: 90, clicks: 12, destination: "https://example.com/press"),
        ]

        var nextResourceID = 20
        for seed in seeds.sorted(by: { $0.age > $1.age }) {
            var row = seed.slug == "launch" ? Self.row(data("22b-links-get-full-200")) : template(for: seed.kind)
            nextResourceID += 1
            row["id"] = .int(nextResourceID)
            row["user_id"] = .int(userID)
            row["url"] = .string(seed.slug)
            row["clicks"] = .int(seed.clicks)
            row["is_enabled"] = .bool(seed.enabled)
            row["created_at"] = timestamp(seed.age)
            row["updated_at"] = seed.age > 40 ? .null : timestamp(seed.age / 2)
            row["last_used_at"] = timestamp(min(seed.age, seed.clicks > 0 ? 0.2 : seed.age))
            row["lifecycle_state"] = "active"
            row["lifecycle_state_at"] = timestamp(seed.age)
            if let destination = seed.destination { row["location_url"] = .string(destination) }
            if let settings = seed.settings { row["settings"] = .object(settings) }

            switch seed.kind {
            case "link" where seed.slug == "launch":
                // The full fixture link: project, domain, splash page, pixel,
                // targeting, password, UTM, cloaking. Its schedule is dropped
                // so it shows as live.
                row["scheduled_at"] = nil
                row["scheduled_end"] = nil
                var settings = row["settings"]?.objectValue ?? [:]
                settings["clicks_limit"] = 5000
                settings["cloaking_title"] = "Introducing Northwind"
                row["settings"] = .object(settings)
            case "link":
                row["settings"] = .null
            case "vcard":
                var settings = row["settings"]?.objectValue ?? [:]
                settings["vcard_first_name"] = "Avery"
                settings["vcard_last_name"] = "Quinn"
                settings["vcard_company"] = "Northwind Studio"
                settings["vcard_job_title"] = "Founder"
                settings["vcard_email"] = "avery@example.com"
                settings["vcard_city"] = "Manchester"
                row["settings"] = .object(settings)
            case "event":
                var settings = row["settings"]?.objectValue ?? [:]
                settings["event_name"] = "Studio open evening"
                settings["event_note"] = "Drinks, prints and a short talk."
                settings["event_start_datetime"] = localDateTime(daysAhead: 21, hour: 18)
                settings["event_end_datetime"] = localDateTime(daysAhead: 21, hour: 21)
                row["settings"] = .object(settings)
            case "file":
                var settings = row["settings"]?.objectValue ?? [:]
                settings["file"] = "media-kit.pdf"
                row["settings"] = .object(settings)
            default:
                break
            }
            resources.append(row)
        }
    }

    private func seedBlocks() {
        let template = data("24g-biolink-blocks-list-200").arrayValue?.compactMap(\.objectValue) ?? []
        let copy: [String: (heading: String, link: String, url: String, collector: String)] = [
            "avery": ("Hi, I'm Avery", "See my work", "https://example.com/work", "Join the newsletter"),
            "northwind": ("Northwind Studio", "Start a project", "https://example.com/contact", "Get our notes"),
            "workshops": ("Upcoming workshops", "Book a seat", "https://cal.example.com/workshops", "Join the waitlist"),
        ]
        var blocks: [FixtureObject] = []
        var blockID = 100
        for page in resources where page["type"]?.stringValue == "biolink" {
            guard let slug = page["url"]?.stringValue, let words = copy[slug] else { continue }
            for (order, original) in template.enumerated() {
                var block = original
                blockID += 1
                block["id"] = .int(blockID)
                block["link_id"] = page["id"] ?? 0
                block["user_id"] = .int(userID)
                block["order"] = .int(order)
                block["clicks"] = .int(block["type"]?.stringValue == "link" ? (page["clicks"]?.intValue ?? 0) / 3 : 0)
                var settings = block["settings"]?.objectValue ?? [:]
                switch block["type"]?.stringValue {
                case "heading": settings["heading"] = .string(words.heading)
                case "link":
                    settings["name"] = .string(words.link)
                    block["location_url"] = .string(words.url)
                default: settings["name"] = .string(words.collector)
                }
                block["settings"] = .object(settings)
                blocks.append(block)
            }
        }
        tables["biolink-blocks"] = blocks

        // Form submissions to the first page's email collector.
        if let collector = blocks.first(where: { $0["type"]?.stringValue == "email_collector" }) {
            let entries = [("Grace", "grace@example.com", 2.0), ("Lin", "lin@example.com", 5.0), ("Sam", "sam@example.org", 9.0)]
            var dataID = 10
            tables["data"] = entries.map { entry -> FixtureObject in
                let (name, email, age) = entry
                var row = Self.row(data("26z4-data-list-200"))
                dataID += 1
                row["id"] = .int(dataID)
                row["user_id"] = .int(userID)
                row["link_id"] = collector["link_id"] ?? 0
                row["biolink_block_id"] = collector["id"] ?? 0
                row["data"] = ["name": .string(name), "email": .string(email)]
                row["datetime"] = timestamp(age)
                return row
            }
        }
    }

    private func seedQRCodes() {
        func link(_ slug: String) -> FixtureObject? { resources.first { $0["url"]?.stringValue == slug } }
        let codes: [(name: String, slug: String, age: Double, project: Int?)] = [
            ("Spring menu table card", "spring-menu", 2, 3),
            ("Shop window", "portfolio", 8, nil),
            ("Open evening flyer", "open-evening", 11, 4),
            ("Business card", "avery-card", 20, nil),
        ]
        var qrID = 50
        tables["qr-codes"] = codes.map { code -> FixtureObject in
            var row = qrTemplate()
            qrID += 1
            row["id"] = .int(qrID)
            row["name"] = .string(code.name)
            let address = "https://card.site/\(code.slug)"
            var settings = row["settings"]?.objectValue ?? [:]
            settings["url"] = .string(address)
            row["settings"] = .object(settings)
            row["embedded_data"] = .string(address)
            row["link_id"] = link(code.slug)?["type"]?.stringValue == "link" ? link(code.slug)?["id"] : nil
            row["project_id"] = code.project.map(JSONValue.int)
            row["created_at"] = timestamp(code.age)
            row["updated_at"] = .null
            return row
        }
    }

    private func seedAccountTables() {
        var welcome = Self.row(data("26t-internal-notifications-list-200"))
        welcome["id"] = 1
        welcome["user_id"] = .int(userID)
        welcome["is_read"] = true
        welcome["datetime"] = timestamp(240)
        var joined = welcome
        joined["id"] = 2
        joined["title"] = "Jordan Lee joined Northwind Studio"
        joined["description"] = "They can now edit the team's links and pages."
        joined["url"] = "/workspace"
        joined["is_read"] = false
        joined["datetime"] = timestamp(3)
        var milestone = welcome
        milestone["id"] = 3
        milestone["title"] = "spring-menu passed 1,000 clicks"
        milestone["description"] = "Your short link is having a great week."
        milestone["url"] = "/links"
        milestone["is_read"] = false
        milestone["datetime"] = timestamp(1)
        tables["internal-notifications"] = [milestone, joined, welcome]

        let logTemplate = Self.row(data("26y-logs-200"), 3)
        let signIns: [(device: String, os: String, browser: String, age: Double)] = [
            ("mobile", "iOS", "Safari", 0.1), ("desktop", "macOS", "Safari", 1.2),
            ("desktop", "macOS", "Chrome", 3.5), ("tablet", "iPadOS", "Safari", 6),
            ("mobile", "iOS", "Safari", 9),
        ]
        var logID = 0
        tables["logs"] = signIns.map { entry -> FixtureObject in
            var row = logTemplate
            logID += 1
            row["id"] = .int(logID)
            row["user_id"] = .int(userID)
            row["type"] = "login"
            row["ip"] = "203.0.113.24"
            row["device_type"] = .string(entry.device)
            row["os_name"] = .string(entry.os)
            row["browser_name"] = .string(entry.browser)
            row["datetime"] = timestamp(entry.age)
            return row
        }

        // Image uploads point at the QR fixture's data URL, which
        // URLSession (and so AsyncImage) loads without a network.
        let image = data("23b-qr-codes-generate-200")["png"] ?? ""
        let files: [(name: String, mime: String, type: String, size: Int, age: Double)] = [
            ("hero.png", "image/png", "image", 182_311, 2), ("logo.png", "image/png", "logo", 12_044, 12),
            ("media-kit.pdf", "application/pdf", "file", 1_482_100, 50),
        ]
        var uploadID = 0
        tables["uploads"] = files.map { file -> FixtureObject in
            var row = Self.row(data("26z2-uploads-list-200"))
            uploadID += 1
            row["upload_id"] = .int(uploadID)
            row["user_id"] = .int(userID)
            row["name"] = .string(file.name)
            row["original_name"] = .string(file.name)
            row["extension"] = .string((file.name as NSString).pathExtension)
            row["mime_type"] = .string(file.mime)
            row["type"] = .string(file.type)
            row["size"] = .int(file.size)
            row["url"] = file.mime.hasPrefix("image/") ? image : .string("https://example.com/uploads/\(file.name)")
            row["created_at"] = timestamp(file.age)
            return row
        }

        var shortcuts = data("26e-account-tokens-list-200")["tokens"]?[0]?.objectValue ?? [:]
        shortcuts["user_id"] = .int(userID)
        shortcuts["created_at"] = timestamp(30)
        shortcuts["last_used_at"] = timestamp(1)
        var zapier = shortcuts
        zapier["id"] = 4
        zapier["name"] = "Zapier"
        zapier["scopes"] = ["links:read", "qr:read"]
        zapier["created_at"] = timestamp(12)
        zapier["last_used_at"] = .null
        tables["tokens"] = [zapier, shortcuts]
    }
}
#endif
