//
//  LoopMeAdDisplayController.m
//  LoopMeSDK
//
//  Created by Dmitriy Lihachov on 8/21/12.
//  Copyright (c) 2013 LoopMe. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <LOOMoatMobileAppKit/LOOMoatAnalytics.h>
#import <LOOMoatMobileAppKit/LOOMoatWebTracker.h>

#import "LoopMeAdDisplayController.h"
#import "LoopMeAdConfiguration.h"
#import "LoopMeAdWebView.h"
#import "LoopMeDefinitions.h"
#import "LoopMeDestinationDisplayController.h"
#import "LoopMeJSClient.h"
#import "LoopMeMRAIDClient.h"
#import "LoopMeVideoClient.h"
#import "NSURL+LoopMeAdditions.h"
#import "LoopMeError.h"
#import "LoopMeLogging.h"
#import "LoopMe360ViewController.h"
#import "LoopMeInterstitialViewController.h"
#import "LoopMeCloseButton.h"
#import "LoopMeInterstitial.h"
#import "LoopMeErrorEventSender.h"

NSInteger const kLoopMeWebViewLoadingTimeout = 180;
NSString * const kLoopMeShakeNotificationName = @"DeviceShaken";
NSString * const kLoopMeBaseURL = @"http://loopme.me/";

@interface LoopMeAdDisplayController ()
<
    UIWebViewDelegate,
    LoopMeVideoClientDelegate,
    LoopMeJSClientDelegate,
    LoopMeMRAIDClientDelegate,
    LoopMeDestinationDisplayControllerDelegate
>

@property (nonatomic, strong) LoopMeAdWebView *webView;
@property (nonatomic, strong) LoopMeCloseButton *closeButton;
@property (nonatomic, strong) LoopMeJSClient *JSClient;
@property (nonatomic, strong) LoopMeMRAIDClient *mraidClient;
@property (nonatomic, strong) LoopMeVideoClient *videoClient;
@property (nonatomic, strong) LoopMeDestinationDisplayController *destinationDisplayClient;
@property (nonatomic, strong) NSTimer *webViewTimeOutTimer;
@property (nonatomic, strong) LoopMeAdConfiguration *configuration;
@property (nonatomic, strong) NSDictionary *orientationProperties;
@property (nonatomic, assign) CGSize originalSize;

@property (nonatomic, assign, getter=isFirstCallToExpand) BOOL firstCallToExpand;
@property (nonatomic, assign, getter=isUseCustomClose) BOOL useCustomClose;

@property (nonatomic, assign) CGPoint prevLoaction;
@property (nonatomic, strong) UIPanGestureRecognizer *panWebView;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchWebView;

@property (nonatomic, assign) BOOL adDisplayed;
@property (nonatomic, strong) LOOMoatWebTracker *tracker;

- (void)deviceShaken;
- (BOOL)shouldIntercept:(NSURL *)URL
         navigationType:(UIWebViewNavigationType)navigationType;
- (void)interceptURL:(NSURL *)URL;

@end

@implementation LoopMeAdDisplayController

#pragma mark - Properties

- (LoopMeVideoClient *)videoClient {
    if (_videoClient == nil) {
        _videoClient = [[LoopMeVideoClient alloc] initWithDelegate:self];
    }
    return _videoClient;
}

- (LoopMeDestinationDisplayController *)destinationDisplayClient {
    if (_destinationDisplayClient == nil) {
        _destinationDisplayClient = [LoopMeDestinationDisplayController controllerWithDelegate:self];
    }
    return _destinationDisplayClient;
}

- (void)setVisible:(BOOL)visible {
    if (self.adDisplayed && _visible != visible) {
        
        if (_forceHidden) {
            _visible = NO;
        } else {
            _visible = visible;
        }
        
        if (self.configuration.isMraid) {
            NSString *stringBOOL = _visible ? @"true" : @"false";
            [self.mraidClient executeEvent:LoopMeMRAIDFunctions.viewableChange params:@[stringBOOL]];
        }
        
        if (visible && !_forceHidden) {
            [self.JSClient executeEvent:LoopMeEvent.state forNamespace:kLoopMeNamespaceWebview param:LoopMeWebViewState.visible];
        } else {
            [self.JSClient executeEvent:LoopMeEvent.state forNamespace:kLoopMeNamespaceWebview param:LoopMeWebViewState.hidden];
        }
    }
}

- (void)setVisibleNoJS:(BOOL)visibleNoJS {
    if (_visibleNoJS != visibleNoJS) {
        _visibleNoJS = visibleNoJS;
        NSString *stringBOOL = visibleNoJS ? @"true" : @"false";
        if (self.configuration.isMraid) {
            [self.mraidClient executeEvent:LoopMeMRAIDFunctions.viewableChange params:@[stringBOOL]];
        }
        if (_visibleNoJS) {
            [self.videoClient play];
        } else {
            [self.videoClient pause];
        }
    }
}

- (UIButton *)closeButton {
    if (!_closeButton) {
        _closeButton = [[LoopMeCloseButton alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
        _closeButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
        [_closeButton addTarget:self action:@selector(mraidClientDidReceiveCloseCommand:) forControlEvents:UIControlEventTouchUpInside];
    }
    return _closeButton;
}

- (void)setUseCustomClose:(BOOL)useCustomClose {
    _useCustomClose = useCustomClose;
    self.closeButton.hidden = useCustomClose;
}

- (NSString *)appKey {
    if (!_appKey) {
        _appKey = self.delegate.appKey;
    }
    return _appKey;
}

#pragma mark - Life Cycle

- (void)dealloc {
    [_webView stopLoading];
    _webView.delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kLoopMeShakeNotificationName object:nil];
    [_webViewTimeOutTimer invalidate];
    _webViewTimeOutTimer = nil;
}

- (instancetype)initWithDelegate:(id<LoopMeAdDisplayControllerDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _destinationDisplayClient = [LoopMeDestinationDisplayController controllerWithDelegate:self];
        _JSClient = [[LoopMeJSClient alloc] initWithDelegate:self];
        _mraidClient = [[LoopMeMRAIDClient alloc] initWithDelegate:self];
        
        //if frame is zero WebView display content incorrect
        _webView = [[LoopMeAdWebView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
        _webView.delegate = self;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(deviceShaken) name:kLoopMeShakeNotificationName object:nil];
        
        _firstCallToExpand = YES;
    }
    return self;
}

#pragma mark - Private

- (void)deviceShaken {
    [self.JSClient setShake];
}

- (BOOL)shouldIntercept:(NSURL *)URL
         navigationType:(UIWebViewNavigationType)navigationType {
    if (navigationType == UIWebViewNavigationTypeLinkClicked) {
        if ([self.delegate respondsToSelector:@selector(adDisplayControllerDidReceiveTap:)]) {
            [self.delegate adDisplayControllerDidReceiveTap:self];
        }
        return YES;
    }
    return NO;
}

- (void)interceptURL:(NSURL *)URL {
    [self.destinationDisplayClient displayDestinationWithURL:URL];
}

- (void)cancelWebView {
    [self.webView stopLoading];
    
    NSError *error = [LoopMeError errorForStatusCode:LoopMeErrorCodeHTMLRequestTimeOut];
    if ([self.delegate respondsToSelector:@selector(adDisplayController:didFailToLoadAdWithError:)]) {
        LoopMeLogInfo(@"Ad failed to load: %@", error);
        [self.delegate adDisplayController:self didFailToLoadAdWithError:error];
    }
}

- (void)panWebView:(UIPanGestureRecognizer *)recognizer {
    CGPoint currentLocation = [recognizer locationInView:self.webView];
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.prevLoaction = currentLocation;
    }
    
    LoopMe360ViewController *vc = [self.videoClient viewController360];
    [vc pan:currentLocation prevLocation:self.prevLoaction];
    self.prevLoaction = currentLocation;
}

- (void)pinchWebView:(UIPinchGestureRecognizer *)recognizer {
    LoopMe360ViewController *vc = [self.videoClient viewController360];
    [vc handlePinchGesture:recognizer];
}

- (void)setOrientation:(NSDictionary *)orientationProperties forConfiguration:(LoopMeAdConfiguration *)configuration {
    if (orientationProperties) {
        configuration.allowOrientationChange = [orientationProperties[@"allowOrientationChange"] boolValue];
        if ([orientationProperties[@"forceOrientation"] isEqualToString:@"portrait"]) {
            configuration.orientation = LoopMeAdOrientationPortrait;
        } else if ([orientationProperties[@"forceOrientation"] isEqualToString:@"landscape"]) {
            configuration.orientation = LoopMeAdOrientationLandscape;
        }
    }
}

- (void)setExpandProperties:(NSDictionary *)properties forConfiguration:(LoopMeAdConfiguration *)configuration {
    if (properties) {
        struct LoopMeMRAIDExpandProperties expandProperties;
        expandProperties.height = [properties[@"height"] intValue];
        expandProperties.width = [properties[@"width"] intValue];
        expandProperties.useCustomClose = [properties[@"useCustomClose"] boolValue];
        
        configuration.expandProperties = expandProperties;
    }
}

- (CGRect)frameForCloseButton:(CGRect)superviewFrame {
    return CGRectMake(superviewFrame.size.width - 50, 0, 50, 50);
}

- (void)setUpJSContext {
    id log = ^(JSValue *msg) {
        LoopMeLogDebug(@"JS: %@", msg);
    };
    
    JSContext *jsContext = [self.webView valueForKeyPath:@"documentView.webView.mainFrame.javaScriptContext"];
    jsContext[@"console"][@"error"] = log;
    
    __weak LoopMeAdDisplayController *wekSelf = self;
    [jsContext setExceptionHandler:^(JSContext *context, JSValue *value) {
        [LoopMeErrorEventSender sendError:LoopMeEventErrorTypeJS errorMessage:[value toString] appkey:wekSelf.appKey];
    }];
}

- (UIInterfaceOrientation)calculatePreferredOrientstion:(BOOL)allowOrientationChange orientationProperties:(NSDictionary *)orientationProperties {
    
    UIInterfaceOrientation preferredOrientation;
    UIInterfaceOrientation currentInterfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    
    if (allowOrientationChange) {
        preferredOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    } else {
        if ([orientationProperties[@"forceOrientation"] isEqualToString:@"portrait"]) {
            if (UIInterfaceOrientationIsPortrait(currentInterfaceOrientation)) {
                // this will accomodate both portrait and portrait upside down
                preferredOrientation = currentInterfaceOrientation;
            } else {
                preferredOrientation = UIInterfaceOrientationPortrait;
            }
        } else if ([orientationProperties[@"forceOrientation"] isEqualToString:@"landscape"]) {
            if (UIInterfaceOrientationIsLandscape(currentInterfaceOrientation)) {
                // this will accomodate both landscape left and landscape right
                preferredOrientation = currentInterfaceOrientation;
            } else {
                preferredOrientation = UIInterfaceOrientationLandscapeLeft;
            }
        } else {
            preferredOrientation = currentInterfaceOrientation;
        }
    }
    return preferredOrientation;
}

- (CGRect)adjustFrame:(CGRect)frame {
    CGRect adjustedFrame = frame;
    if ([self.delegate isKindOfClass:[LoopMeInterstitial class]]) {
        if ((self.configuration.orientation == LoopMeAdOrientationLandscape && adjustedFrame.size.width < adjustedFrame.size.height) || (self.configuration.orientation == LoopMeAdOrientationPortrait && adjustedFrame.size.width > adjustedFrame.size.height)) {
            adjustedFrame = CGRectMake(adjustedFrame.origin.x, adjustedFrame.origin.y, adjustedFrame.size.height, adjustedFrame.size.width);
        }
    } else if([self.delegate respondsToSelector:@selector(isMaximizedControllerIsPresented)] && [self.delegate performSelector:@selector(isMaximizedControllerIsPresented)]) {
        adjustedFrame = CGRectMake(adjustedFrame.origin.x, adjustedFrame.origin.y, adjustedFrame.size.height, adjustedFrame.size.width);
    }
    return adjustedFrame;
}

#pragma mark - Public

- (void)setExpandProperties:(LoopMeAdConfiguration *)configuration {
    [self setExpandProperties:[self.mraidClient getExpandProperties] forConfiguration:configuration];
}

- (void)loadConfiguration:(LoopMeAdConfiguration *)configuration {
    self.configuration = configuration;
    
    if ([self.configuration useTracking:LoopMeTrackerName.moat]) {
        LOOMoatOptions *options = [[LOOMoatOptions alloc] init];
        options.debugLoggingEnabled = YES;
        [[LOOMoatAnalytics sharedInstance] startWithOptions:options];
        
        if (!self.tracker) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.tracker = [LOOMoatWebTracker trackerWithWebComponent:self.webView];
            });
        }
    }

    if (configuration.isMraid) {
        
        NSURL *bundleURL = [[NSBundle mainBundle] URLForResource:@"LoopMeResources" withExtension:@"bundle"];
        if (!bundleURL) {
            [self.delegate adDisplayController:self didFailToLoadAdWithError:[LoopMeError errorForStatusCode:LoopMeErrorCodeNoMraidJS]];
            return;
        }
        
        NSBundle *resourcesBundle = [NSBundle bundleWithURL:bundleURL];
        NSString *jsPath = [resourcesBundle pathForResource:@"mraid" ofType:@"js"];
        NSString *mraidjs = [NSString stringWithContentsOfFile:jsPath encoding:NSUTF8StringEncoding error:NULL];
        
        if (mraidjs) {
            mraidjs = [mraidjs stringByAppendingString:@"</script>"];
            mraidjs = [@"<script>" stringByAppendingString:mraidjs];
            
            NSMutableString *html = [configuration.adResponseHTMLString mutableCopy];
            
            NSRange range = [html rangeOfString:@"<script>"];
            [html insertString:mraidjs atIndex:range.location];
            configuration.adResponseHTMLString = html;
        } else {
            [self.delegate adDisplayController:self didFailToLoadAdWithError:[LoopMeError errorForStatusCode:LoopMeErrorCodeNoMraidJS]];
            return;
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setUpJSContext];
        [self.webView loadHTMLString:configuration.adResponseHTMLString
                             baseURL:[NSURL URLWithString:kLoopMeBaseURL]];
    });
    
    self.webViewTimeOutTimer = [NSTimer scheduledTimerWithTimeInterval:kLoopMeWebViewLoadingTimeout target:self selector:@selector(cancelWebView) userInfo:nil repeats:NO];
}

- (void)displayAd {
    if ([self.configuration useTracking:LoopMeTrackerName.moat]) {
        [self.tracker startTracking];
    }
    self.adDisplayed = YES;
    self.videoClient.viewController = [self.delegate viewControllerForPresentation];
    self.webView.frame = self.delegate.containerView.bounds;
    
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    
    CGRect adjustedFrame = [self adjustFrame:self.webView.frame];
    
    [self.videoClient adjustViewToFrame:adjustedFrame];
    [self.delegate.containerView addSubview:self.webView];
    [self.delegate.containerView bringSubviewToFront:self.webView];
    [self.videoClient willAppear];
    
    if (self.configuration.isMraid) {
        
        self.originalSize = adjustedFrame.size;
        
        NSString *placementType = [self.delegate isKindOfClass:[LoopMeInterstitial class]] ? @"interstitial" : @"inline";
        [self.mraidClient executeEvent:LoopMeMRAIDFunctions.setPlacementType params:@[placementType]];
        [self.mraidClient executeEvent:LoopMeMRAIDFunctions.setDefaultPosition params:@[@0, @0, @(adjustedFrame.size.width), @(adjustedFrame.size.height)]];
        
        CGSize windowSize = [[UIApplication sharedApplication] keyWindow].bounds.size;
        [self.mraidClient executeEvent:LoopMeMRAIDFunctions.setMaxSize params:@[@(windowSize.width),@(windowSize.height)]];
        [self.mraidClient executeEvent:LoopMeMRAIDFunctions.setScreenSize params:@[@(windowSize.width), @(windowSize.height)]];
        
        [self.mraidClient executeEvent:LoopMeMRAIDFunctions.stateChange params:@[LoopMeMRAIDState.defaultt]];
        [self.mraidClient executeEvent:LoopMeMRAIDFunctions.ready params:nil];
        
        self.closeButton.frame = [self frameForCloseButton:adjustedFrame];
        [self.delegate.containerView addSubview:self.closeButton];
    }

    self.panWebView = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panWebView:)];
    [self.webView addGestureRecognizer:self.panWebView];
    
    self.pinchWebView = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchWebView:)];
    [self.webView addGestureRecognizer:self.pinchWebView];
}

- (void)closeAd {
    if ([self.configuration useTracking:LoopMeTrackerName.moat]) {
        [self.tracker stopTracking];
    }
    self.visible = NO;
    self.adDisplayed = NO;
    [self.JSClient executeEvent:LoopMeEvent.state forNamespace:kLoopMeNamespaceWebview param:LoopMeWebViewState.closed];
    [self.webView removeGestureRecognizer:self.panWebView];
    [self.webView removeGestureRecognizer:self.pinchWebView];
    [self.webView stopLoading];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView loadHTMLString:@"" baseURL:nil];
        [self stopHandlingRequests];
    });

}

- (void)layoutSubviews {
    [self.videoClient adjustViewToFrame:self.webView.bounds];
}

- (void)layoutSubviewsToFrame:(CGRect)frame {
    [self.videoClient adjustViewToFrame:frame];
}

- (void)stopHandlingRequests {
    [self.destinationDisplayClient cancel];
    self.destinationDisplayClient = nil;
    [self.videoClient cancel];
    self.videoClient = nil;
    self.destinationDisplayClient = nil;
    [self.webViewTimeOutTimer invalidate];
}

- (void)moveView:(BOOL)hideWebView {
    [self.videoClient moveView];
    [self displayAd];
    self.webView.hidden = hideWebView;
}

- (void)expandReporting {
    if (self.configuration.isMraid) {
        [self.mraidClient executeEvent:LoopMeMRAIDFunctions.stateChange params:@[LoopMeMRAIDState.expanded]];
        CGRect adjustedFrame = [self adjustFrame:self.webView.frame];
         [self.mraidClient executeEvent:LoopMeMRAIDFunctions.sizeChange params:@[@(adjustedFrame.size.width), @(adjustedFrame.size.height)]];
    }
    self.closeButton.hidden = self.configuration.expandProperties.useCustomClose;
    [self.JSClient setFullScreenModeEnabled:YES];
}

- (void)collapseReporting {
    self.closeButton.hidden = self.isUseCustomClose;
    [self.JSClient setFullScreenModeEnabled:NO];
}

- (void)resizeTo:(CGSize)size {
    if (self.configuration.isMraid) {
        [self.mraidClient executeEvent:LoopMeMRAIDFunctions.sizeChange params:@[@(size.width),@(size.height)]];
        if ([self.delegate respondsToSelector:@selector(adDisplayController:willResizeAd:)]) {
            [self.delegate adDisplayController:self willResizeAd:size];
        }
    }
}

- (void)setOrientationProperties:(NSDictionary *)orientationProperties {
    if (orientationProperties) {
        _orientationProperties = orientationProperties;
    }
    BOOL allowOrientationChange = [self.orientationProperties[@"allowOrientationChange"] isEqualToString:@"true"] ? YES : NO;
    UIInterfaceOrientation preferredOrientation = [self calculatePreferredOrientstion:allowOrientationChange orientationProperties:self.orientationProperties];
    LoopMeAdOrientation adOrientation;
    if (UIInterfaceOrientationIsPortrait(preferredOrientation)) {
        adOrientation = LoopMeAdOrientationPortrait;
    } else {
        adOrientation = LoopMeAdOrientationLandscape;
    }
    
    if ([[self.delegate viewControllerForPresentation] isKindOfClass:[LoopMeInterstitialViewController class]]) {
        [(LoopMeInterstitialViewController *)[self.delegate viewControllerForPresentation] setAllowOrientationChange:allowOrientationChange];
        [(LoopMeInterstitialViewController *)[self.delegate viewControllerForPresentation] setOrientation:adOrientation];
        [(LoopMeInterstitialViewController *)[self.delegate viewControllerForPresentation] forceChangeOrientation];
    }
    
    if ([self.delegate respondsToSelector:@selector(adDisplayController:allowOrientationChange:orientation:)]) {
        [self.delegate adDisplayController:self allowOrientationChange:allowOrientationChange orientation:adOrientation];
    }
}

#pragma mark - UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request
 navigationType:(UIWebViewNavigationType)navigationType {
    NSURL *URL = [request URL];
    if ([self.JSClient shouldInterceptURL:URL]) {
        [self.JSClient executeEvent:LoopMeEvent.isNativeCallFinished forNamespace:kLoopMeNamespaceWebview param:@YES paramBOOL:YES];
        [self.JSClient processURL:URL];
        return NO;
    } else if ([self.mraidClient shouldInterceptURL:URL]){
        [self.mraidClient processURL:URL];
    } else if ([self shouldIntercept:URL navigationType:navigationType]) {
        [self interceptURL:URL];
        return NO;
    }
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if (self.configuration.isMraid) {
        [self.mraidClient setSupports];
        [self setOrientation:[self.mraidClient getOrientationProperties] forConfiguration:self.configuration];
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    LoopMeLogDebug(@"WebView received an error %@", error);
    if (error.code == -1004) {
        if ([self.delegate respondsToSelector:@selector(adDisplayController:didFailToLoadAdWithError:)]) {
            [self.delegate adDisplayController:self didFailToLoadAdWithError:error];
        }
    }
}

#pragma mark - LoopMeDestinationDisplayControllerDelegate

- (UIViewController *)viewControllerForPresentingModalView {
    return [self.delegate viewControllerForPresentation];
}

- (void)destinationDisplayControllerWillLeaveApplication:(LoopMeDestinationDisplayController *)destinationDisplayController {
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerWillLeaveApplication:)]) {
        [self.delegate adDisplayControllerWillLeaveApplication:self];
    }
}

- (void)destinationDisplayControllerWillPresentModal:(LoopMeDestinationDisplayController *)destinationDisplayController {
    self.visible = NO;
    self.destinationIsPresented = YES;
}

- (void)destinationDisplayControllerDidDismissModal:(LoopMeDestinationDisplayController *)destinationDisplayController {
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerDidDismissModal:)]) {
        [self.delegate adDisplayControllerDidDismissModal:self];
    }
    self.destinationIsPresented = NO;
}

#pragma mark - JSClientDelegate 

- (UIWebView *)webViewTransport {
    return self.webView;
}

- (id<LoopMeVideoCommunicatorProtocol>)videoCommunicator {
    return self.videoClient;
}

- (void)JSClientDidReceiveSuccessCommand:(LoopMeJSClient *)client {
    LoopMeLogInfo(@"Ad was successfully loaded");
    [self.webViewTimeOutTimer invalidate];
    _webViewTimeOutTimer = nil;
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerDidFinishLoadingAd:)]) {
        [self.delegate adDisplayControllerDidFinishLoadingAd:self];
    }
}

- (void)JSClientDidReceiveFailCommand:(LoopMeJSClient *)client {
    NSError *error = [LoopMeError errorForStatusCode:LoopMeErrorCodeSpecificHost];
    LoopMeLogInfo(@"Ad failed to load: %@", error);
    [self.webViewTimeOutTimer invalidate];
    _webViewTimeOutTimer = nil;
    if ([self.delegate respondsToSelector:@selector(adDisplayController:didFailToLoadAdWithError:)]) {
        [self.delegate adDisplayController:self didFailToLoadAdWithError:error];
    }
}

- (void)JSClientDidReceiveCloseCommand:(LoopMeJSClient *)client {
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerShouldCloseAd:)]) {
        [self.delegate adDisplayControllerShouldCloseAd:self];
    }
}

- (void)JSClientDidReceiveVibrateCommand:(LoopMeJSClient *)client {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)JSClientDidReceiveFulLScreenCommand:(LoopMeJSClient *)client fullScreen:(BOOL)expand {
    if (self.isFirstCallToExpand) {
        expand = NO;
        self.firstCallToExpand = NO;
    }
    
    if (expand) {
        if ([self.delegate respondsToSelector:@selector(adDisplayControllerWillExpandAd:)]) {
            [self.videoClient setGravity:AVLayerVideoGravityResizeAspect];
            [self.delegate adDisplayControllerWillExpandAd:self];
        }
    } else {
        if ([self.delegate respondsToSelector:@selector(adDisplayControllerWillCollapse:)]) {
            [self.delegate adDisplayControllerWillCollapse:self];
        }
    }
}

#pragma mark - MRAIDClientDelegate

- (void)mraidClient:(LoopMeMRAIDClient *)client shouldOpenURL:(NSURL *)URL {
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerDidReceiveTap:)]) {
        [self.delegate adDisplayControllerDidReceiveTap:self];
    }
    [self interceptURL:URL];
}

- (void)mraidClient:(LoopMeMRAIDClient *)client useCustomClose:(BOOL)useCustomCLose {
    self.useCustomClose = useCustomCLose;
}

- (void)mraidClient:(LoopMeMRAIDClient *)client sholdPlayVideo:(NSURL *)URL {
    [self.videoClient playVideo:URL];
}

- (void)mraidClient:(LoopMeMRAIDClient *)client setOrientationProperties:(NSDictionary *)orientationProperties {
    [self setOrientationProperties:orientationProperties];
}

- (void)mraidClientDidReceiveCloseCommand:(LoopMeMRAIDClient *)client {
    if ([[self.mraidClient getState] isEqualToString:LoopMeMRAIDState.resized]) {
        [self resizeTo:self.originalSize];
        [self.mraidClient executeEvent:LoopMeMRAIDFunctions.stateChange params:@[LoopMeMRAIDState.defaultt]];
        return;
    }
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerShouldCloseAd:)]) {
        [self.delegate adDisplayControllerShouldCloseAd:self];
    }
}

- (void)mraidClientDidReceiveExpandCommand:(LoopMeMRAIDClient *)client {
    if ([self.delegate respondsToSelector:@selector(adDisplayControllerWillExpandAd:)]) {
        [self.delegate adDisplayControllerWillExpandAd:self];
    }
}

- (void)mraidClientDidResizeAd:(LoopMeMRAIDClient *)client {
    NSDictionary *resizeProperties = [self.mraidClient getResizeProperties];
    CGFloat width = [[resizeProperties objectForKey:@"width"] floatValue];
    CGFloat height = [[resizeProperties objectForKey:@"height"] floatValue];
    CGSize newSize = CGSizeMake(width, height);
    
    [self resizeTo:newSize];
}

#pragma mark - VideoClientDelegate

- (UIViewController *)viewControllerForPresentation {
    return [self.delegate viewControllerForPresentation];
}

- (id<LoopMeJSCommunicatorProtocol>)JSCommunicator {
    return self.JSClient;
}

- (void)videoClientDidReachEnd:(LoopMeVideoClient *)client {
    LoopMeLogInfo(@"Video ad did reach end");
    if ([self.delegate respondsToSelector:
         @selector(adDisplayControllerVideoDidReachEnd:)]) {
        [self.delegate adDisplayControllerVideoDidReachEnd:self];
    }
}

- (void)videoClient:(LoopMeVideoClient *)client didFailToLoadVideoWithError:(NSError *)error {
    LoopMeLogInfo(@"Did fail to load video ad");
    if ([self.delegate respondsToSelector:
         @selector(adDisplayController:didFailToLoadAdWithError:)]) {
        [self.delegate adDisplayController:self didFailToLoadAdWithError:error];
    }
}

- (void)videoClient:(LoopMeVideoClient *)client setupView:(UIView *)view {
    view.frame = self.delegate.containerView.bounds;
    [[self.delegate containerView] insertSubview:view belowSubview:self.webView];
}

- (void)videoClientDidBecomeActive:(LoopMeVideoClient *)client {
    [self layoutSubviews];
    if (/*!self.isDestIsShown && ![self.videoClient playerReachedEnd] && !self.isEndCardClicked && */self.visible) {
        [self.videoClient play];
    }
}

- (BOOL)useMoatTracking {
    return [_configuration useTracking:LoopMeTrackerName.moat];
}

- (BOOL)isVideo360 {
    return [_configuration isV360];
}

@end
