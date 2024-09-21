//
//  BLEDevice.swift
//  Audium
//
//  Created by Reyhan Ariq Syahalam on 21/09/24.
//

import Foundation
import CoreBluetooth

struct BLEDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let uuid: UUID
    var rssi: NSNumber
    var distance: Double
    var distanceHistory: [Double] = []
    var lastSeen: Date // Tambahkan properti lastSeen
    
    // Menghitung rata-rata jarak dari riwayat
    var averageDistance: Double {
        guard !distanceHistory.isEmpty else { return distance }
        let sum = distanceHistory.reduce(0, +)
        return sum / Double(distanceHistory.count)
    }
    
    static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool {
        return lhs.id == rhs.id
    }
}
