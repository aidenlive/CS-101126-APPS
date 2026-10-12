import Foundation

// QR code builder endpoints. The list, the URL-only create and delete stay
// in APIClient.swift (`qrCodes(page:)`, `createQRCode(name:url:linkID:)`,
// `deleteQRCode(id:)`).
//
// Server: apps/api/internal/handlers/qr_codes.go. Fixtures 23a–23e.
extension APIClient {

    /// `GET /qr-codes/types`: the 28 types, in the server's order.
    public func qrCodeTypes() async throws -> [QRCodeTypeInfo] {
        let list: [QRCodeTypeInfo]? = try await sendOptional(.get, "api/v1/qr-codes/types")
        return list ?? []
    }

    /// `GET /qr-codes/{id}`, with the full settings for editing.
    public func qrCodeDesign(id: Int) async throws -> QRCodeDesign {
        try await send(.get, "api/v1/qr-codes/\(id)")
    }

    /// `POST /qr-codes`. A missing name is a 400; content the generator
    /// can't encode is a 400 "Failed to generate QR code: …".
    public func createQRCode(payload: QRCodePayload) async throws -> QRCodeDesign {
        try await send(.post, "api/v1/qr-codes", body: payload)
    }

    /// `PUT /qr-codes/{id}`. The server regenerates the image only when
    /// something that affects it changed. See ``QRCodePayload`` for the
    /// merge rules.
    public func updateQRCode(id: Int, payload: QRCodePayload) async throws -> QRCodeDesign {
        try await send(.put, "api/v1/qr-codes/\(id)", body: payload)
    }

    /// `POST /qr-codes/generate`: renders without storing. The name is not
    /// required. Nothing to encode → 400 ``APIError/invalid(_:)``.
    public func previewQRCode(_ payload: QRCodePayload) async throws -> QRCodePreview {
        try await send(.post, "api/v1/qr-codes/generate", body: payload)
    }
}
