//
// Created by Stefan on 04/01/15.
//

#import "OpenSSLCertificate.h"
#import <openssl/pkcs12.h>
#import <openssl/x509v3.h>

// static unsigned char *const DEFAULT_CERTIFICATE_COMMON_NAME = (unsigned char * const)"us.curtisjones.libSwerve.001";

static const int MAX_PASS_SIZE = 1024;

@interface OpenSSLCertificate ()
@property(nonatomic) NSUInteger days;
@property(nonatomic) NSUInteger bits;
@property(nonatomic) EVP_PKEY *pkey;
@property(nonatomic) X509 *x509;
@property(nonatomic) long serial;
@property(nonatomic) NSString *label;
@end

@implementation OpenSSLCertificate

- (instancetype)initWithEndDate:(NSDate*)endDate bits:(NSUInteger)bits label:(NSString *)label serial:(long)serial {
    NSUInteger days = 0;
    if (endDate) {
        days = [self.class daysFromDate:[NSDate date] untilDate:endDate];
    }
	return [self initWithDays:days bits:bits label:label serial:serial];
}

- (instancetype)initWithDays:(NSUInteger)days bits:(NSUInteger)bits label:(NSString *)label serial:(long)serial {
    if (self = [super init]) {
        self.days = days;
        self.bits = bits;
			self.label = label;
        self.serial = serial;
        CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_ON);
    }
    return self;
}

- (void)dealloc {
    [self cleanup];
}


- (BOOL)tryCreateSelfSignedCertificate:(NSError**)error {
    if (self.pkey || self.x509) {
        if (error) {
					NSLog(@"Failed. certCreateAlreadyCalled");
					return FALSE;
//          *error = [[PulseError alloc] initWithCode:[PulseError certCreateAlreadyCalled] userInfo:nil];
        }
        return NO;
    }
    
    self.pkey = EVP_PKEY_new();
    self.x509 = X509_new();
    
    RSA *rsa = RSA_generate_key((int)self.bits, RSA_F4, NULL, NULL);
    int returnValue = RSA_check_key(rsa);
    if (returnValue != 1) {
        if (error) {
//          *error = [[PulseError alloc] initWithCode:[PulseError rsaKeyGenError] userInfo:@{@"openSSLError":@(returnValue)}];
					return FALSE;
        }
        return NO;
    }

    if (!EVP_PKEY_assign_RSA(self.pkey, rsa)) {
        if (error) {
//          *error = [[PulseError alloc] initWithCode:[PulseError rsaKeyAssignError] userInfo:nil];
					return FALSE;
        }
        return NO;
    }
    rsa = NULL;

    X509_set_version(self.x509, 2);

    ASN1_INTEGER_set(X509_get_serialNumber(self.x509), self.serial);
    X509_gmtime_adj(X509_get_notBefore(self.x509), 0);
    X509_gmtime_adj(X509_get_notAfter(self.x509), (long) (60 * 60 * 24 * self.days));
    X509_set_pubkey(self.x509, self.pkey);

    X509_NAME *name = X509_get_subject_name(self.x509);

//  X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, DEFAULT_CERTIFICATE_COMMON_NAME, -1, -1, 0);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, (const unsigned char *)self.label.UTF8String, -1, -1, 0);

    /* Its self signed so set the issuer name to be the same as the
      * subject.
     */
    X509_set_issuer_name(self.x509, name);

    if (![self addExtension:NID_basic_constraints value:"critical,CA:TRUE"]) {
        if (error) {
//          *error = [[PulseError alloc] initWithCode:[PulseError addExtensionError] userInfo:nil];
					return FALSE;
        }
        return NO;
    }
    if (![self addExtension:NID_key_usage value:"critical,digitalSignature,keyEncipherment"]) {
        if (error) {
//            *error = [[PulseError alloc] initWithCode:[PulseError addExtensionError] userInfo:nil];
					return FALSE;
        }
        return NO;
    }
    if (![self addExtension:NID_ext_key_usage value:"critical,serverAuth,clientAuth"]) {
        if (error) {
//            *error = [[PulseError alloc] initWithCode:[PulseError addExtensionError] userInfo:nil];
					return FALSE;
        }
        return NO;
    }

    int signResult = X509_sign(self.x509, self.pkey, EVP_md5());
    if (signResult == 0) {
        if (error) {
//            *error = [[PulseError alloc] initWithCode:[PulseError signError] userInfo:nil];
					return FALSE;
        }
        return NO;
    }
    
    return YES;
}

+ (NSUInteger)daysFromDate:(NSDate*)fromDate untilDate:(NSDate*)untilDate {
    NSUInteger seconds = (NSUInteger) [untilDate timeIntervalSinceDate:fromDate];
    return seconds / (3600 *24);
}

- (BOOL)addExtension:(int)nid value:(char *)value {
    X509_EXTENSION *ex;
    X509V3_CTX ctx;
    /* This sets the 'context' of the extensions. */
    /* No configuration database */
    X509V3_set_ctx_nodb(&ctx);
    /* Issuer and subject certs: both the target since it is self signed,
     * no request and no CRL
     */
    X509V3_set_ctx(&ctx, self.x509, self.x509, NULL, NULL, 0);
    ex = X509V3_EXT_conf_nid(NULL, &ctx, nid, value);
    if (!ex) {
        return NO;
    }

    X509_add_ext(self.x509, ex, -1);
    X509_EXTENSION_free(ex);
    return YES;

}

- (NSData*)createPKCS12BlobWithPassword:(NSString*)password error:(NSError**)error {
    if (!self.pkey || !self.x509 || ![password canBeConvertedToEncoding:NSASCIIStringEncoding]) {
        if (error) {
//            *error = [[PulseError alloc] initWithCode:[PulseError calledMoreThanOneError] userInfo:nil];
					return nil;
}
        return nil;
    }
    
    OpenSSL_add_all_ciphers();
    OpenSSL_add_all_digests();

    char *pwd = malloc(sizeof(char) * MAX_PASS_SIZE);
    if (![password getCString:pwd maxLength:MAX_PASS_SIZE-1 encoding:NSASCIIStringEncoding]) {
        if (error) {
//            *error = [[PulseError alloc] initWithCode:[PulseError invalidPasswordError] userInfo:nil];
					return nil;
        }
        free(pwd);
        return nil;
    }

    PKCS12 *pkcs12 = PKCS12_create(pwd, "libSwerve", self.pkey, self.x509, NULL, 0, 0, 0, 0, 0);
    if (!pkcs12) {
        if (error) {
//            *error = [[PulseError alloc] initWithCode:[PulseError pkcs12ExportError] userInfo:nil];
					return nil;
        }
        free(pwd);
        return nil;
    }

    int pkcs12Length = i2d_PKCS12(pkcs12, NULL);
    if (pkcs12Length <= 0) {
        if (error) {
//            *error = [[PulseError alloc] initWithCode:[PulseError pkcs12ExportError] userInfo:nil];
					return nil;
        }
        PKCS12_free(pkcs12);
        free(pwd);
        return nil;
    }
    unsigned char *buffer = malloc(sizeof(unsigned char)* pkcs12Length);
    unsigned char *tmp = buffer;
    i2d_PKCS12(pkcs12, &tmp);
    NSAssert(tmp-buffer == pkcs12Length, @"Sizes must match");
    NSData *pkcs12Data = [NSData dataWithBytes:buffer length:(NSUInteger) pkcs12Length];
    
    PKCS12_free(pkcs12);
    free(buffer);
    free(pwd);
    
    return pkcs12Data;
}

- (void)cleanup {
    if (self.x509) {
        X509_free(self.x509);
        self.x509 = NULL;
    }
    if (self.pkey) {
        EVP_PKEY_free(self.pkey);
        self.pkey = NULL;
    }
}

@end
