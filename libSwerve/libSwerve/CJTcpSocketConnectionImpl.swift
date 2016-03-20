//
//  CJTcpSocketConnectionImpl.swift
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.19.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

import Foundation

internal class CJTcpSocketConnectionImpl: CJSocketConnection {
	
	var context: Any?
	var readHandler: CJConnectionReadHandler?
	var readHandler2: CJConnectionReadHandler2?
	var closeHandler: ((CJConnection) -> Void)?
	
	var channel: dispatch_io_t!
	let indata: dispatch_data_t
	
	var sockfd: Int32
	let soaddr: sockaddr_in
	let remoteAddr: String
	let remotePort: UInt16
	
	private var stop: Int32 = 0
	private let queue = dispatch_queue_create("us.curtisjones.libSwerve.CJTcpServerImpl.queue", DISPATCH_QUEUE_SERIAL)
	private let group = dispatch_group_create()
	private let pauser = dispatch_group_create()
	private var bytesIn: size_t = 0
	private var bytesOut: size_t = 0
	private var lastReadTime: dispatch_time_t = 0
	
	required init(sockfd: Int32, soaddr: sockaddr_in) {
		self.sockfd = sockfd
		self.soaddr = soaddr
		self.remoteAddr = CJAddrToString(soaddr.sin_addr, family: soaddr.sin_family) ?? ""
		self.remotePort = soaddr.sin_port
		self.indata = dispatch_data_create(nil, 0, nil, nil)
		
		log("Incoming connection established.")
	}
	
	func open() {
		self.channel = dispatch_io_create(DISPATCH_IO_STREAM, dispatch_fd_t(sockfd), queue) { [weak self, sockfd] error in
			if error != 0 {
				self?.log("Channel open failed. [sockfd = \(sockfd), error = (\(error)) \(cjstrerror(error))")
				self?.channel = nil
				self?.close()
			}
			else {
				self?.log("Channel closed. [sockfd = \(sockfd)]")
			}
		}
		
		guard let channel = self.channel else { return }
		
		dispatch_io_set_low_water(channel, 1)
		dispatch_io_set_interval(channel, 10000000000, DISPATCH_IO_STRICT_INTERVAL)
		dispatch_io_read(channel, 0, Int.max, queue) { [weak self, group, pauser] done, data, error in
			// stop!
			if self?.stop != 0 { return }
			
			dispatch_group_enter(group)
			dispatch_group_wait(pauser, DISPATCH_TIME_FOREVER)
			
			let currentTime = dispatch_time(DISPATCH_TIME_NOW, 0)
			let lastReadTime = self?.lastReadTime ?? 0
			
			// if there's data, process it. otherwise, if the connection has been idlea too long, close it.
			if data != nil && dispatch_data_get_size(data) != 0 {
				self?.handleIncoming(done: done, data: data, error: error)
			}
			else if done != true && lastReadTime != 0 && currentTime > lastReadTime + (NSEC_PER_SEC * 60) {
				self?.log("Closing idle connection.")
				self?.close()
			}
			
			self?.lastReadTime = currentTime
			
			if done == true || error != 0 {
				self?.close()
				self?.log("Error while reading. \(error) = \(cjstrerror(error))")
			}
			
			dispatch_group_leave(group)
		}
	}
	
	func close() {
		if OSAtomicCompareAndSwap32(0, 1, &stop) == false { return }
		
		dispatch_group_notify(group, queue) { [sockfd] in
			self.readHandler = nil
			self.sockfd = 0
			
			if let channel = self.channel {
				dispatch_io_close(channel, DISPATCH_IO_STOP)
			}
			Darwin.close(sockfd)
			
			self.closeHandler?(self)
			
			self.closeHandler = nil
			self.context = nil
			
			self.log("Connection closed. [bytesIn = \(self.bytesIn); bytesOut = \(self.bytesOut)]")
		}
	}
	
	func pause() {
		dispatch_group_enter(pauser)
	}
	
	func resume() {
		dispatch_group_leave(pauser)
	}
	
	func write(bytes: UnsafePointer<Void>, size: Int, completionHandler: ((Bool) -> Void)?) {
		//log("Writing \(size) bytes.")
		
		if stop != 0 {
			log("Cannot write to a closed connection.")
			completionHandler?(false)
			return
		}
		
		bytesOut += size
		
		dispatch_group_enter(group)
		dispatch_io_write(channel, 0, dispatch_data_create(bytes, size, nil, nil), queue) { [group] done, data, error in
			if done == true {
				completionHandler?(error == 0)
				
				if error != 0 {
					self.close()
					self.log("Writing. [error = [\(error)] \(cjstrerror(error))]")
				}
				
				dispatch_group_leave(group)
			}
			else if error != 0 {
				self.log("Writing. [error = [\(error)] \(cjstrerror(error))]")
				dispatch_group_leave(group)
			}
		}
	}
	
	private final func handleIncoming(done done: Bool, data: dispatch_data_t, error: Int32) {
		if stop != 0 { return }
		
		let size = dispatch_data_get_size(data)
		if size == 0 { return }
		bytesIn += size
		
		if let handler = readHandler {
			dispatch_data_apply(data) { region, offset, buffer, size in handler(buffer, size); return true }
		}
		else if let handler = readHandler2 {
			handler(data, size)
		}
	}
	
	private final func log(string: String) {
		DLog("\(remoteAddr):\(remotePort) [sockfd = \(sockfd)] :: " + string)
	}
	
}
