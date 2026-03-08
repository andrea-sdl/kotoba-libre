import Foundation

public enum AppResources {
    public static var iconPNGURL: URL? {
        Bundle.module.url(forResource: "AppIcon", withExtension: "png")
    }

    public static var iconICNSURL: URL? {
        Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
    }
}
