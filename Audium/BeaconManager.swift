import Foundation
import CoreLocation
import AVFoundation
import SwiftUI

// Struct to store individual distance measurements with timestamps
struct Measurement {
    let distance: CLLocationAccuracy
    let timestamp: Date
}

// Struct to represent a detected BLE Beacon
struct BLEBeacon: Identifiable {
    let id = UUID()
    let idUUID: UUID
    let major: UInt16
    let minor: UInt16
    let proximity: CLProximity
    let accuracy: CLLocationAccuracy
    let rssi: Int

    var description: String {
        return "UUID: \(idUUID.uuidString), Major: \(major), Minor: \(minor), Proximity: \(proximity), Accuracy: \(accuracy)m, RSSI: \(rssi)"
    }
}

extension CLProximity {
    var stringValue: String {
        switch self {
        case .immediate:
            return "Immediate"
        case .near:
            return "Near"
        case .far:
            return "Far"
        default:
            return "Unknown"
        }
    }
}

class BeaconManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager: CLLocationManager!
    
    // Published properties to update the UI
    @Published var beacons = [BLEBeacon]()
    @Published var isSessionActive: Bool = false
    @Published var currentAudio: String? = nil
    @Published var audioNote: String? = nil
    
    // Mapping between beacon UUIDs and their corresponding audio file names
    let beaconAudioMapping: [UUID: String] = [
        UUID(uuidString: "EF63C140-2AF4-4E1E-AAB3-340055B3BB4A")!: "satubulansabach.mp3",
        UUID(uuidString: "EF63C140-2AF4-4E1E-AAB3-340055B3BB4C")!: "diesabach.mp3",
        UUID(uuidString: "EF63C140-2AF4-4E1E-AAB3-340055B3BB4D")!: "creepsabach.mp3"
    ]
    
    private var backgroundPlayer: AVAudioPlayer?
    private var beaconAudioPlayer: AVAudioPlayer?
    private var currentBeaconUUID: UUID? // UUID of currently playing beacon audio
    
    // Timer properties to delay stopping the audio
    private var stopAudioTimer: Timer?
    private let audioStopDelay: TimeInterval = 3.0 // Delay 5 seconds before stopping audio
    
    override init() {
        super.init()
        locationManager = CLLocationManager()
        locationManager.delegate = self
        
        // Set distance filter to none and prevent automatic pausing
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // Configure audio session
        configureAudioSession()
    }
    
    // MARK: - Audio Session Configuration
    
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Session Control
    
    /// Starts the beacon scanning session and background music playback
    func startSession() {
        locationManager.requestAlwaysAuthorization()
        
        if CLLocationManager.authorizationStatus() == .authorizedAlways ||
            CLLocationManager.authorizationStatus() == .authorizedWhenInUse {
            isSessionActive = true
            startScanning()
            startBackgroundMusic()
            print("Session started.")
        } else {
            print("Location permission not granted.")
        }
    }
    
    func stopSession() {
        isSessionActive = false
        stopScanning()
        stopBackgroundMusic()
        stopBeaconAudio()
        print("Session stopped.")
    }
    
    // MARK: - Beacon Scanning
    
    private func startScanning() {
        for uuid in beaconAudioMapping.keys {
            let beaconRegion = CLBeaconRegion(uuid: uuid, identifier: uuid.uuidString)
            beaconRegion.notifyEntryStateOnDisplay = true
            locationManager.startMonitoring(for: beaconRegion)
            locationManager.startRangingBeacons(satisfying: beaconRegion.beaconIdentityConstraint)
            print("Started scanning for beacon with UUID: \(uuid.uuidString)")
        }
    }
    
    private func stopScanning() {
        for uuid in beaconAudioMapping.keys {
            let beaconRegion = CLBeaconRegion(uuid: uuid, identifier: uuid.uuidString)
            locationManager.stopMonitoring(for: beaconRegion)
            locationManager.stopRangingBeacons(satisfying: beaconRegion.beaconIdentityConstraint)
            print("Stopped scanning for beacon with UUID: \(uuid.uuidString)")
        }
    }
    
    // MARK: - Background Music Management
    
    private func startBackgroundMusic() {
        guard let backgroundAudioURL = Bundle.main.url(forResource: "bg", withExtension: "mp3") else {
            print("Background music file not found.")
            return
        }
        
        do {
            backgroundPlayer = try AVAudioPlayer(contentsOf: backgroundAudioURL)
            backgroundPlayer?.numberOfLoops = -1
            backgroundPlayer?.volume = 0.5
            backgroundPlayer?.prepareToPlay()
            backgroundPlayer?.play()
            print("Background music started.")
        } catch {
            print("Error playing background music: \(error.localizedDescription)")
        }
    }
    
    private func stopBackgroundMusic() {
        if backgroundPlayer?.isPlaying == true {
            backgroundPlayer?.stop()
            print("Background music stopped.")
        }
    }
    
    // MARK: - CLLocationManagerDelegate Methods
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if isSessionActive {
                startScanning()
                startBackgroundMusic()
            }
        default:
            if isSessionActive {
                stopScanning()
                stopBackgroundMusic()
                stopBeaconAudio()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        DispatchQueue.main.async {
            let nearBeacons = beacons.filter { $0.proximity == .immediate }
            
            self.beacons = nearBeacons.map { beacon in
                BLEBeacon(idUUID: beacon.uuid,
                          major: beacon.major.uint16Value,
                          minor: beacon.minor.uint16Value,
                          proximity: beacon.proximity,
                          accuracy: beacon.accuracy,
                          rssi: beacon.rssi)
            }
            
            // Cek apakah ada beacon dalam radius 1 meter
            let beaconsWithin1Meter = nearBeacons.filter { $0.accuracy < 1 }
            
            if let closestBeacon = beaconsWithin1Meter.min(by: { $0.accuracy < $1.accuracy }) {
                // Beacon paling dekat berubah atau berbeda
                if self.currentBeaconUUID != closestBeacon.uuid {
                    // Hentikan audio beacon yang sedang berjalan
                    self.stopBeaconAudio()
                    
                    // Ganti ke beacon yang baru
                    self.currentBeaconUUID = closestBeacon.uuid
                    self.playAudioForBeacon(uuid: closestBeacon.uuid)
                    self.audioNote = "Playing audio for beacon UUID \(closestBeacon.uuid.uuidString) as it is within 0.5 meter."
                } else {
                    print("Beacon closest remains unchanged and within 0.5 meter; continuing current audio playback.")
                }
                
                self.cancelAudioStopTimer() // Cancel any pending audio stop
            } else {
                // Tidak ada beacon dalam radius 1 meter
                if self.currentBeaconUUID != nil {
                    self.scheduleAudioStop()
                }
            }
            
            self.logScannedBeacons()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("Entered beacon region: \(region.identifier)")
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("Exited beacon region: \(region.identifier)")
        DispatchQueue.main.async {
            self.beacons.removeAll { $0.idUUID.uuidString == region.identifier }
            if self.currentBeaconUUID?.uuidString == region.identifier {
                self.scheduleAudioStop()
                self.audioNote = "Stopped audio as beacon UUID \(region.identifier) has exited the 1-meter proximity."
            }
        }
    }
    
    // MARK: - Logging
    
    private func logScannedBeacons() {
        print("Scanned Beacons:")
        for beacon in beacons {
            print("- UUID: \(beacon.idUUID.uuidString), RSSI: \(beacon.rssi), Distance: \(String(format: "%.2f", beacon.accuracy)) meters, Proximity: \(beacon.proximity.stringValue)")
        }
    }
    
    // MARK: - Beacon Audio Playback
    
    private func playAudioForBeacon(uuid: UUID) {
        guard let audioFileName = beaconAudioMapping[uuid] else {
            print("No audio mapped for beacon UUID: \(uuid.uuidString)")
            stopBeaconAudio()
            self.audioNote = "No audio mapped for beacon UUID \(uuid.uuidString)."
            return
        }
        
        guard let audioURL = Bundle.main.url(forResource: audioFileName, withExtension: nil) else {
            print("Audio file \(audioFileName) not found for beacon UUID: \(uuid.uuidString)")
            self.audioNote = "Audio file \(audioFileName) for beacon UUID \(uuid.uuidString) not found."
            return
        }
        
        do {
            beaconAudioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            beaconAudioPlayer?.numberOfLoops = -1
            beaconAudioPlayer?.volume = 1.0
            beaconAudioPlayer?.prepareToPlay()
            beaconAudioPlayer?.play()
            print("Playing beacon audio: \(audioFileName) for beacon UUID: \(uuid.uuidString)")
            self.currentAudio = audioFileName
        } catch {
            print("Error playing beacon audio: \(error.localizedDescription)")
            self.audioNote = "Error playing beacon audio \(audioFileName): \(error.localizedDescription)"
        }
    }
    
    private func stopBeaconAudio() {
        if beaconAudioPlayer?.isPlaying == true {
            beaconAudioPlayer?.stop()
            print("Beacon audio stopped.")
            self.currentAudio = nil
        }
    }
    
    // MARK: - Audio Stop Timer
    
    private func scheduleAudioStop() {
        if stopAudioTimer == nil {
            stopAudioTimer = Timer.scheduledTimer(withTimeInterval: audioStopDelay, repeats: false) { _ in
                self.stopBeaconAudio()
                self.currentBeaconUUID = nil
                self.audioNote = "Audio stopped after beacon lost for more than \(self.audioStopDelay) seconds."
                self.stopAudioTimer = nil
            }
        }
    }
    
    private func cancelAudioStopTimer() {
        stopAudioTimer?.invalidate()
        stopAudioTimer = nil
    }
}
