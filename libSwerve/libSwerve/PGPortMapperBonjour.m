//
//  PGPortMapperBonjour.m
//  PigeonGuts
//
//  Created by Jones Curtis on 2011.12.18.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "PGPortMapperBonjour.h"
#import <dns_sd.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <net/if.h>
#import <netinet/in.h>
#import <ifaddrs.h>

#ifndef Log
#define ENABLE_LOGGING 0
#define Log   if(!ENABLE_LOGGING) ; else NSLog
#endif

//
// Private IP address ranges. See RFC 3330.
//
static const struct {UInt32 mask, value;} kPrivateRanges[] =
{
	{0xFF000000, 0x00000000},       //   0.x.x.x (hosts on "this" network)
	{0xFF000000, 0x0A000000},       //  10.x.x.x (private address range)
	{0xFF000000, 0x7F000000},       // 127.x.x.x (loopback)
	{0xFFFF0000, 0xA9FE0000},       // 169.254.x.x (link-local self-configured addresses)
	{0xFFF00000, 0xAC100000},       // 172.(16-31).x.x (private address range)
	{0xFFFF0000, 0xC0A80000},       // 192.168.x.x (private address range)
	{0,0}
};

static NSString * StringFromIPv4Addr (UInt32);




@interface PGPortMapperBonjour ()
@property (readwrite) SInt32 error;
@property (readwrite) UInt32 rawPublicAddress;
@property (copy) NSString* publicAddress;
@property (readwrite) unsigned short publicPort;
@property (readonly) void* _service;
- (void) priv_disconnect;
@end





@implementation PGPortMapperBonjour

@synthesize publicAddress = _publicAddress;
@synthesize rawPublicAddress = _rawPublicAddress;
@synthesize publicPort = _publicPort;
@synthesize error = _error;
@synthesize _service = _service;
@synthesize mapTCP = _mapTCP;
@synthesize mapUDP = _mapUDP;
@synthesize desiredPublicPort = _desiredPublicPort;

/**
 *
 *
 */
- (id)initWithPrivatePort:(UInt16)privatePort publicPort:(UInt16)publicPort handler:(void (^)(PGPortMapperBonjour*))handler;
{
	self = [super init];
	
	if (self) {
		_port = privatePort;
		_publicPort = publicPort;
		_mapTCP = TRUE;
		mHandler = [handler copy];
	}
	
	return self;
}

/**
 *
 *
 */
- (void)dealloc
{
	if (_service)
		[self priv_disconnect];
}

/**
 *
 *
 */
- (void)finalize
{
	if (_service)
		[self priv_disconnect];
	
	[super finalize];
}

/**
 *
 *
 */
- (BOOL)isMapped
{
	return _rawPublicAddress && _rawPublicAddress != [[self class] rawLocalAddress];
}

/**
 * Called whenever the port mapping changes (see comment for callback, below.)
 *
 */
- (void)priv_portMapStatus:(DNSServiceErrorType)errorCode publicAddress:(UInt32)rawPublicAddress publicPort:(UInt16)publicPort
{
	NSLog(@"%s..", __PRETTY_FUNCTION__);
	
	if (errorCode)
		Log(@"Port-mapping callback got error %i",errorCode);
	else if ( publicPort == 0 && _desiredPublicPort != 0 ) {
		Log(@"Port-mapping callback reported no mapping available");
		errorCode = kDNSServiceErr_NATPortMappingUnsupported;
	}
	
	if( errorCode != self.error )
		self.error = errorCode;
	
	if( rawPublicAddress != self.rawPublicAddress ) {
		self.rawPublicAddress = rawPublicAddress;
		self.publicAddress = StringFromIPv4Addr(rawPublicAddress);
	}
	
	if( publicPort != self.publicPort )
		self.publicPort = publicPort;
	
	if (!errorCode)
		NSLog(@"PortMapper: Got %@ :%hu (mapped=%i)", self.publicAddress,self.publicPort,self.isMapped);
	
	if (mHandler)
		mHandler(self);
}

/**
 * Asynchronous callback from DNSServiceNATPortMappingCreate. This is invoked whenever the status of
 * the port mapping changes. All it does is dispatch to the object's 
 * priv_portMapStatus:publicAddress:publicPort: method.
 */
static void
portMapCallback (
								 DNSServiceRef                    sdRef,
								 DNSServiceFlags                  flags,
								 uint32_t                         interfaceIndex,
								 DNSServiceErrorType              errorCode,
								 uint32_t                         publicAddress,    /* four byte IPv4 address in network byte order */
								 DNSServiceProtocol               protocol,
								 uint16_t                         privatePort,
								 uint16_t                         publicPort,       /* may be different than the requested port */
								 uint32_t                         ttl,              /* may be different than the requested ttl */
								 void                             *context
								 )
{
	@try {
		[(__bridge PGPortMapperBonjour *)context priv_portMapStatus:errorCode publicAddress: publicAddress publicPort: ntohs(publicPort)];  // port #s in network byte order!
	}
	@catch (NSException *exception) {
		NSLog(@"PortMapper caught exception: %@", exception);
	}
}


/**
 * CFSocket callback, informing us that _socket has data available, which means that the DNS service
 * has an incoming result to be processed. This will end up invoking the portMapCallback.
 */
static void
serviceCallback (CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *clientCallBackInfo)
{
	PGPortMapperBonjour *mapper = (__bridge PGPortMapperBonjour *)clientCallBackInfo;
	DNSServiceRef service = mapper._service;
	DNSServiceErrorType err = DNSServiceProcessResult(service);
	
	if (err) {
		[mapper priv_portMapStatus: err publicAddress: 0 publicPort: 0];
		[mapper priv_disconnect];
	}
}

/**
 * Converts a raw IPv4 address to an NSString in dotted-quad notation
 *
 */
static NSString *
StringFromIPv4Addr (UInt32 ipv4Addr)
{
	if (ipv4Addr != 0) {
		const UInt8* addrBytes = (const UInt8*)&ipv4Addr;
		return [NSString stringWithFormat: @"%u.%u.%u.%u",
						(unsigned)addrBytes[0],(unsigned)addrBytes[1],
						(unsigned)addrBytes[2],(unsigned)addrBytes[3]];
	}
	else
		return nil;
}    

/**
 *
 *
 */
- (BOOL)open
{
	NSAssert(!_service,@"Already open");
	
	// Create the DNSService:
	DNSServiceProtocol protocol = 0;
	
	if ( _mapTCP )
		protocol |= kDNSServiceProtocol_TCP;
	
	if ( _mapUDP )
		protocol |= kDNSServiceProtocol_UDP;
	
	self.error = DNSServiceNATPortMappingCreate((DNSServiceRef*)&_service, 
																							0 /*flags*/, 
																							0 /*interfaceIndex*/, 
																							protocol,
																							htons(_port),
																							htons(_desiredPublicPort),
																							0 /*ttl*/,
																							&portMapCallback, 
																							(__bridge void *)self);
	
	if ( _error ) {
		Log(@"Error %i creating port mapping",_error);
		return NO;
	}
	
	// Wrap a CFSocket around the service's socket:
	CFSocketContext ctxt = { 0, (__bridge void *)self, CFRetain, CFRelease, NULL };
	
	_socket = CFSocketCreateWithNative(NULL, DNSServiceRefSockFD(_service), kCFSocketReadCallBack, &serviceCallback, &ctxt);
	
	if( _socket ) {
		CFSocketSetSocketFlags(_socket, CFSocketGetSocketFlags(_socket) & ~kCFSocketCloseOnInvalidate);
		// Attach the socket to the runloop so the serviceCallback will be invoked:
		_socketSource = CFSocketCreateRunLoopSource(NULL, _socket, 0);
		
		if (_socketSource)
			CFRunLoopAddSource(CFRunLoopGetCurrent(), _socketSource, kCFRunLoopCommonModes);
	}
	
	if( _socketSource ) {
		Log(@"Opening PortMapper");
		return YES;
	} else {
		Log(@"Failed to open PortMapper");
		[self close];
		_error = kDNSServiceErr_Unknown;
		return NO;
	}
}

/**
 *
 *
 */
- (BOOL)waitTillOpened
{
	if( ! _socketSource )
		if( ! [self open] )
			return NO;
	
	// Run the runloop until there's either an error or a result:
	while( _error==0 && _publicAddress==nil )
		if (FALSE == [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate distantFuture]])
			break;
	
	return (_error==0);
}

/**
 * Close down, but _without_ clearing the 'error' property
 *
 */
- (void) priv_disconnect
{
	if( _socketSource ) {
		CFRunLoopSourceInvalidate(_socketSource);
		CFRelease(_socketSource);
		_socketSource = NULL;
	}
	
	if( _socket ) {
		CFSocketInvalidate(_socket);
		CFRelease(_socket);
		_socket = NULL;
	}
	
	if( _service ) {
		Log(@"Deleting port mapping");
		DNSServiceRefDeallocate(_service);
		_service = NULL;
		self.rawPublicAddress = 0;
		self.publicAddress = nil;
		self.publicPort = 0;
	}
}

/**
 *
 *
 */
- (void)close
{
	[self priv_disconnect];
	self.error = 0;
}





#pragma mark - Helpers

/**
 *
 *
 */
+ (UInt32)rawLocalAddress
{
	// getifaddrs returns a linked list of interface entries;
	// find the first active non-loopback interface with IPv4:
	UInt32 address = 0;
	struct ifaddrs *interfaces;
	if( getifaddrs(&interfaces) == 0 ) {
		struct ifaddrs *interface;
		for( interface=interfaces; interface; interface=interface->ifa_next ) {
			if( (interface->ifa_flags & IFF_UP) && ! (interface->ifa_flags & IFF_LOOPBACK) ) {
				const struct sockaddr_in *addr = (const struct sockaddr_in*) interface->ifa_addr;
				if( addr && addr->sin_family==AF_INET ) {
					address = addr->sin_addr.s_addr;
					break;
				}
			}
		}
		freeifaddrs(interfaces);
	}
	return address;
}

/**
 *
 *
 */
+ (NSString*)localAddress
{
	return StringFromIPv4Addr( [self rawLocalAddress] );
}

/**
 *
 *
 */
+ (BOOL)localAddressIsPrivate
{
	UInt32 address = ntohl([self rawLocalAddress]);
	int i;
	for( i=0; kPrivateRanges[i].mask; i++ )
		if( (address & kPrivateRanges[i].mask) == kPrivateRanges[i].value )
			return YES;
	return NO;
}

/**
 * To find our public IP address, open a PortMapper with no port or protocols. This will cause the 
 * DNSService to look up our public address without creating a mapping.
 */
+ (NSString *)publicAddress
{
	NSString *addr = nil;
	PGPortMapperBonjour *mapper = [[self alloc] initWithPrivatePort:0 publicPort:0 handler:nil];
	
	mapper.mapTCP = mapper.mapUDP = NO;
	
	if ([mapper waitTillOpened])
		addr = mapper.publicAddress;
	
	[mapper close];
	
	return addr;
}

@end
