//
//  AppEnviornment.swift
//  CSWang
//
//  Created by Dove Zachary on 2022/11/28.
//

import Foundation

struct AppEnvironment {
    let persistence = PersistenceController.shared
    let delayQueue = DispatchQueue(label: "com.chocoford.ExcalidrawZ_DelayQueue")
}
