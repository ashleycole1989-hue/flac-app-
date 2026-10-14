import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var root: RootViewController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let store = LibraryStore()
        let scanner = LibraryScanner(store: store)
        let engine = PlaybackEngine(store: store)
        let root = RootViewController(scanner: scanner, engine: engine)
        self.root = root

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = Theme.background
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = root
        window.makeKeyAndVisible()
        self.window = window

        if !connectionOptions.urlContexts.isEmpty {
            root.importExternal(connectionOptions.urlContexts.map(\.url))
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        root?.importExternal(URLContexts.map(\.url))
    }
}
