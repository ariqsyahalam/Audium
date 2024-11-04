import SwiftUI

struct ContentView: View {
    @EnvironmentObject var beaconManager: BeaconManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Audium - Museum Audio Guide")
                    .font(.largeTitle)
                    .padding()
                
                if beaconManager.isSessionActive {
                    Button(action: {
                        beaconManager.stopSession()
                    }) {
                        Text("Stop Session")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                } else {
                    Button(action: {
                        beaconManager.startSession()
                    }) {
                        Text("Start Session")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                
                if let audio = beaconManager.currentAudio {
                    VStack {
                        Text("Now Playing:")
                            .font(.headline)
                        Text(audio)
                            .font(.subheadline)
                    }
                } else {
                    Text("No audio playing.")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                
                if let note = beaconManager.audioNote {
                    Text(note)
                        .font(.footnote)
                        .padding()
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                
                List(beaconManager.beacons) { beacon in
                    VStack(alignment: .leading) {
                        Text("UUID: \(beacon.idUUID.uuidString)")
                            .font(.headline)
                        Text("Major: \(beacon.major), Minor: \(beacon.minor)")
                            .font(.subheadline)
                        Text("Distance: \(String(format: "%.2f", beacon.accuracy)) meters")
                            .font(.subheadline)
                        Text("Proximity: \(beacon.rssi)")
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .navigationTitle("Audium")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(BeaconManager())
    }
}
