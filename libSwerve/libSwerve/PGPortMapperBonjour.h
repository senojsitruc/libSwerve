//
//  PGPortMapperBonjour.h
//  PigeonGuts
//
//  Created by Jones Curtis on 2011.12.18.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PGPortMapperBonjour : NSObject
{
	UInt16 _port, _desiredPublicPort, _publicPort;
	BOOL _mapTCP, _mapUDP;
	SInt32 _error;
	void *_service; // DNSServiceRef
	CFSocketRef _socket;
	CFRunLoopSourceRef _socketSource;
	UInt32 _rawPublicAddress;
	NSString *_publicAddress;
	
	void (^mHandler) (PGPortMapperBonjour*);
}

@property (readwrite) BOOL mapTCP;
@property (readwrite) BOOL mapUDP;
@property (readwrite) UInt16 desiredPublicPort;
@property (readonly) SInt32 error;
@property (readonly) UInt32 rawPublicAddress;
@property (readonly,copy) NSString* publicAddress;
@property (readonly) unsigned short publicPort;
@property (readonly) BOOL isMapped;

/**
 * Class methods.
 */
+ (NSString *)publicAddress;
+ (NSString *)localAddress;
+ (UInt32)rawLocalAddress;
+ (BOOL)localAddressIsPrivate;

/**
 * Initializes a PortMapper that will map the given local (private) port. By default it will map TCP
 * and not UDP, and will not suggest a desired public port, but this can be configured by setting 
 * properties before opening the PortMapper.
 */
- (id)initWithPrivatePort:(UInt16)privatePort publicPort:(UInt16)publicPort handler:(void (^)(PGPortMapperBonjour*))handler;

/**
 * Opens the PortMapper, using the current settings of the above properties. Returns immediately; 
 * you can find out when the mapping is created or fails by observing the error / publicAddress /
 * publicPort properties, or by listening for the PortMapperChangedNotification. It's very unlikely
 * that this call will fail (return NO). If it does, it probably means that the mDNSResponder 
 * process isn't working.
 */
- (BOOL)open;

/**
 * Blocks till the PortMapper finishes opening. Returns YES if it opened, NO on error. It's not 
 * usually a good idea to use this, as it will lock up your application until a response arrives 
 * from the NAT. Listen for asynchronous notifications instead. If called when the PortMapper is 
 * closed, it will call -open for you. If called when it's already open, it just returns YES. 
 */
- (BOOL)waitTillOpened;

/**
 * Closes the PortMapper, terminating any open port mapping.
 */
- (void)close;

@end
