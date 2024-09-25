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
        UUID(uuidString: "EF63C140-2AF4-4E1E-AAB3-340055B3BB4A")!: "beaconAudio1.mp3",
        UUID(uuidString: "EF63C140-2AF4-4E1E-AAB3-340055B3BB4C")!: "beaconAudio2.mp3",
        UUID(uuidString: "EF63C140-2AF4-4E1E-AAB3-340055B3BB4D")!: "beaconAudio3.mp3"
    ]
    
    private var backgroundPlayer: AVAudioPlayer?
    private var beaconAudioPlayer: AVAudioPlayer?
    private var currentBeaconUUID: UUID?
    
    // Dictionary to store distance measurements for each beacon
    private var beaconMeasurements: [UUID: [Measurement]] = [:]
    private let measurementInterval: TimeInterval = 3.0 // 3 seconds
    
    override init() {
        super.init()
        locationManager = CLLocationManager()
        locationManager.delegate = self
        
        // Set distance filter to none and prevent automatic pausing
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    // MARK: - Session Control
    
    /// Starts the beacon scanning session and background music playback
    func startSession() {
        // Request always authorization for location access
        locationManager.requestAlwaysAuthorization()
        
        // Check authorization status
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
    
    /// Stops the beacon scanning session and background music playback
    func stopSession() {
        isSessionActive = false
        stopScanning()
        stopBackgroundMusic()
        stopBeaconAudio()
        print("Session stopped.")
    }
    
    // MARK: - Beacon Scanning
    
    /// Starts scanning for all beacons defined in `beaconAudioMapping`
    private func startScanning() {
        for uuid in beaconAudioMapping.keys {
            let beaconRegion = CLBeaconRegion(uuid: uuid, identifier: uuid.uuidString)
            beaconRegion.notifyEntryStateOnDisplay = true
            locationManager.startMonitoring(for: beaconRegion)
            locationManager.startRangingBeacons(satisfying: beaconRegion.beaconIdentityConstraint)
            print("Started scanning for beacon with UUID: \(uuid.uuidString)")
        }
    }
    
    /// Stops scanning for all beacons
    private func stopScanning() {
        for uuid in beaconAudioMapping.keys {
            let beaconRegion = CLBeaconRegion(uuid: uuid, identifier: uuid.uuidString)
            locationManager.stopMonitoring(for: beaconRegion)
            locationManager.stopRangingBeacons(satisfying: beaconRegion.beaconIdentityConstraint)
            print("Stopped scanning for beacon with UUID: \(uuid.uuidString)")
        }
    }
    
    // MARK: - Background Music Management
    
    /// Starts playing the background music in a loop
    private func startBackgroundMusic() {
        guard let backgroundAudioURL = Bundle.main.url(forResource: "backgroundMusic", withExtension: "mp3") else {
            print("Background music file not found.")
            return
        }
        
        do {
            backgroundPlayer = try AVAudioPlayer(contentsOf: backgroundAudioURL)
            backgroundPlayer?.numberOfLoops = -1 // Loop indefinitely
            backgroundPlayer?.volume = 0.5 // Adjust volume as needed
            backgroundPlayer?.prepareToPlay()
            backgroundPlayer?.play()
            print("Background music started.")
        } catch {
            print("Error playing background music: \(error.localizedDescription)")
        }
    }
    
    /// Stops the background music playback
    private func stopBackgroundMusic() {
        if backgroundPlayer?.isPlaying == true {
            backgroundPlayer?.stop()
            print("Background music stopped.")
        }
    }
    
    // MARK: - CLLocationManagerDelegate Methods
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Automatically start or stop scanning based on authorization status
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
            // Filter beacons with proximity .immediate or .near
            let nearBeacons = beacons.filter { $0.proximity == .immediate || $0.proximity == .near }
            
            // Update the list of detected beacons
            self.beacons = nearBeacons.map { beacon in
                BLEBeacon(idUUID: beacon.uuid,
                          major: beacon.major.uint16Value,
                          minor: beacon.minor.uint16Value,
                          proximity: beacon.proximity,
                          accuracy: beacon.accuracy,
                          rssi: beacon.rssi)
            }
            
            // Update distance measurements for immediate and near beacons
            let currentTime = Date()
            for beacon in nearBeacons {
                let uuid = beacon.uuid
                let distance = beacon.accuracy
                
                if self.beaconMeasurements[uuid] != nil {
                    self.beaconMeasurements[uuid]?.append(Measurement(distance: distance, timestamp: currentTime))
                } else {
                    self.beaconMeasurements[uuid] = [Measurement(distance: distance, timestamp: currentTime)]
                }
                
                // Remove measurements older than the measurement interval
                self.beaconMeasurements[uuid] = self.beaconMeasurements[uuid]?.filter { measurement in
                    return currentTime.timeIntervalSince(measurement.timestamp) <= self.measurementInterval
                }
            }
            
            // Calculate average distance for each beacon
            var averageDistances: [UUID: CLLocationAccuracy] = [:]
            for (uuid, measurements) in self.beaconMeasurements {
                guard !measurements.isEmpty else { continue }
                let totalDistance = measurements.reduce(0) { $0 + $1.distance }
                let averageDistance = totalDistance / Double(measurements.count)
                averageDistances[uuid] = averageDistance
            }
            
            // Determine the closest beacon based on average distance
            if let (closestBeaconUUID, closestAverageDistance) = averageDistances.min(by: { $0.value < $1.value }) {
                // Check if the average distance is below 1 meter
                if closestAverageDistance < 1.0 {
                    if self.currentBeaconUUID != closestBeaconUUID {
                        // Closest beacon has changed and is within 1 meter
                        self.currentBeaconUUID = closestBeaconUUID
                        self.playAudioForBeacon(uuid: closestBeaconUUID)
                        
                        // Set audio note explaining why the audio is playing
                        self.audioNote = "Playing audio for beacon UUID \(closestBeaconUUID.uuidString) as it is within 1 meter."
                    } else {
                        // Closest beacon remains the same and is still within 1 meter
                        print("Closest beacon remains unchanged and within 1 meter; continuing current audio playback.")
                    }
                } else {
                    // Closest beacon is beyond 1 meter; stop audio if any
                    if self.currentBeaconUUID != nil {
                        self.currentBeaconUUID = nil
                        self.stopBeaconAudio()
                        
                        // Set audio note explaining why the audio is stopped
                        self.audioNote = "Stopping audio playback as the closest beacon is beyond 1 meter."
                    }
                }
            } else {
                // No immediate or near beacons detected within the measurement interval
                if self.currentBeaconUUID != nil {
                    self.currentBeaconUUID = nil
                    self.stopBeaconAudio()
                    
                    // Set audio note explaining why the audio is stopped
                    self.audioNote = "Stopping audio playback as no beacons are within 1 meter for the last 3 seconds."
                }
            }
            
            // Log scanned beacons
            self.logScannedBeacons()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("Entered beacon region: \(region.identifier)")
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("Exited beacon region: \(region.identifier)")
        DispatchQueue.main.async {
            // Remove the exited beacon from the list
            self.beacons.removeAll { $0.idUUID.uuidString == region.identifier }
            if self.currentBeaconUUID?.uuidString == region.identifier {
                self.currentBeaconUUID = nil
                self.stopBeaconAudio()
                
                // Set audio note explaining why the audio is stopped
                self.audioNote = "Stopped audio as beacon UUID \(region.identifier) has exited the 1-meter proximity."
            }
            
            // Remove distance measurements for the exited beacon
            if let uuid = UUID(uuidString: region.identifier) {
                self.beaconMeasurements.removeValue(forKey: uuid)
            }
        }
    }
    
    // MARK: - Logging
    
    /// Logs all scanned beacons with their details
    private func logScannedBeacons() {
        print("Scanned Beacons:")
        for beacon in beacons {
            print("- UUID: \(beacon.idUUID.uuidString), RSSI: \(beacon.rssi), Distance: \(String(format: "%.2f", beacon.accuracy)) meters, Proximity: \(beacon.proximity.stringValue)")
        }
    }
    
    // MARK: - Beacon Audio Playback
    
    /// Plays the audio associated with a specific beacon UUID
    /// - Parameter uuid: The UUID of the beacon
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
            // Stop any currently playing beacon audio
            stopBeaconAudio()
            
            // Initialize and play the beacon-specific audio
            beaconAudioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            beaconAudioPlayer?.numberOfLoops = -1 // Loop indefinitely
            beaconAudioPlayer?.volume = 1.0 // Adjust volume as needed
            beaconAudioPlayer?.prepareToPlay()
            beaconAudioPlayer?.play()
            print("Playing beacon audio: \(audioFileName) for beacon UUID: \(uuid.uuidString)")
            
            // Update the current audio being played
            self.currentAudio = audioFileName
        } catch {
            print("Error playing beacon audio: \(error.localizedDescription)")
            self.audioNote = "Error playing beacon audio \(audioFileName): \(error.localizedDescription)"
        }
    }
    
    /// Stops the currently playing beacon audio
    private func stopBeaconAudio() {
        if beaconAudioPlayer?.isPlaying == true {
            beaconAudioPlayer?.stop()
            print("Beacon audio stopped.")
            self.currentAudio = nil
        }
    }
    
    // MARK: - Helper Methods
    
    /// Provides a descriptive string for the beacon's proximity
    /// - Parameter uuid: The UUID of the beacon
    /// - Returns: A string describing the beacon's proximity
    private func beaconProximityDescription(for uuid: UUID) -> String {
        if let beacon = beacons.first(where: { $0.idUUID == uuid }) {
            switch beacon.proximity {
            case .immediate:
                return "Immediate"
            case .near:
                return "Near"
            default:
                return "Unknown"
            }
        }
        return "Unknown"
    }
}
