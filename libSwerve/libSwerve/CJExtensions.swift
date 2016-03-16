//
//  CJExtensions.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.15.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

let dlogQueue = dispatch_queue_create("us.curtisjones.libSwerve.CJExtensions.dlogqueue", nil)

public func DLog(message: String?, file: String = #file, line: Int = #line, function: String = #function) {
	dispatch_async(dlogQueue) {
		if let message = message where message.isEmpty == false {
			print("\(NSDate()): \(file)+\(line)::\(function).. \(message)")
		}
		else {
			print("\(NSDate()): \(file)+\(line)::\(function)")
		}
	}
}

internal func cjstrerror() -> String? {
	return String.fromCString(strerror(errno))
}

public func CJDispatchMain (async: Bool = true, _ block: () -> Void) {
	if async == true {
		dispatch_async(dispatch_get_main_queue(), block)
	}
	else {
		dispatch_sync(dispatch_get_main_queue(), block)
	}
}

public func CJDispatchBackground(async: Bool = true, _ block: () -> Void) {
	if async == true {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block)
	}
	else {
		dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block)
	}
}

extension NSError {
	
	convenience init(domain: String = "", code: Int = 0, description: String?) {
		self.init(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: description ?? ""])
	}
	
}
