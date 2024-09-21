//
//  Item.swift
//  Audium
//
//  Created by Reyhan Ariq Syahalam on 21/09/24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
