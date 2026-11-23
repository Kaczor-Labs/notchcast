// Container paths draw on Dragos Tugui's Peel, SpaceReport.swift @ 20230794 (GPL-3.0).
// Cache paths draw on tw93 and Mole contributors, lib/clean/user.sh @ f3804188 (GPL-3.0).
import Foundation

extension CleanerScanner {
    func additionalAreas(home: URL) throws -> (areas: [CleanerArea], blocked: [CleanerItem]) {
        var areas = CleanerBrowserVersions.areas(home: home)
        var blocked: [CleanerItem] = []

        for (folder, suffixes) in [
            ("Containers", [("Data/Library/Logs", CleanerArea.Kind.logs), ("Data/Library/Caches", .containerCaches),
                            ("Data/tmp", .containerCaches)]),
            ("Group Containers", [("Library/Caches", .containerCaches)])
        ] {
            let root = home.appending(path: "Library/\(folder)")
            let base = CleanerArea(home: home, kind: .containerCaches, root: root)
            for name in try discoveryNames(in: base, blocked: &blocked)
                where !name.hasPrefix(".") && !CleanerProtectedPaths.isAppleCache(name)
            {
                let container = try child(name, of: root)
                for (suffix, kind) in suffixes {
                    let logRoot = container.appending(path: suffix)
                    areas.append(.init(home: home, kind: kind, root: logRoot, owner: name))
                    if kind == .logs {
                        areas.append(.init(home: home, kind: kind, root: logRoot.appending(path: "DiagnosticReports"),
                                           owner: name, filesOnly: true))
                    }
                }
            }
        }

        let library = home.appending(path: "Library")
        for (path, owner) in Self.browserDiskCaches {
            areas.append(.init(home: home, kind: .browserCaches, root: library.appending(path: "Caches/" + path),
                               owner: owner))
        }
        for (path, owner, profileCaches, sharedCaches) in Self.browserSupportCaches {
            let root = library.appending(path: path)
            for leaf in sharedCaches {
                areas.append(.init(home: home, kind: .browserCaches, root: root.appending(path: leaf), owner: owner))
            }
            guard !profileCaches.isEmpty else { continue }
            let profiles = CleanerArea(home: home, kind: .browserCaches, root: root, owner: owner)
            for name in try discoveryNames(in: profiles, blocked: &blocked) where !name.hasPrefix(".") {
                try Task.checkCancellation()
                let profile = try child(name, of: root)
                guard let facts = try? fileSystem.inspect(profile).facts, facts.isDirectory, !facts.isSymbolicLink
                else { continue }
                for leaf in profileCaches {
                    areas.append(.init(home: home, kind: .browserCaches, root: profile.appending(path: leaf),
                                       owner: owner))
                }
            }
        }
        return (areas, blocked)
    }

    private func discoveryNames(in area: CleanerArea, blocked: inout [CleanerItem]) throws -> [String] {
        do {
            _ = try directoryIdentities(to: area.root)
            return try fileSystem.children(of: area.root, limit: Self.maxEntries).sorted()
        } catch CleanerFileError.missing {
            return []
        } catch CleanerFileError.unreadable {
            blocked.append(.init(id: area.root, area: area, size: nil, standing: .locked(.unreadable)))
            return []
        } catch let reason as CleanerHoldBack {
            blocked.append(.init(id: area.root, area: area, size: nil, standing: .locked(reason)))
            return []
        }
    }

    static let browserCacheParents: Set<String> = {
        let profiled = browserSupportCaches.compactMap { path, _, _, _ in
            path.hasPrefix("Caches/") ? String(path.dropFirst("Caches/".count)) : nil
        }
        return Set((browserDiskCaches.map { $0.0 } + profiled).compactMap {
            $0.split(separator: "/").first?.lowercased()
        })
    }()

    private static let browserDiskCaches: [(String, String)] = [
        ("com.apple.Safari", "com.apple.Safari"),
        ("Google/Chrome", "Google Chrome"), ("Chromium", "Chromium"),
        ("com.microsoft.edgemac", "Microsoft Edge"), ("company.thebrowser.Browser", "Arc"),
        ("company.thebrowser.dia", "Dia"),
        ("BraveSoftware/Brave-Browser", "Brave Browser"), ("net.imput.helium", "Helium"),
        ("Yandex/YandexBrowser", "Yandex"), ("Firefox", "Firefox"),
        ("com.operasoftware.Opera", "Opera"), ("com.vivaldi.Vivaldi", "Vivaldi"),
        ("Comet", "Comet"), ("com.kagi.kagimacOS", "Orion"), ("zen", "Zen"),
        ("com.tencent.QQBrowser3", "QQBrowser3")
    ]

    private static let chromiumProfileCaches = [
        "Application Cache", "Code Cache", "GPUCache", "DawnCache", "GrShaderCache", "GraphiteDawnCache"
    ]
    private static let chromiumSharedCaches = [
        "ShaderCache", "GrShaderCache", "GraphiteDawnCache", "Crashpad/completed", "component_crx_cache"
    ]
    private static let browserSupportCaches: [(String, String, [String], [String])] = [
        ("Caches/Dia/User Data", "Dia", ["Cache", "Code Cache"], []),
        ("Caches/BrowserOS", "BrowserOS", ["Cache", "Code Cache"], []),
        ("Application Support/Google/Chrome", "Google Chrome", chromiumProfileCaches, chromiumSharedCaches + [
            "OptGuideOnDeviceModel", "OptGuideOnDeviceClassifierModel", "optimization_guide_model_store"
        ]),
        ("Application Support/BraveSoftware/Brave-Browser", "Brave Browser", chromiumProfileCaches, chromiumSharedCaches),
        ("Application Support/Arc", "Arc", chromiumProfileCaches, chromiumSharedCaches),
        ("Application Support/Arc/User Data", "Arc", chromiumProfileCaches, chromiumSharedCaches + ["extensions_crx_cache"]),
        ("Application Support/Dia/User Data", "Dia", ["DawnGraphiteCache", "DawnWebGPUCache", "GPUCache"],
         ["GraphiteDawnCache", "GPUPersistentCache", "component_crx_cache", "extensions_crx_cache"]),
        ("Application Support/Vivaldi", "Vivaldi", chromiumProfileCaches, chromiumSharedCaches),
        ("Application Support/QQBrowser3", "QQBrowser3", ["Code Cache", "GPUCache"], chromiumSharedCaches),
        ("Application Support/net.imput.helium", "Helium", ["GPUCache", "Application Cache"],
         chromiumSharedCaches + ["extensions_crx_cache"]),
        ("Application Support/Yandex/YandexBrowser", "Yandex", ["GPUCache"],
         ["ShaderCache", "GrShaderCache", "GraphiteDawnCache"]),
        ("Application Support/BrowserOS", "BrowserOS", ["GPUCache", "DawnGraphiteCache", "DawnWebGPUCache"],
         chromiumSharedCaches + ["GPUPersistentCache"]),
        ("Application Support/Firefox/Profiles", "Firefox", ["cache2"], []),
        ("Application Support/Google/GoogleUpdater", "Google Chrome", [], ["crx_cache"])
    ]
}
