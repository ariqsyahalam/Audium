//
//  BLEBeacon.swift
//  Audium
//
//  Created by Reyhan Ariq Syahalam on 21/09/24.
//

import Foundation
import CoreLocation

struct BLEBeacon: Identifiable {
    let id: UUID
    let major: CLBeaconMajorValue
    let minor: CLBeaconMinorValue
    var proximity: CLProximity
    var accuracy: CLLocationAccuracy
    var rssi: Int
    var timestamp: Date // Tambahkan properti timestamp

    var name: String {
        return "Beacon \(id.uuidString)"
    }
}
