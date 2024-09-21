//
//  ContentView.swift
//  Audium
//
//  Created by Reyhan Ariq Syahalam on 21/09/24.
//

import SwiftUI
import CoreBluetooth
import Combine

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var discoveredPeripherals: [(peripheral: CBPeripheral, id: UUID, rssi: NSNumber)] = []
    @Published var updateCount: Int = 0 // Variabel untuk menghitung jumlah pembaruan
    private var centralManager: CBCentralManager!
    private var rssiUpdateTimer: AnyCancellable?
    private var updateTimer: AnyCancellable?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        startUpdateTimer()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(where: { $0.peripheral == peripheral }) {
            let peripheralId = peripheral.identifier
            discoveredPeripherals.append((peripheral: peripheral, id: peripheralId, rssi: RSSI))
            startRSSIUpdate(for: peripheral)
        } else {
            // Update RSSI jika perangkat sudah ada
            if let index = discoveredPeripherals.firstIndex(where: { $0.peripheral == peripheral }) {
                discoveredPeripherals[index].rssi = RSSI
            }
        }
    }

    func startRSSIUpdate(for peripheral: CBPeripheral) {
        // Hentikan timer sebelumnya jika ada
        rssiUpdateTimer?.cancel()
        
        rssiUpdateTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self, weak peripheral] _ in
                guard let peripheral = peripheral, peripheral.state == .connected else {
                    return // Hentikan jika tidak terhubung
                }
                peripheral.readRSSI()
            }
    }

    func centralManager(_ central: CBCentralManager, didUpdateRSSI RSSI: NSNumber, for peripheral: CBPeripheral, error: Error?) {
        if let index = discoveredPeripherals.firstIndex(where: { $0.peripheral == peripheral }) {
            discoveredPeripherals[index].rssi = RSSI
        }
    }

    func startUpdateTimer() {
        updateTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePeripherals()
            }
    }

    func updatePeripherals() {
        // Scan ulang untuk perangkat BLE
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        updateCount += 1 // Tambahkan jumlah pembaruan
        print(updateCount)
    }

    // Fungsi untuk mengurutkan perangkat berdasarkan RSSI
    func sortedPeripherals() -> [(peripheral: CBPeripheral, id: UUID, rssi: NSNumber)] {
        return discoveredPeripherals.sorted { ($0.rssi).intValue > ($1.rssi).intValue }
    }
}

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()

    var body: some View {
        NavigationView {
            VStack {
                Text("Update Count: \(bluetoothManager.updateCount)")
                    .font(.headline)
                    .padding()

                List(bluetoothManager.sortedPeripherals(), id: \.id) { item in
                    VStack(alignment: .leading) {
                        Text(item.peripheral.name ?? "Unknown Device")
                            .font(.headline)
                        Text("ID: \(item.id.uuidString)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("RSSI: \(item.rssi) dBm")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
                .navigationTitle("Detected BLE Devices")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
