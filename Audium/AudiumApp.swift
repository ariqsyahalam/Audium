//
//  AudiumApp.swift
//  Audium
//
//  Created by Reyhan Ariq Syahalam on 21/09/24.
//

import SwiftUI
import SwiftData
import AVFoundation

@main
struct AudiumApp: App {
    init() {
        // Atur audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            print("Audio session berhasil diatur")
        } catch {
            print("Kesalahan mengatur audio session: \(error.localizedDescription)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

