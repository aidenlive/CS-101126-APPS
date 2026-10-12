import SwiftUI
import StudioKit
import CardsiteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/*
 The share extension's principal class (NSExtensionPrincipalClass in
 Info.plist names it through @objc). It hosts `ShareView` and connects
 the model to the extension context: complete, cancel and open the app.
 */

#if os(iOS)
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let model = ShareModel(session: SharedSession.current?.snapshot())

    override func viewDidLoad() {
        super.viewDidLoad()
        StudioFonts.register()
        connect()

        let host = UIHostingController(rootView: ShareView(model: model).tint(Color.studioAccentLine))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await model.start(with: items) }
    }

    private func connect() {
        model.onComplete = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        model.onCancel = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
        // iOS lets only some extension points open their app; a share
        // extension usually gets `false`, and the view then says how to
        // open Cardsite instead.
        model.openURL = { [weak self] url in
            guard let context = self?.extensionContext else { return false }
            return await withCheckedContinuation { continuation in
                context.open(url) { opened in continuation.resume(returning: opened) }
            }
        }
    }
}

#elseif os(macOS)
@objc(ShareViewController)
final class ShareViewController: NSViewController {
    private let model = ShareModel(session: SharedSession.current?.snapshot())

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        StudioFonts.register()
        connect()

        let container = NSView()
        let host = NSHostingController(rootView: ShareView(model: model).tint(Color.studioAccentLine))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
        // The share popover's size: wide enough for an address, tall
        // enough for the form without scrolling.
        preferredContentSize = NSSize(width: 440, height: 380)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await model.start(with: items) }
    }

    private func connect() {
        model.onComplete = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        model.onCancel = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
        model.openURL = { url in
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
