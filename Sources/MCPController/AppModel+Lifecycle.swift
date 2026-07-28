import Foundation

extension AppModel {
    func shutdownForApplicationQuit() {
        stopAll()
        stopTailscaleFunnel()
    }
}
