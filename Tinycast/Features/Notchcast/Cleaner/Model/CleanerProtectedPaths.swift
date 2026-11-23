// Adapted from Dragos Tugui's Peel, ProtectedData.swift and SystemFolders.swift @ 20230794 (GPL-3.0).
// The Apple cache names also draw on RemoveMacAI, Storage.swift @ 12cef18 (MIT).
// E5RT safety rule from tw93 and Mole contributors, lib/core/app_protection.sh @ f3804188 (GPL-3.0).
import Foundation

enum CleanerProtectedPaths {
    private static let appleCaches: Set<String> = [
        "amsdatamigratortool", "amsengagementd", "amsondevicestoraged", "animoji", "apple",
        "askpermissiond", "assessmentagent", "audiocomponentregistrar", "audioconverterservice",
        "betaenrollmentagent", "cleanup at startup", "cloudkit", "colorsync", "commcenter", "commerce",
        "configuration", "containermanagerd", "contentlinkingd", "contextstoreagent", "corespeech",
        "crashhandlerservice", "crashreporter", "csexattrcryptoservice", "desktop pictures",
        "destinationd", "diagnosticextensionsd", "duetexpertd", "energykit", "familycircle",
        "familycircled", "finance", "gamed", "gamekit", "gamestorekit", "geoservices", "heard", "homed",
        "homekit", "icdd", "icloudmailagent", "itunescloudd", "jetpackcache", "knowledge-agent",
        "locationd", "maps", "mapspushd", "mbuseragent", "mediaanalysisd-access", "metal", "metrickitd",
        "metrics", "mobileactivation", "mobileactivationd", "mobileassetd", "mobiletimerd", "nbagent",
        "ondemandresources", "ondevicestorage", "passkit", "proactived", "protectedcloudstorage",
        "ptpcamerad", "rtcreportingd", "sandboxhelper", "screentimeagent", "siritts", "speechsynthesis",
        "sportsd", "ssu", "statuskitagent", "storeaccountd", "storeassetd", "storedownloadd",
        "storelegacy", "storeuid", "studentd", "submitdiaginfo", "talagent", "ttsresourcecache.plist",
        "voicetrigger", "watchlistd"
    ]

    private static let protectedNames: Set<String> = [
        "localhistory", "location_data", "clipboard", "documents", "keychains", "wallets", "wallet.dat", "keystore",
        "local extension settings", "com.apple.e5rt.e5bundlecache",
        ".ssh", ".gnupg", ".aws", ".password-store", ".git-credentials", "debug.keystore",
        "settings-security.xml", "gradle.properties"
    ]

    private static let protectedExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "aplibrary", "musiclibrary", "tvlibrary", "imovielibrary", "migratedphotolibrary",
        "fcpbundle", "keychain", "keychain-db", "kdbx"
    ]

    static func isAppleCache(_ name: String) -> Bool {
        let folded = CleanerPolicy.groupOwner(name).lowercased()
        return folded.hasPrefix("com.apple.") || appleCaches.contains(folded)
            || (folded.hasPrefix("aaprofilepicture_") && folded.hasSuffix(".png"))
    }

    static func isProtected(_ url: URL) -> Bool {
        protectedNames.contains(url.lastPathComponent.lowercased())
            || protectedExtensions.contains(url.pathExtension.lowercased())
    }
}
