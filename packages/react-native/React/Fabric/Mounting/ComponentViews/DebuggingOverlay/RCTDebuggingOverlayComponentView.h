/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTUIKit.h> // [macOS]

#import <React/RCTViewComponentView.h>

#import <react/renderer/components/rncore/RCTComponentViewHelpers.h>

@interface RCTDebuggingOverlayComponentView : RCTViewComponentView <RCTDebuggingOverlayViewProtocol>

@end