//
//  Item.swift
//  Sounder
//
//  Created by Boris Krasnoiarov on 9/17/25.
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
