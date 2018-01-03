//
//  LoopMeVideoManager.m
//  LoopMeSDK
//
//  Created by Kogda Bogdan on 2/19/15.
//
//

#import <stdlib.h>
#import "LoopMeVideoManager.h"
#import "LoopMeError.h"
#import "LoopMeErrorEventSender.h"
#import "LoopMeGlobalSettings.h"

NSInteger const kLoopMeVideoLoadTimeOutInterval = 180;
NSTimeInterval const kLoopMeVideoCacheExpiredTime = (-1*32*60*60);

@interface LoopMeVideoManager ()
<
    NSURLConnectionDataDelegate
>

@property (nonatomic, strong) id ETag;
@property (nonatomic, strong) NSMutableURLRequest *request;
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSMutableData *videoData;
@property (nonatomic, strong) NSTimer *videoLoadingTimeout;

@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, strong) NSString *videoPath;
@property (nonatomic, assign) long long contentLength;
@property (nonatomic, assign, getter=isDidLoadSent) BOOL didLoadSent;

- (NSString *)assetsDirectory;

@end

@implementation LoopMeVideoManager

#pragma mark - Life Cycle

- (instancetype)initWithVideoPath:(NSString *)videoPath delegate:(id<LoopMeVideoManagerDelegate>)delegate {
    self = [super init];
    if (self) {
        _videoPath = videoPath;
        _delegate = delegate;
        [self clearOldCacheFiles];
    }
    return self;
}

#pragma mark - Private

- (NSString *)assetsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = paths[0];
    return [documentsDirectory stringByAppendingPathComponent:@"lm_assets/"];
}

- (void)invalidateTimers {
    [self.videoLoadingTimeout invalidate];
    self.videoLoadingTimeout = nil;
}

#pragma mark - Public

- (void)loadVideoWithURL:(NSURL *)URL {
    self.videoURL = URL;
    self.videoLoadingTimeout = [NSTimer scheduledTimerWithTimeInterval:kLoopMeVideoLoadTimeOutInterval target:self selector:@selector(timeOut) userInfo:nil repeats:NO];
    self.request = [NSMutableURLRequest requestWithURL:URL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:kLoopMeVideoLoadTimeOutInterval];
    self.connection = [NSURLConnection connectionWithRequest:self.request delegate:self];
}

- (void)cancel {
    [self.connection cancel];
    self.connection = nil;
    [self invalidateTimers];
}

- (void)clearOldCacheFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSString *directoryPath = self.assetsDirectory;
    NSDirectoryEnumerator* enumerator = [fm enumeratorAtPath:directoryPath];
    
    NSString *file;
    while (file = [enumerator nextObject]) {

        NSDate *creationDate = [[fm attributesOfItemAtPath:[directoryPath stringByAppendingPathComponent:file] error:nil] fileCreationDate];
        NSDate *yesterDay = [[NSDate date] dateByAddingTimeInterval:kLoopMeVideoCacheExpiredTime];
        
        if ([creationDate compare:yesterDay] == NSOrderedAscending) {
            [fm removeItemAtPath:[directoryPath stringByAppendingPathComponent:file] error:nil];
        }
    }
}


- (void)cacheVideoData:(NSData *)data {
    NSString *directoryPath = self.assetsDirectory;
    
    [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                              withIntermediateDirectories:NO
                                               attributes:nil
                                                    error:nil];
    
    NSString *dataPath = [directoryPath stringByAppendingPathComponent:self.videoPath];
    NSURL *URL = [NSURL fileURLWithPath:dataPath];
    
    if([data writeToFile:dataPath atomically:NO]) {
        if (!self.isDidLoadSent) {
            [self.delegate videoManager:self didLoadVideo:URL];
            self.didLoadSent = YES;
        }
    } else {
        [self.delegate videoManager:self didFailLoadWithError:[LoopMeError errorForStatusCode:LoopMeErrorCodeWrirtingToDisk]];
    }
}

- (BOOL)hasCachedURL:(NSURL *)URL {
    if (!self.videoPath) {
        return NO;
    }
    
    NSString *videoPath = [[self assetsDirectory] stringByAppendingPathComponent:URL.lastPathComponent];
    return [[NSFileManager defaultManager] fileExistsAtPath:videoPath];
}

- (NSURL *)videoFileURL {
    NSString *dataPath = [[self assetsDirectory] stringByAppendingPathComponent:self.videoPath];
    NSURL *URL = [NSURL fileURLWithPath:dataPath];
    return URL;
}

- (void)failedInitPlayer: (NSURL *)url {
    self.didLoadSent = NO;
    [self loadVideoWithURL:url];
}

- (void)reconect {
    [self.request setValue:self.ETag forHTTPHeaderField:@"If-Range"];
    
    [self.request setValue:[NSString stringWithFormat:@"bytes=%lu-%lld", (unsigned long)self.videoData.length, self.contentLength] forHTTPHeaderField:@"Range"];
    self.connection = [NSURLConnection connectionWithRequest:self.request delegate:self];
}

- (void)timeOut {
    [self cancel];
    [LoopMeErrorEventSender sendError:LoopMeEventErrorTypeBadAsset errorMessage:[NSString stringWithFormat:@"Time out for video: %@", self.videoURL.absoluteString] appkey:self.delegate.appKey];
    NSError *error = [LoopMeError errorForStatusCode:LoopMeErrorCodeVideoDownloadTimeout];
    [self.delegate videoManager:self didFailLoadWithError:error];
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    if ([response respondsToSelector:@selector(statusCode)]) {
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        if (statusCode == 200) {
            self.contentLength = [response expectedContentLength];
            self.ETag = [[(NSHTTPURLResponse *)response allHeaderFields] valueForKey:@"ETag"];
            self.videoData = [NSMutableData data];
            return;
        }
        if (statusCode != 206) {
            [LoopMeErrorEventSender sendError:LoopMeEventErrorTypeBadAsset errorMessage:[NSString stringWithFormat:@"response code %ld: %@",(long)statusCode, self.videoURL.absoluteString] appkey:self.delegate.appKey];
    
            [self.delegate videoManager:self didFailLoadWithError:[LoopMeError errorForStatusCode:statusCode]];
        }
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.videoData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if (error.code == -1005) {
        [self reconect];
        return;
    }

    if (error.code == NSURLErrorTimedOut) {
        [LoopMeErrorEventSender sendError:LoopMeEventErrorTypeBadAsset errorMessage:[NSString stringWithFormat:@"Time out for: %@", self.videoURL.absoluteString] appkey:self.delegate.appKey];
    } else {
        [LoopMeErrorEventSender sendError:LoopMeEventErrorTypeBadAsset errorMessage:[NSString stringWithFormat:@"Error code %ld: %@", (long)error.code, self.videoURL.absoluteString] appkey:self.delegate.appKey];
    }
    
    [self.delegate videoManager:self didFailLoadWithError:error];
    [self invalidateTimers];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self cacheVideoData:[NSData dataWithData:self.videoData]];
    self.videoData = nil;
    self.connection = nil;
    [self invalidateTimers];
}

- (NSURLRequest *)connection: (NSURLConnection *)connection
             willSendRequest: (NSURLRequest *)request
            redirectResponse: (NSURLResponse *)redirectResponse {
    if (redirectResponse) {
        NSURL *newURL = [request URL];
        NSMutableURLRequest *newRequest = [self.request mutableCopy];
        [newRequest setURL: newURL];
        return newRequest;
    } else {
        return request;
    }
}

@end
