import Foundation
import CoreLocation
import SwiftUI
import AVFoundation

class BeaconManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    var locationManager: CLLocationManager!

    @Published var beacons = [BLEBeacon]()

    // Pemetaan antara UUID beacon dan nama file audio
    let beaconAudioMapping: [UUID: String] = [
        UUID(uuidString: "ef63c140-2af4-4e1e-aab3-340055b3bb4b")!: "kini.mp3"
        // Tambahkan pasangan UUID dan nama file audio lainnya
    ]

    var audioPlayer: AVAudioPlayer?
    var currentBeaconUUID: UUID?

    var lastBeaconDetectionTime: Date?
    var beaconTimeoutTimer: Timer?

    override init() {
        super.init()
        locationManager = CLLocationManager()
        locationManager.delegate = self

        // Meminta izin lokasi
        locationManager.requestAlwaysAuthorization()

        // Atur jarak filter (opsional)
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false

        // Tambahkan observer untuk status aplikasi
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Mulai monitoring beacon
        startMonitoring()
        startBeaconTimeoutTimer()
    }

    deinit {
        beaconTimeoutTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc func appDidBecomeActive() {
        print("Aplikasi kembali aktif")
        // Mulai ranging saat aplikasi aktif
        startRanging()
    }

    @objc func appDidEnterBackground() {
        print("Aplikasi masuk ke latar belakang")
        // Hentikan ranging saat aplikasi masuk ke latar belakang
        stopRanging()
    }

    func startMonitoring() {
        for uuid in beaconAudioMapping.keys {
            let beaconRegion = CLBeaconRegion(uuid: uuid, identifier: uuid.uuidString)
            beaconRegion.notifyEntryStateOnDisplay = true
            beaconRegion.notifyOnEntry = true
            beaconRegion.notifyOnExit = true
            locationManager.startMonitoring(for: beaconRegion)
            print("Mulai monitoring beacon untuk UUID: \(uuid.uuidString)")
        }
    }

    func stopMonitoring() {
        for uuid in beaconAudioMapping.keys {
            let beaconRegion = CLBeaconRegion(uuid: uuid, identifier: uuid.uuidString)
            locationManager.stopMonitoring(for: beaconRegion)
            print("Hentikan monitoring beacon untuk UUID: \(uuid.uuidString)")
        }
    }

    func startRanging() {
        for uuid in beaconAudioMapping.keys {
            let beaconRegion = CLBeaconRegion(uuid: uuid, identifier: uuid.uuidString)
            locationManager.startRangingBeacons(satisfying: beaconRegion.beaconIdentityConstraint)
            print("Mulai ranging beacon untuk UUID: \(uuid.uuidString)")
        }
    }

    func stopRanging() {
        for uuid in beaconAudioMapping.keys {
            let beaconRegion = CLBeaconRegion(uuid: uuid, identifier: uuid.uuidString)
            locationManager.stopRangingBeacons(satisfying: beaconRegion.beaconIdentityConstraint)
            print("Hentikan ranging beacon untuk UUID: \(uuid.uuidString)")
        }
        // Bersihkan daftar beacon
        DispatchQueue.main.async {
            self.beacons.removeAll()
        }
    }

    func startBeaconTimeoutTimer() {
        beaconTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkBeaconTimeout()
        }
    }

    func checkBeaconTimeout() {
        guard let lastDetectionTime = lastBeaconDetectionTime else {
            // Jika lastDetectionTime nil, artinya tidak ada beacon yang terdeteksi
            DispatchQueue.main.async {
                if self.currentBeaconUUID != nil {
                    self.currentBeaconUUID = nil
                    self.stopAudio()
                    print("Audio dihentikan karena beacon tidak terdeteksi")
                }
            }
            return
        }
        let timeSinceLastDetection = Date().timeIntervalSince(lastDetectionTime)
        if timeSinceLastDetection > 10.0 {
            // Beacon tidak terdeteksi selama lebih dari 10 detik
            DispatchQueue.main.async {
                if self.currentBeaconUUID != nil {
                    self.currentBeaconUUID = nil
                    self.stopAudio()
                    print("Audio dihentikan karena beacon timeout")
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            print("Izin lokasi selalu diizinkan")
            startMonitoring()
            startRanging()
        case .authorizedWhenInUse:
            print("Izin lokasi saat digunakan diizinkan")
            // Jika Anda memerlukan izin "Always", informasikan kepada pengguna
            startMonitoring()
            startRanging()
        default:
            print("Izin lokasi tidak diizinkan")
            stopMonitoring()
            stopRanging()
        }
    }

    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        DispatchQueue.main.async {
            // Memperbarui daftar beacon yang terdeteksi
            self.beacons = beacons.map { beacon in
                BLEBeacon(id: beacon.uuid,
                          major: beacon.major.uint16Value,
                          minor: beacon.minor.uint16Value,
                          proximity: beacon.proximity,
                          accuracy: beacon.accuracy,
                          rssi: beacon.rssi,
                          timestamp: Date()) // Setel timestamp ke waktu saat ini
            }

            if !self.beacons.isEmpty {
                // Beacon terdeteksi
                self.lastBeaconDetectionTime = Date()
            } else {
                // Tidak ada beacon terdeteksi
                self.lastBeaconDetectionTime = nil
            }

            // Memperbarui UI atau log
            self.logScannedBeacons()
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("Memasuki wilayah beacon: \(region.identifier)")
        if let uuid = UUID(uuidString: region.identifier) {
            if self.currentBeaconUUID != uuid {
                self.currentBeaconUUID = uuid
                self.playAudioForBeacon(uuid: uuid)
                print("Memutar audio dalam didEnterRegion untuk UUID: \(uuid.uuidString)")
            } else {
                print("Beacon yang sama sudah aktif, tidak memutar ulang audio")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("Keluar dari wilayah beacon: \(region.identifier)")
        DispatchQueue.main.async {
            if self.currentBeaconUUID?.uuidString == region.identifier {
                self.currentBeaconUUID = nil
                self.stopAudio()
                print("Audio dihentikan karena keluar dari region beacon")
            }
        }
    }

    // Fungsi untuk mencatat log daftar beacon yang dipindai
    func logScannedBeacons() {
        print("Daftar beacon yang dipindai:")
        for beacon in beacons {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let timestampString = dateFormatter.string(from: beacon.timestamp)
            print("- UUID: \(beacon.id.uuidString), Major: \(beacon.major), Minor: \(beacon.minor), RSSI: \(beacon.rssi), Jarak: \(String(format: "%.2f", beacon.accuracy)) meter, Waktu: \(timestampString)")
        }
    }


    // Fungsi untuk memutar audio berdasarkan UUID beacon
    func playAudioForBeacon(uuid: UUID) {
        // Atur AVAudioSession
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Kesalahan mengatur AVAudioSession: \(error.localizedDescription)")
        }

        if let audioFileName = beaconAudioMapping[uuid] {
            // Cek apakah file audio ada
            if let audioURL = Bundle.main.url(forResource: audioFileName, withExtension: nil) {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                    audioPlayer?.numberOfLoops = -1 // Ulangi terus menerus
                    audioPlayer?.prepareToPlay()
                    audioPlayer?.play()
                    print("Memutar audio: \(audioFileName) untuk beacon UUID: \(uuid.uuidString)")
                } catch {
                    print("Kesalahan memutar audio: \(error.localizedDescription)")
                }
            } else {
                print("File audio \(audioFileName) tidak ditemukan")
            }
        } else {
            print("Tidak ada audio yang terkait dengan beacon UUID: \(uuid.uuidString)")
            stopAudio()
        }
    }

    func stopAudio() {
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
            print("Menghentikan audio")
        }
        // Nonaktifkan AVAudioSession
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Kesalahan menonaktifkan AVAudioSession: \(error.localizedDescription)")
        }
    }
}
