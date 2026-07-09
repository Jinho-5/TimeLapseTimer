import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    // CameraViewModel이 녹화 시작/종료 시 이 값을 변경
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

@main
struct TimeLapseTimerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainCameraView()
        }
    }
}
