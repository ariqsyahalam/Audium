import Foundation
import CoreBluetooth
import SwiftUI

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    var centralManager: CBCentralManager!
    
    @Published var devices = [BLEDevice]()
    
    var cleanupTimer: Timer?
    
    override init() {
        super.init()
        // Inisialisasi centralManager dengan opsi latar belakang
        let centralQueue = DispatchQueue(label: "id.budionosiregar.Audium", attributes: .concurrent)
        let options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true
            // Hapus opsi pemulihan status jika tidak diperlukan
            // CBCentralManagerOptionRestoreIdentifierKey: "com.yourapp.bluetoothCentralManager"
        ]
        centralManager = CBCentralManager(delegate: self, queue: centralQueue, options: options)
        
        // Daftarkan notifikasi aplikasi masuk ke latar belakang dan kembali ke latar depan
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    @objc func didEnterBackground() {
        print("Aplikasi masuk ke latar belakang")
        // Lanjutkan pemindaian di latar belakang jika memungkinkan
        startScanning()
    }
    
    @objc func willEnterForeground() {
        print("Aplikasi akan masuk ke latar depan")
        // Mulai ulang pemindaian jika diperlukan
        startScanning()
    }
    
    func startScanning() {
        print("Mulai pemindaian")
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    func stopScanning() {
        print("Hentikan pemindaian")
        centralManager.stopScan()
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            if central.state == .poweredOn {
                print("Bluetooth aktif")
                // Mulai pemindaian
                self.startScanning()
                // Mulai timer untuk membersihkan perangkat yang tidak aktif
                self.cleanupTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    self.cleanupDevices()
                }
                self.cleanupTimer?.tolerance = 0.1
            } else {
                print("Bluetooth tidak tersedia")
                self.cleanupTimer?.invalidate()
                self.cleanupTimer = nil
                self.devices.removeAll()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let distance = calculateDistance(rssi: RSSI)
        let deviceName = peripheral.name ?? "Tidak Diketahui"
        let currentTime = Date()
        
        DispatchQueue.main.async {
            if let index = self.devices.firstIndex(where: { $0.id == peripheral.identifier }) {
                // Perbarui perangkat yang sudah ada
                var device = self.devices[index]
                device.rssi = RSSI
                device.distance = distance
                device.lastSeen = currentTime
                
                // Perbarui riwayat jarak
                device.distanceHistory.append(distance)
                if device.distanceHistory.count > 5 {
                    device.distanceHistory.removeFirst(device.distanceHistory.count - 5)
                }
                
                self.devices[index] = device
            } else {
                // Tambahkan perangkat baru
                var device = BLEDevice(id: peripheral.identifier,
                                       name: deviceName,
                                       uuid: peripheral.identifier,
                                       rssi: RSSI,
                                       distance: distance,
                                       lastSeen: currentTime)
                device.distanceHistory.append(distance)
                self.devices.append(device)
            }
            
            // Tambahkan log daftar perangkat yang dipindai
            self.logScannedDevices()
        }
    }
    
    func calculateDistance(rssi: NSNumber) -> Double {
        let txPower = -59
        let n: Double = 2.0
        let rssiValue = Double(truncating: rssi)
        let distance = pow(10.0, (Double(txPower) - rssiValue) / (10.0 * n))
        return distance
    }
    
    func cleanupDevices() {
        let timeoutInterval: TimeInterval = 5.0
        let currentTime = Date()
        
        DispatchQueue.main.async {
            self.devices.removeAll { device in
                return currentTime.timeIntervalSince(device.lastSeen) > timeoutInterval
            }
        }
    }
    
    // Fungsi untuk mencatat log daftar perangkat yang dipindai
    func logScannedDevices() {
        print("Daftar perangkat yang dipindai:")
        for device in devices {
            print("- Nama: \(device.name), RSSI: \(device.rssi), Jarak: \(String(format: "%.2f", device.distance)) meter")
        }
    }
}
