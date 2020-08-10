/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ABI39_0_0RCTAppState.h"

#import <ABI39_0_0FBReactNativeSpec/ABI39_0_0FBReactNativeSpec.h>
#import <ABI39_0_0React/ABI39_0_0RCTAssert.h>
#import <ABI39_0_0React/ABI39_0_0RCTBridge.h>
#import <ABI39_0_0React/ABI39_0_0RCTEventDispatcher.h>
#import <ABI39_0_0React/ABI39_0_0RCTUtils.h>

#import "ABI39_0_0CoreModulesPlugins.h"

static NSString *ABI39_0_0RCTCurrentAppState()
{
  static NSDictionary *states;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    states = @{@(UIApplicationStateActive) : @"active", @(UIApplicationStateBackground) : @"background"};
  });

  if (ABI39_0_0RCTRunningInAppExtension()) {
    return @"extension";
  }

  return states[@(ABI39_0_0RCTSharedApplication().applicationState)] ?: @"unknown";
}

@interface ABI39_0_0RCTAppState () <NativeAppStateSpec>
@end

@implementation ABI39_0_0RCTAppState {
  NSString *_lastKnownState;
}

ABI39_0_0RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

- (ABI39_0_0facebook::ABI39_0_0React::ModuleConstants<JS::NativeAppState::Constants>)constantsToExport
{
  return (ABI39_0_0facebook::ABI39_0_0React::ModuleConstants<JS::NativeAppState::Constants>)[self getConstants];
}

- (ABI39_0_0facebook::ABI39_0_0React::ModuleConstants<JS::NativeAppState::Constants>)getConstants
{
  return ABI39_0_0facebook::ABI39_0_0React::typedConstants<JS::NativeAppState::Constants>({
      .initialAppState = ABI39_0_0RCTCurrentAppState(),
  });
}

#pragma mark - Lifecycle

- (NSArray<NSString *> *)supportedEvents
{
  return @[ @"appStateDidChange", @"memoryWarning" ];
}

- (void)startObserving
{
  for (NSString *name in @[
         UIApplicationDidBecomeActiveNotification,
         UIApplicationDidEnterBackgroundNotification,
         UIApplicationDidFinishLaunchingNotification,
         UIApplicationWillResignActiveNotification,
         UIApplicationWillEnterForegroundNotification
       ]) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAppStateDidChange:)
                                                 name:name
                                               object:nil];
  }

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleMemoryWarning)
                                               name:UIApplicationDidReceiveMemoryWarningNotification
                                             object:nil];
}

- (void)stopObserving
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)invalidate
{
  [self stopObserving];
}

#pragma mark - App Notification Methods

- (void)handleMemoryWarning
{
  if (self.bridge) {
    [self sendEventWithName:@"memoryWarning" body:nil];
  }
}

- (void)handleAppStateDidChange:(NSNotification *)notification
{
  NSString *newState;

  if ([notification.name isEqualToString:UIApplicationWillResignActiveNotification]) {
    newState = @"inactive";
  } else if ([notification.name isEqualToString:UIApplicationWillEnterForegroundNotification]) {
    newState = @"background";
  } else {
    newState = ABI39_0_0RCTCurrentAppState();
  }

  if (![newState isEqualToString:_lastKnownState]) {
    _lastKnownState = newState;
    if (self.bridge) {
      [self sendEventWithName:@"appStateDidChange" body:@{@"app_state" : _lastKnownState}];
    }
  }
}

#pragma mark - Public API

/**
 * Get the current background/foreground state of the app
 */
ABI39_0_0RCT_EXPORT_METHOD(getCurrentAppState : (ABI39_0_0RCTResponseSenderBlock)callback error : (__unused ABI39_0_0RCTResponseSenderBlock)error)
{
  callback(@[ @{@"app_state" : ABI39_0_0RCTCurrentAppState()} ]);
}

- (std::shared_ptr<ABI39_0_0facebook::ABI39_0_0React::TurboModule>)
    getTurboModuleWithJsInvoker:(std::shared_ptr<ABI39_0_0facebook::ABI39_0_0React::CallInvoker>)jsInvoker
                  nativeInvoker:(std::shared_ptr<ABI39_0_0facebook::ABI39_0_0React::CallInvoker>)nativeInvoker
                     perfLogger:(id<ABI39_0_0RCTTurboModulePerformanceLogger>)perfLogger
{
  return std::make_shared<ABI39_0_0facebook::ABI39_0_0React::NativeAppStateSpecJSI>(self, jsInvoker, nativeInvoker, perfLogger);
}

@end

Class ABI39_0_0RCTAppStateCls(void)
{
  return ABI39_0_0RCTAppState.class;
}
