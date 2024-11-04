import Foundation
import CoreLocation
import AVFoundation
import SwiftUI

// Struct to represent a detected BLE Beacon
struct BLEBeacon: Identifiable {
    let id = UUID()
    let idUUID: UUID
    let major: UInt16
    let minor: UInt16
    let accuracy: CLLocationAccuracy
    let rssi: Int

    var description: String {
        return "UUID: \(idUUID.uuidString), Major: \(major), Minor: \(minor), Accuracy: \(accuracy)m, RSSI: \(rssi)"
    }
}

// Struct to hold narration and background audio files for a beacon, along with RSSI threshold
struct BeaconAudioFiles {
    let narration: [String]    // Array of narration audio filenames
    let background: String     // Background audio filename
    let rssiThreshold: Int     // RSSI threshold for this beacon
}

class BeaconManager: NSObject, ObservableObject, CLLocationManagerDelegate, AVAudioPlayerDelegate {
    private var locationManager: CLLocationManager!

    // Published properties to update the UI
    @Published var beacons = [BLEBeacon]()
    @Published var isSessionActive: Bool = false
    @Published var currentAudio: String? = nil
    @Published var audioNote: String? = nil

    // Mapping between beacon UUIDs and their corresponding audio files and RSSI threshold
    let beaconAudioMapping: [UUID: BeaconAudioFiles] = [
        UUID(uuidString: "9D38C8B0-77F8-4E23-8DBA-1546C4D035A4")!: BeaconAudioFiles(
            narration: ["1.wav", "2.wav", "3.wav"],
            background: "a1.wav",
            rssiThreshold: -65
        ),
        UUID(uuidString: "3D023D21-83D9-4C48-94FB-48718E22AA14")!: BeaconAudioFiles(
            narration: ["4.wav", "5.wav", "6.wav", "7.wav", "8.wav"],
            background: "a2.wav",
            rssiThreshold: -75
        ),
        UUID(uuidString: "2D7A9F0C-E0E8-4CC9-A71B-A21DB2D034A1")!: BeaconAudioFiles(
            narration: ["9.wav", "10.wav"],
            background: "a3.wav",
            rssiThreshold: -70
        ),
        UUID(uuidString: "8C40139D-48F2-46ED-8668-0A3898D7C38E")!: BeaconAudioFiles(
            narration: ["11.wav", "12.wav"],
            background: "a4.wav",
            rssiThreshold: -70
        )
        // Add other mappings as needed
    ]

    private var beaconNarrationPlayer: AVAudioPlayer?
    private var beaconBackgroundPlayer: AVAudioPlayer?
    private var currentBeaconUUID: UUID? // UUID of currently playing beacon audio

    // Keeps track of the current narration index for each beacon
    private var beaconNarrationIndices: [UUID: Int] = [:]

    // Timer properties to delay stopping the audio
    private var stopAudioTimer: Timer?
    private let audioStopDelay: TimeInterval = 3.0 // Delay 3 seconds before stopping audio

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

    /// Starts the beacon scanning session
    func startSession() {
        locationManager.requestAlwaysAuthorization()

        if CLLocationManager.authorizationStatus() == .authorizedAlways ||
            CLLocationManager.authorizationStatus() == .authorizedWhenInUse {
            isSessionActive = true
            startScanning()
            print("Session started.")
        } else {
            print("Location permission not granted.")
        }
    }

    func stopSession() {
        isSessionActive = false
        stopScanning()
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

    // MARK: - CLLocationManagerDelegate Methods

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if isSessionActive {
                startScanning()
            }
        default:
            if isSessionActive {
                stopScanning()
                stopBeaconAudio()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        DispatchQueue.main.async {
            var strongBeacons = [CLBeacon]()

            for beacon in beacons {
                if let audioFiles = self.beaconAudioMapping[beacon.uuid] {
                    // Use the beacon's RSSI threshold
                    if beacon.rssi >= audioFiles.rssiThreshold && beacon.rssi != 0 {
                        strongBeacons.append(beacon)
                    }
                }
            }

            self.beacons = strongBeacons.map { beacon in
                BLEBeacon(idUUID: beacon.uuid,
                          major: beacon.major.uint16Value,
                          minor: beacon.minor.uint16Value,
                          accuracy: beacon.accuracy,
                          rssi: beacon.rssi)
            }

            // Find the closest beacon based on the highest RSSI value
            if let closestBeacon = strongBeacons.max(by: { $0.rssi < $1.rssi }) {
                // If the closest beacon has changed
                if self.currentBeaconUUID != closestBeacon.uuid {
                    // Stop current beacon audio
                    self.stopBeaconAudio()

                    // Reset narration index for the new beacon
                    self.beaconNarrationIndices[closestBeacon.uuid] = 0

                    // Set new current beacon
                    self.currentBeaconUUID = closestBeacon.uuid
                    self.playAudioForBeacon(uuid: closestBeacon.uuid)
                    self.audioNote = "Playing audio for beacon UUID \(closestBeacon.uuid.uuidString) with RSSI \(closestBeacon.rssi)."
                } else {
                    print("Beacon closest remains unchanged with RSSI \(closestBeacon.rssi); continuing current audio playback.")
                }

                self.cancelAudioStopTimer() // Cancel any pending audio stop
            } else {
                // No beacons meet their RSSI threshold
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
                self.audioNote = "Stopped audio as beacon UUID \(region.identifier) has exited the proximity."
            }
        }
    }

    // MARK: - Logging

    private func logScannedBeacons() {
        print("Scanned Beacons:")
        for beacon in beacons {
            print("- UUID: \(beacon.idUUID.uuidString), RSSI: \(beacon.rssi), Distance: \(String(format: "%.2f", beacon.accuracy)) meters")
        }
    }

    // MARK: - Beacon Audio Playback

    private func playAudioForBeacon(uuid: UUID) {
        guard let audioFiles = beaconAudioMapping[uuid] else {
            print("No audio mapped for beacon UUID: \(uuid.uuidString)")
            stopBeaconAudio()
            self.audioNote = "No audio mapped for beacon UUID \(uuid.uuidString)."
            return
        }

        // Play background audio in loop
        if let backgroundURL = Bundle.main.url(forResource: audioFiles.background, withExtension: nil) {
            do {
                beaconBackgroundPlayer = try AVAudioPlayer(contentsOf: backgroundURL)
                beaconBackgroundPlayer?.numberOfLoops = -1 // Loop indefinitely
                beaconBackgroundPlayer?.volume = 1.0
                beaconBackgroundPlayer?.prepareToPlay()
                beaconBackgroundPlayer?.play()
                print("Playing beacon background audio: \(audioFiles.background) for beacon UUID: \(uuid.uuidString)")
            } catch {
                print("Error playing beacon background audio: \(error.localizedDescription)")
                self.audioNote = "Error playing beacon background audio \(audioFiles.background): \(error.localizedDescription)"
            }
        } else {
            print("Background audio file \(audioFiles.background) not found for beacon UUID: \(uuid.uuidString)")
            self.audioNote = "Background audio file \(audioFiles.background) for beacon UUID \(uuid.uuidString) not found."
        }

        // Initialize narration index if not set
        if beaconNarrationIndices[uuid] == nil {
            beaconNarrationIndices[uuid] = 0
        }

        // Play the first narration audio
        playNextNarrationAudio(for: uuid)
    }

    private func playNextNarrationAudio(for uuid: UUID) {
        guard let audioFiles = beaconAudioMapping[uuid],
              let narrationIndex = beaconNarrationIndices[uuid],
              narrationIndex < audioFiles.narration.count else {
            print("No more narration audios to play for beacon UUID: \(uuid.uuidString)")
            return
        }

        let narrationFilename = audioFiles.narration[narrationIndex]

        if let narrationURL = Bundle.main.url(forResource: narrationFilename, withExtension: nil) {
            do {
                beaconNarrationPlayer = try AVAudioPlayer(contentsOf: narrationURL)
                beaconNarrationPlayer?.delegate = self // Set delegate to handle completion
                beaconNarrationPlayer?.numberOfLoops = 0 // Play once
                beaconNarrationPlayer?.volume = 1.0
                beaconNarrationPlayer?.prepareToPlay()
                beaconNarrationPlayer?.play()
                print("Playing beacon narration audio: \(narrationFilename) for beacon UUID: \(uuid.uuidString)")
                self.currentAudio = narrationFilename
                self.beaconNarrationIndices[uuid] = narrationIndex + 1 // Increment narration index
            } catch {
                print("Error playing beacon narration audio: \(error.localizedDescription)")
                self.audioNote = "Error playing beacon narration audio \(narrationFilename): \(error.localizedDescription)"
            }
        } else {
            print("Narration audio file \(narrationFilename) not found for beacon UUID: \(uuid.uuidString)")
            self.audioNote = "Narration audio file \(narrationFilename) for beacon UUID \(uuid.uuidString) not found."
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Check if the narration player finished playing
        if player == beaconNarrationPlayer, let uuid = currentBeaconUUID {
            // Play the next narration audio if available
            playNextNarrationAudio(for: uuid)
        }
    }

    private func stopBeaconAudio() {
        if beaconNarrationPlayer?.isPlaying == true {
            beaconNarrationPlayer?.stop()
            print("Beacon narration audio stopped.")
        }
        if beaconBackgroundPlayer?.isPlaying == true {
            beaconBackgroundPlayer?.stop()
            print("Beacon background audio stopped.")
        }
        self.currentAudio = nil

        // Reset the narration index for the current beacon
        if let uuid = currentBeaconUUID {
            beaconNarrationIndices[uuid] = 0
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
