import SwiftUI

@main
struct AudiumApp: App {
    @StateObject private var beaconManager = BeaconManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(beaconManager)
        }
    }
}
