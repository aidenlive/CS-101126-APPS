import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import StudioKit
import CardsiteKit

/// The address rows every link-backed editor shows, through the shared
/// `AddressField`.
///
/// Creating: slug, a domain picker (verified domains only) and Shuffle.
/// Editing: the slug only, on the domain it was created with, because the
/// vCard, file and static update handlers ignore `domain_id` and the event
/// and payment ones can't move an address back to the default host.
struct ResourceAddressRows: View {
    @Environment(AppModel.self) private var app
    let kind: ResourceKind
    @Binding var address: AddressForm
    let list: ResourceListModel
    let isNew: Bool
    let savedAddress: AddressForm
    let error: String?
    let prompt: String

    var body: some View {
        if isNew {
            AddressField(
                slug: $address.slug,
                domainID: $address.domainID,
                domains: list.options.usableDomains(keeping: address.domainID),
                defaultHost: app.addresses.publicHost,
                label: kind.addressLabel,
                help: kind.addressHelp,
                prompt: prompt,
                error: error,
                isSaved: false
            )
            Button {
                address.slug = Slug.random()
            } label: {
                Label("Shuffle Address", systemImage: "shuffle")
            }
            .accessibilityHint(Text("Generates a new random address"))
        } else {
            AddressField(
                slug: $address.slug,
                domainID: .constant(savedAddress.domainID),
                domains: [],
                defaultHost: list.host(for: savedAddress.domainID, defaultHost: app.addresses.publicHost),
                label: kind.addressLabel,
                help: kind.addressHelp,
                prompt: prompt,
                error: error,
                isSaved: address.slug == savedAddress.slug
            )
        }
    }
}

/// The address section's footer: why the domain list is empty, or why the
/// domain can't change.
struct ResourceAddressFooter: View {
    let list: ResourceListModel
    let isNew: Bool

    var body: some View {
        Group {
            if isNew, list.options.pickersFailed {
                Text("Domains couldn’t be loaded, so the address uses the default domain.")
            } else if isNew, list.options.usableDomains().isEmpty {
                Text("Verified custom domains appear here as address options.")
            } else if !isNew {
                Text("The domain is chosen when this is created. The address can change; links already shared to the old one stop working.")
            }
        }
        .studioText(.uiSm)
        .foregroundStyle(Color.studioText3)
    }
}

/// Choose a file from Files or Photos, show what is chosen, and say what
/// the server takes. Used by file links (any allowed type) and static pages
/// (HTML or ZIP, no Photos).
struct ResourceFileRows: View {
    @Binding var picked: PickedFile?
    /// The stored file's name when editing, shown until a new one is picked.
    let currentName: String?
    let allowedTypes: [UTType]
    let allowedMIMETypes: Set<String>
    let accepts: String
    let allowsPhotos: Bool
    let error: String?

    @State private var isImporting = false
    @State private var isPickingPhoto = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var isReading = false
    @State private var pickError: String? = nil

    var body: some View {
        LabeledContent {
            if isReading {
                ProgressView()
                    .accessibilityLabel(Text("Reading file"))
            } else if picked != nil {
                Button {
                    picked = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.studioText3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(currentName == nil ? Text("Remove the chosen file") : Text("Keep the current file"))
            }
        } label: {
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(fileLabel)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText2)
                if let picked {
                    Text(verbatim: picked.filename)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(verbatim: picked.size.formatted(.byteCount(style: .file)))
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .monospacedDigit()
                } else if let currentName, !currentName.isEmpty {
                    Text(verbatim: currentName)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else {
                    Text("None chosen")
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText3)
                }
            }
            .accessibilityElement(children: .combine)
        }

        Button {
            isImporting = true
        } label: {
            Label(picked == nil && currentName == nil ? String(localized: "Choose File…") : String(localized: "Replace with a File…"),
                  systemImage: "folder")
        }
        .disabled(isReading)

        if allowsPhotos {
            Button {
                isPickingPhoto = true
            } label: {
                Label(String(localized: "Choose from Photos…"), systemImage: "photo.on.rectangle")
            }
            .disabled(isReading)
        }

        EditorFieldFootnote(help: accepts, error: pickError ?? error)
            .fileImporter(isPresented: $isImporting, allowedContentTypes: allowedTypes) { result in
                switch result {
                case .success(let url): read(url)
                case .failure(let failure): pickError = failure.localizedDescription
                }
            }
            .photosPicker(isPresented: $isPickingPhoto, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task { await readPhoto(item) }
            }
    }

    private var fileLabel: String {
        if picked != nil { return String(localized: "New file") }
        return currentName == nil ? String(localized: "File") : String(localized: "Current file")
    }

    private func read(_ url: URL) {
        pickError = nil
        do {
            picked = try PickedFile.fromFile(at: url, allowed: allowedMIMETypes, allowedDescription: accepts)
        } catch {
            pickError = error.localizedDescription
        }
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        pickError = nil
        isReading = true
        defer { isReading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                pickError = PickedFile.Problem.unreadable.localizedDescription
                return
            }
            let type = item.supportedContentTypes.first { UploadRules.imageMIMETypes.contains(PickedFile.mimeType(for: $0)) }
                ?? item.supportedContentTypes.first
            picked = try PickedFile.fromPhoto(data: data, contentType: type, allowedDescription: accepts)
        } catch {
            pickError = error.localizedDescription
        }
    }
}

/// A plain statement inside a form, with an icon: what Cardsite does and
/// doesn't do with this resource.
struct ResourceNote: View {
    let systemImage: String
    let message: String

    var body: some View {
        Label {
            Text(message)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.studioInfo)
        }
        .accessibilityElement(children: .combine)
    }
}
