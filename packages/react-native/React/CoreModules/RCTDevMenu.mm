/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTDevMenu.h>

#import <FBReactNativeSpec/FBReactNativeSpec.h>
#import <React/RCTBridge+Private.h>
#import <React/RCTBundleURLProvider.h>
#import <React/RCTDefines.h>
#import <React/RCTDevSettings.h>
#if !TARGET_OS_OSX // [macOS]
#import <React/RCTKeyCommands.h>
#endif // [macOS]
#import <React/RCTLog.h>
#import <React/RCTReloadCommand.h>
#import <React/RCTUtils.h>
#import "CoreModulesPlugins.h"

#if RCT_DEV_MENU
#if RCT_ENABLE_INSPECTOR
#import <React/RCTInspectorDevServerHelper.h>
#endif

@protocol RCTDevMenuItemProvider
- (RCTDevMenuItem *)devMenuItem;
@end

NSString *const RCTShowDevMenuNotification = @"RCTShowDevMenuNotification";

#if !TARGET_OS_OSX // [macOS]

// [macOS
typedef void (*MotionEndedWithEventImpType)(id self, SEL selector, UIEventSubtype motion, UIEvent *event);
static MotionEndedWithEventImpType RCTOriginalUIWindowMotionEndedWithEventImp = nil;
// macOS]

@implementation UIWindow (RCTDevMenu)

- (void)RCT_motionEnded:(__unused UIEventSubtype)motion withEvent:(UIEvent *)event
{
  RCTOriginalUIWindowMotionEndedWithEventImp(self, @selector(motionEnded:withEvent:), motion, event); // [macOS]
  if (event.subtype == UIEventSubtypeMotionShake) {
    [[NSNotificationCenter defaultCenter] postNotificationName:RCTShowDevMenuNotification object:nil];
  }
}

@end

#endif // [macOS]

@implementation RCTDevMenuItem {
  RCTDevMenuItemTitleBlock _titleBlock;
  dispatch_block_t _handler;
}

- (instancetype)initWithTitleBlock:(RCTDevMenuItemTitleBlock)titleBlock handler:(dispatch_block_t)handler
{
  if ((self = [super init])) {
    _titleBlock = [titleBlock copy];
    _handler = [handler copy];
  }
  return self;
}

RCT_NOT_IMPLEMENTED(-(instancetype)init)

+ (instancetype)buttonItemWithTitleBlock:(NSString * (^)(void))titleBlock handler:(dispatch_block_t)handler
{
  return [[self alloc] initWithTitleBlock:titleBlock handler:handler];
}

+ (instancetype)buttonItemWithTitle:(NSString *)title handler:(dispatch_block_t)handler
{
  return [[self alloc]
      initWithTitleBlock:^NSString * {
        return title;
      }
                 handler:handler];
}

- (void)callHandler
{
  if (_handler) {
    _handler();
  }
}

- (NSString *)title
{
  if (_titleBlock) {
    return _titleBlock();
  }
  return nil;
}

@end

#if !TARGET_OS_OSX // [macOS]

typedef void (^RCTDevMenuAlertActionHandler)(UIAlertAction *action);

#endif // [macOS]

@interface RCTDevMenu () <RCTBridgeModule, RCTInvalidating, NativeDevMenuSpec>

@end

@implementation RCTDevMenu {
#if !TARGET_OS_OSX // [macOS]
  UIAlertController *_actionSheet;
#endif // [macOS]
  NSMutableArray<RCTDevMenuItem *> *_extraMenuItems;
}

@synthesize bridge = _bridge;
@synthesize moduleRegistry = _moduleRegistry;
@synthesize callableJSModules = _callableJSModules;
@synthesize bundleManager = _bundleManager;

RCT_EXPORT_MODULE()

+ (void)initialize
{
#if !TARGET_OS_OSX // [macOS]
  // We're swizzling here because it's poor form to override methods in a category,
  RCTOriginalUIWindowMotionEndedWithEventImp = (MotionEndedWithEventImpType) RCTSwapInstanceMethods([UIWindow class], @selector(motionEnded:withEvent:), @selector(RCT_motionEnded:withEvent:)); // [macOS]
#endif // [macOS]
}

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (instancetype)init
{
  if ((self = [super init])) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showOnShake)
                                                 name:RCTShowDevMenuNotification
                                               object:nil];
    _extraMenuItems = [NSMutableArray new];

    [self registerHotkeys];
  }
  return self;
}

- (void)registerHotkeys
{
#if TARGET_OS_SIMULATOR || TARGET_OS_MACCATALYST
  RCTKeyCommands *commands = [RCTKeyCommands sharedInstance];
  __weak __typeof(self) weakSelf = self;

  // Toggle debug menu
  [commands registerKeyCommandWithInput:@"d"
                          modifierFlags:UIKeyModifierCommand
                                 action:^(__unused UIKeyCommand *command) {
                                   [weakSelf toggle];
                                 }];

  // Toggle element inspector
  [commands registerKeyCommandWithInput:@"i"
                          modifierFlags:UIKeyModifierCommand
                                 action:^(__unused UIKeyCommand *command) {
                                   [(RCTDevSettings *)[weakSelf.moduleRegistry moduleForName:"DevSettings"]
                                       toggleElementInspector];
                                 }];

  // Reload in normal mode
  [commands registerKeyCommandWithInput:@"n"
                          modifierFlags:UIKeyModifierCommand
                                 action:^(__unused UIKeyCommand *command) {
                                   [(RCTDevSettings *)[weakSelf.moduleRegistry moduleForName:"DevSettings"]
                                       setIsDebuggingRemotely:NO];
                                 }];
#endif
}

- (void)unregisterHotkeys
{
#if TARGET_OS_SIMULATOR || TARGET_OS_MACCATALYST
  RCTKeyCommands *commands = [RCTKeyCommands sharedInstance];

  [commands unregisterKeyCommandWithInput:@"d" modifierFlags:UIKeyModifierCommand];
  [commands unregisterKeyCommandWithInput:@"i" modifierFlags:UIKeyModifierCommand];
  [commands unregisterKeyCommandWithInput:@"n" modifierFlags:UIKeyModifierCommand];
#endif
}

- (BOOL)isHotkeysRegistered
{
#if TARGET_OS_SIMULATOR || TARGET_OS_MACCATALYST
  RCTKeyCommands *commands = [RCTKeyCommands sharedInstance];

  return [commands isKeyCommandRegisteredForInput:@"d" modifierFlags:UIKeyModifierCommand] &&
      [commands isKeyCommandRegisteredForInput:@"i" modifierFlags:UIKeyModifierCommand] &&
      [commands isKeyCommandRegisteredForInput:@"n" modifierFlags:UIKeyModifierCommand];
#else
  return NO;
#endif
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

- (void)invalidate
{
  _presentedItems = nil;
#if !TARGET_OS_OSX // [macOS]
  [_actionSheet dismissViewControllerAnimated:YES
                                   completion:^(void){
                                   }];
#endif // [macOS]
}

- (void)showOnShake
{
  if ([((RCTDevSettings *)[_moduleRegistry moduleForName:"DevSettings"]) isShakeToShowDevMenuEnabled]) {
    NSMutableArray<RCTPlatformWindow *> *windows = [NSMutableArray new]; // [macOS]
#if !TARGET_OS_OSX // [macOS]
    for (UIWindowScene *scene in RCTSharedApplication().connectedScenes) {
      [windows addObjectsFromArray:scene.windows];
    }
#endif // [macOS]
    for (RCTPlatformWindow *window in windows) { // [macOS]
      NSString *recursiveDescription = [window valueForKey:@"recursiveDescription"];
      if ([recursiveDescription containsString:@"RCTView"]) {
        [self show];
        return;
      }
    }
  }
}

#if !TARGET_OS_OSX // [macOS]
- (void)toggle
{
  if (_actionSheet.isBeingPresented || _actionSheet.beingDismissed) {
    return;
  }
  if (_actionSheet) {
    [_actionSheet dismissViewControllerAnimated:YES
                                     completion:^(void) {
                                       self->_actionSheet = nil;
                                     }];

  } else {
    [self show];
  }
}

- (BOOL)isActionSheetShown
{
  return _actionSheet != nil;
}
#endif // [macOS]

- (void)addItem:(NSString *)title handler:(void (^)(void))handler
{
  [self addItem:[RCTDevMenuItem buttonItemWithTitle:title handler:handler]];
}

- (void)addItem:(RCTDevMenuItem *)item
{
  [_extraMenuItems addObject:item];
}

- (void)setDefaultJSBundle
{
  [[RCTBundleURLProvider sharedSettings] resetToDefaults];
  self->_bundleManager.bundleURL = [[RCTBundleURLProvider sharedSettings] jsBundleURLForFallbackExtension:nil];
  RCTTriggerReloadCommandListeners(@"Dev menu - reset to default");
}

- (NSArray<RCTDevMenuItem *> *)_menuItemsToPresent
{
  NSMutableArray<RCTDevMenuItem *> *items = [NSMutableArray new];

  // Add built-in items
  __weak RCTDevSettings *devSettings = [_moduleRegistry moduleForName:"DevSettings"];
  __weak RCTDevMenu *weakSelf = self;
  __weak RCTBundleManager *bundleManager = _bundleManager;

  [items addObject:[RCTDevMenuItem buttonItemWithTitle:@"Reload"
                                               handler:^{
                                                 RCTTriggerReloadCommandListeners(@"Dev menu - reload");
                                               }]];

  if (!devSettings.isProfilingEnabled) {
#if RCT_ENABLE_INSPECTOR
    if (devSettings.isDeviceDebuggingAvailable) {
      // On-device JS debugging (CDP). Render action to open debugger frontend.
      BOOL isDisconnected = RCTInspectorDevServerHelper.isPackagerDisconnected;
      NSString *title = isDisconnected
          ? [NSString stringWithFormat:@"Connect to %@ to debug JavaScript", RCT_PACKAGER_NAME]
          : @"Open DevTools";
      RCTDevMenuItem *item = [RCTDevMenuItem
          buttonItemWithTitle:title
                      handler:^{
                        [RCTInspectorDevServerHelper
                                openDebugger:bundleManager.bundleURL
                            withErrorMessage:
                                @"Failed to open debugger. Please check that the dev server is running and reload the app."];
                      }];
      [item setDisabled:isDisconnected];
      [items addObject:item];
    }
#endif
  }

  [items addObject:[RCTDevMenuItem
                       buttonItemWithTitleBlock:^NSString * {
                         return @"Toggle Element Inspector";
                       }
                       handler:^{
                         [devSettings toggleElementInspector];
                       }]];

  if (devSettings.isHotLoadingAvailable) {
    [items addObject:[RCTDevMenuItem
                         buttonItemWithTitleBlock:^NSString * {
                           // Previously known as "Hot Reloading". We won't use this term anymore.
                           return devSettings.isHotLoadingEnabled ? @"Disable Fast Refresh" : @"Enable Fast Refresh";
                         }
                         handler:^{
                           devSettings.isHotLoadingEnabled = !devSettings.isHotLoadingEnabled;
                         }]];
  }

#if !TARGET_OS_OSX // [macOS]
  id perfMonitorItemOpaque = [_moduleRegistry moduleForName:"PerfMonitor"];
  SEL devMenuItem = @selector(devMenuItem);
  if ([perfMonitorItemOpaque respondsToSelector:devMenuItem]) {
    RCTDevMenuItem *perfMonitorItem = [perfMonitorItemOpaque devMenuItem];
    [items addObject:perfMonitorItem];
  }
#endif // [macOS]

  [items
      addObject:[RCTDevMenuItem
                    buttonItemWithTitleBlock:^NSString * {
                      return @"Configure Bundler";
                    }
                    handler:^{
#if !TARGET_OS_OSX // [macOS]
                      UIAlertController *alertController = [UIAlertController
                          alertControllerWithTitle:@"Configure Bundler"
                                           message:@"Provide a custom bundler address, port, and entrypoint."
                                    preferredStyle:UIAlertControllerStyleAlert];
                      [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                        textField.placeholder = @"0.0.0.0";
                      }];
                      [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                        textField.placeholder = @"8081";
                      }];
                      [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                        textField.placeholder = @"index";
                      }];
                      [alertController
                          addAction:[UIAlertAction
                                        actionWithTitle:@"Apply Changes"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
                                                  NSArray *textfields = alertController.textFields;
                                                  UITextField *ipTextField = textfields[0];
                                                  UITextField *portTextField = textfields[1];
                                                  UITextField *bundleRootTextField = textfields[2];
                                                  NSString *bundleRoot = bundleRootTextField.text;
                                                  if (ipTextField.text.length == 0 && portTextField.text.length == 0) {
                                                    [weakSelf setDefaultJSBundle];
                                                    return;
                                                  }
                                                  NSNumberFormatter *formatter = [NSNumberFormatter new];
                                                  formatter.numberStyle = NSNumberFormatterDecimalStyle;
                                                  NSNumber *portNumber =
                                                      [formatter numberFromString:portTextField.text];
                                                  if (portNumber == nil) {
                                                    portNumber = [NSNumber numberWithInt:RCT_METRO_PORT];
                                                  }
                                                  [RCTBundleURLProvider sharedSettings].jsLocation = [NSString
                                                      stringWithFormat:@"%@:%d", ipTextField.text, portNumber.intValue];
                                                  if (bundleRoot.length == 0) {
                                                    [bundleManager resetBundleURL];
                                                  } else {
                                                    bundleManager.bundleURL = [[RCTBundleURLProvider sharedSettings]
                                                        jsBundleURLForBundleRoot:bundleRoot];
                                                  }

                                                  RCTTriggerReloadCommandListeners(@"Dev menu - apply changes");
                                                }]];
                      [alertController addAction:[UIAlertAction actionWithTitle:@"Reset to Default"
                                                                          style:UIAlertActionStyleDefault
                                                                        handler:^(__unused UIAlertAction *action) {
                                                                          [weakSelf setDefaultJSBundle];
                                                                        }]];
                      [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                                          style:UIAlertActionStyleCancel
                                                                        handler:^(__unused UIAlertAction *action) {
                                                                          return;
                                                                        }]];
                      [RCTPresentedViewController() presentViewController:alertController animated:YES completion:NULL];
#else // [macOS
                      NSAlert *alert = [NSAlert new];
                      [alert setMessageText:@"Change packager location"];
                      [alert setInformativeText:@"Input packager IP, port and entrypoint"];
                      [alert addButtonWithTitle:@"Use bundled JS"];
                      [alert setAlertStyle:NSWarningAlertStyle];
                      [alert beginSheetModalForWindow:[NSApp keyWindow] completionHandler:nil];
#endif // macOS]
                    }]];

  [items addObjectsFromArray:_extraMenuItems];
  return items;
}

RCT_EXPORT_METHOD(show)
{
#if !TARGET_OS_OSX // [macOS]
  if (_actionSheet || RCTRunningInAppExtension()) {
    return;
  }

  NSString *bridgeDescription = _bridge.bridgeDescription;
  NSString *description =
      bridgeDescription.length > 0 ? [NSString stringWithFormat:@"Running %@", bridgeDescription] : nil;

  // On larger devices we don't have an anchor point for the action sheet
  UIAlertControllerStyle style = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone
      ? UIAlertControllerStyleActionSheet
      : UIAlertControllerStyleAlert;

  NSString *devMenuType = [self.bridge isKindOfClass:RCTBridge.class] ? @"Bridge" : @"Bridgeless";
  NSString *devMenuTitle = [NSString stringWithFormat:@"React Native Dev Menu (%@)", devMenuType];

  _actionSheet = [UIAlertController alertControllerWithTitle:devMenuTitle message:description preferredStyle:style];

  NSArray<RCTDevMenuItem *> *items = [self _menuItemsToPresent];
  for (RCTDevMenuItem *item in items) {
    UIAlertAction *action = [UIAlertAction actionWithTitle:item.title
                                                     style:UIAlertActionStyleDefault
                                                   handler:[self alertActionHandlerForDevItem:item]];
    [action setEnabled:!item.isDisabled];
    [_actionSheet addAction:action];
  }

  [_actionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:[self alertActionHandlerForDevItem:nil]]];

  _presentedItems = items;
  [RCTPresentedViewController() presentViewController:_actionSheet animated:YES completion:nil];

#else // [macOS
  NSMenu *menu = [self menu];
  NSWindow *window = [NSApp keyWindow];
  NSEvent *event = [NSEvent mouseEventWithType:NSLeftMouseUp location:CGPointMake(0, 0) modifierFlags:0 timestamp:NSTimeIntervalSince1970 windowNumber:[window windowNumber]  context:nil eventNumber:0 clickCount:0 pressure:0.1];
  [NSMenu popUpContextMenu:menu withEvent:event forView:[window contentView]];
#endif // macOS]

  [_callableJSModules invokeModule:@"RCTNativeAppEventEmitter" method:@"emit" withArgs:@[ @"RCTDevMenuShown" ]];
}

#if !TARGET_OS_OSX // [macOS]
- (RCTDevMenuAlertActionHandler)alertActionHandlerForDevItem:(RCTDevMenuItem *__nullable)item
{
  return ^(__unused UIAlertAction *action) {
    if (item) {
      [item callHandler];
    }

    self->_actionSheet = nil;
  };
}
#else // [macOS
- (NSMenu *)menu
{
  if ([_bridge.devSettings isSecondaryClickToShowDevMenuEnabled]) {
    NSMenu *menu = nil;
    if (_bridge) {
      NSString *desc = _bridge.bridgeDescription;
      if (desc.length == 0) {
        desc = NSStringFromClass([_bridge class]);
      }
      NSString *title = [NSString stringWithFormat:@"React Native: Development\n(%@)", desc];

      menu = [NSMenu new];

      NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc]initWithString:title];
      [attributedTitle setAttributes: @{ NSFontAttributeName : [NSFont menuFontOfSize:0] } range: NSMakeRange(0, [attributedTitle length])];
      NSMenuItem *titleItem = [NSMenuItem new];
      [titleItem setAttributedTitle:attributedTitle];
      [menu addItem:titleItem];

      [menu addItem:[NSMenuItem separatorItem]];

      NSArray<RCTDevMenuItem *> *items = [self _menuItemsToPresent];
      for (RCTDevMenuItem *item in items) {
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[item title] action:@selector(menuItemSelected:) keyEquivalent:@""];
        [menuItem setTarget:self];
        [menuItem setRepresentedObject:item];
        [menu addItem:menuItem];
      }
    }
    return menu;
  }
  return nil;
}

-(void)menuItemSelected:(id)sender
{
  NSMenuItem *menuItem = (NSMenuItem *)sender;
  RCTDevMenuItem *item = (RCTDevMenuItem *)[menuItem representedObject];
  [item callHandler];
}

- (void)setSecondaryClickToShow:(BOOL)secondaryClickToShow
{
  _bridge.devSettings.isSecondaryClickToShowDevMenuEnabled = secondaryClickToShow;
}
#endif // macOS]

#pragma mark - deprecated methods and properties

#define WARN_DEPRECATED_DEV_MENU_EXPORT() \
  RCTLogWarn(@"Using deprecated method %s, use RCTDevSettings instead", __func__)

- (void)setShakeToShow:(BOOL)shakeToShow
{
  ((RCTDevSettings *)[_moduleRegistry moduleForName:"DevSettings"]).isShakeToShowDevMenuEnabled = shakeToShow;
}

- (BOOL)shakeToShow
{
  return ((RCTDevSettings *)[_moduleRegistry moduleForName:"DevSettings"]).isShakeToShowDevMenuEnabled;
}

RCT_EXPORT_METHOD(reload)
{
  WARN_DEPRECATED_DEV_MENU_EXPORT();
  RCTTriggerReloadCommandListeners(@"Unknown from JS");
}

RCT_EXPORT_METHOD(debugRemotely : (BOOL)enableDebug)
{
  WARN_DEPRECATED_DEV_MENU_EXPORT();
  ((RCTDevSettings *)[_moduleRegistry moduleForName:"DevSettings"]).isDebuggingRemotely = enableDebug;
}

RCT_EXPORT_METHOD(setProfilingEnabled : (BOOL)enabled)
{
  WARN_DEPRECATED_DEV_MENU_EXPORT();
  ((RCTDevSettings *)[_moduleRegistry moduleForName:"DevSettings"]).isProfilingEnabled = enabled;
}

- (BOOL)profilingEnabled
{
  return ((RCTDevSettings *)[_moduleRegistry moduleForName:"DevSettings"]).isProfilingEnabled;
}

RCT_EXPORT_METHOD(setHotLoadingEnabled : (BOOL)enabled)
{
  WARN_DEPRECATED_DEV_MENU_EXPORT();
  ((RCTDevSettings *)[_moduleRegistry moduleForName:"DevSettings"]).isHotLoadingEnabled = enabled;
}

- (BOOL)hotLoadingEnabled
{
  return ((RCTDevSettings *)[_moduleRegistry moduleForName:"DevSettings"]).isHotLoadingEnabled;
}

- (void)setHotkeysEnabled:(BOOL)enabled
{
  if (enabled) {
    [self registerHotkeys];
  } else {
    [self unregisterHotkeys];
  }
}

- (BOOL)hotkeysEnabled
{
  return [self isHotkeysRegistered];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeDevMenuSpecJSI>(params);
}

@end

#else // Unavailable when not in dev mode

@interface RCTDevMenu () <NativeDevMenuSpec>
@end

@implementation RCTDevMenu

- (void)show
{
}
- (void)reload
{
}
- (void)addItem:(NSString *)title handler:(dispatch_block_t)handler
{
}
- (void)addItem:(RCTDevMenu *)item
{
}

- (void)debugRemotely:(BOOL)enableDebug
{
}

- (BOOL)isActionSheetShown
{
  return NO;
}
+ (NSString *)moduleName
{
  return @"DevMenu";
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeDevMenuSpecJSI>(params);
}

@end

@implementation RCTDevMenuItem

+ (instancetype)buttonItemWithTitle:(NSString *)title handler:(void (^)(void))handler
{
  return nil;
}
+ (instancetype)buttonItemWithTitleBlock:(NSString * (^)(void))titleBlock handler:(void (^)(void))handler
{
  return nil;
}

@end

#endif

@implementation RCTBridge (RCTDevMenu)

- (RCTDevMenu *)devMenu
{
#if RCT_DEV_MENU
  return [self moduleForClass:[RCTDevMenu class]];
#else
  return nil;
#endif
}

@end

@implementation RCTBridgeProxy (RCTDevMenu)

- (RCTDevMenu *)devMenu
{
#if RCT_DEV_MENU
  return [self moduleForClass:[RCTDevMenu class]];
#else
  return nil;
#endif
}

@end

Class RCTDevMenuCls(void)
{
  return RCTDevMenu.class;
}