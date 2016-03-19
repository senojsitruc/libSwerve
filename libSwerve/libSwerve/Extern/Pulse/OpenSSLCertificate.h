//
// Created by Stefan on 04/01/15.
//

#import <Foundation/Foundation.h>

@interface OpenSSLCertificate : NSObject

- (instancetype)initWithEndDate:(NSDate*)endDate bits:(NSUInteger)bits label:(NSString *)label serial:(long)serial;
- (instancetype)initWithDays:(NSUInteger)days bits:(NSUInteger)bits label:(NSString *)label serial:(long)serial;

/**
 * This method attempts to create a self signed certificate using the settings
 * from the initializer. This could potentially fail in many ways. The return value
 * indicates whether it has succeeded. If not, this instance _cannot_ be reused; any
 * repeated calls to this method will always return `false`. Instead, create a new
 * instance when you need to try again.
 */
- (BOOL)tryCreateSelfSignedCertificate:(NSError**)error;

- (NSData*)createPKCS12BlobWithPassword:(NSString*)password error:(NSError**)error;

+ (NSUInteger)daysFromDate:(NSDate*)fromDate untilDate:(NSDate*)untilDate;

@end
