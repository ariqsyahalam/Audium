//
//  ContentView.swift
//  Audium
//
//  Created by Reyhan Ariq Syahalam on 21/09/24.
//

import SwiftUI
import CoreLocation

struct ContentView: View {
    @ObservedObject var beaconManager = BeaconManager()
    @State private var isMonitoring = true

    var body: some View {
        VStack {
            Toggle(isOn: $isMonitoring) {
                Text(isMonitoring ? "Monitoring Aktif" : "Monitoring Nonaktif")
            }
            .padding()
            .onChange(of: isMonitoring) { value in
                if value {
                    beaconManager.startMonitoring()
                    beaconManager.startRanging()
                } else {
                    beaconManager.stopMonitoring()
                    beaconManager.stopRanging()
                }
            }

            if !beaconManager.beacons.isEmpty {
                List(beaconManager.beacons) { beacon in
                    VStack(alignment: .leading) {
                        Text("UUID: \(beacon.id.uuidString)")
                            .font(.headline)
                        Text("Major: \(beacon.major), Minor: \(beacon.minor)")
                        Text("Proximity: \(beacon.proximity.rawValue)")
                        Text(String(format: "Jarak: %.2f meter", beacon.accuracy))
                        Text("RSSI: \(beacon.rssi)")
                        Text("Waktu: \(beacon.timestamp, formatter: dateFormatter)")
                    }
                    .padding()
                }
            } else {
                Text("Tidak ada beacon terdekat")
                    .padding()
            }
        }
    }

    // Formatter untuk menampilkan tanggal dan waktu
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}



extension CLProximity {
    var stringValue: String {
        switch self {
        case .immediate:
            return "Sangat Dekat"
        case .near:
            return "Dekat"
        case .far:
            return "Jauh"
        default:
            return "Tidak Diketahui"
        }
    }
}


#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
