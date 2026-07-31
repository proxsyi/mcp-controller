import Foundation

extension AppModel {
    func shutdownForApplicationQuit() {
        stopImmediatelyForApplicationQuit()
        stopTailscaleFunnel()
    }
}
