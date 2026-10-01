import Foundation

enum AppResources {
    static let bundle: Bundle = {
        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("LingGanGu_LingGanGuApp.bundle"),
           let installedBundle = Bundle(url: resourceURL) {
            return installedBundle
        }
        return Bundle.module
    }()
}
