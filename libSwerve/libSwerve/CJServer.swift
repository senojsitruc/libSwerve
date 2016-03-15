//
//  CJServer.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

protocol CJServer {
	
	var isRunning: Bool { get }
	
	func start(completionHandler: (Bool, NSError?) -> Void)
	func stop(completionHandler: (Bool, NSError?) -> Void)
	
}
