import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return true
    }
    
    // MARK: - UISceneSession Lifecycle
    
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config: UISceneConfiguration = .init(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        
        guard connectingSceneSession.role == UISceneSession.Role.windowApplication
        else { return config }
        
        config.delegateClass = SceneDelegate.self
        return config
    }
}
