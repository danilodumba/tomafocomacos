import Foundation
import TomafocoDomain

#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers

/// Seletor de aplicativos via `NSOpenPanel`, ancorado em `/Applications` (T-20, RF-03.2).
///
/// A apresentação do painel (AppKit, main thread) fica isolada em `presentPanel`;
/// a conversão URL → `BlockedApp` é estática e pura, testada contra bundles temporários.
public final class NSOpenPanelApplicationPicker: ApplicationPicking {

    private let defaultDirectory: URL

    public init(defaultDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)) {
        self.defaultDirectory = defaultDirectory
    }

    public func pickApplications() async -> ApplicationPickResult {
        let urls = await MainActor.run { self.presentPanel() }
        return Self.makeResult(from: urls)
    }

    public func applications(at urls: [URL]) -> ApplicationPickResult {
        Self.makeResult(from: urls)
    }

    @MainActor
    private func presentPanel() -> [URL] {
        let panel = NSOpenPanel()
        panel.directoryURL = defaultDirectory
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        // Sem isso o painel entraria no .app como se fosse pasta.
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Adicionar"
        panel.message = "Escolha os aplicativos a bloquear durante o foco."
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    /// Lê bundle ID e nome de exibição de cada `.app` selecionado.
    /// O que não tiver bundle ID legível volta em `unreadableNames` — nunca é descartado em silêncio.
    static func makeResult(from urls: [URL]) -> ApplicationPickResult {
        var apps: [BlockedApp] = []
        var unreadable: [String] = []

        for url in urls {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier,
                  !bundleID.isEmpty else {
                unreadable.append(fallbackName(for: url))
                continue
            }
            apps.append(BlockedApp(bundleID: bundleID, displayName: displayName(for: url, bundle: bundle)))
        }
        return ApplicationPickResult(apps: apps, unreadableNames: unreadable)
    }

    static func displayName(for url: URL, bundle: Bundle) -> String {
        let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = info?[key] as? String, !name.isEmpty { return name }
        }
        return fallbackName(for: url)
    }

    /// Nome do arquivo sem a extensão `.app`.
    static func fallbackName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}
#endif
