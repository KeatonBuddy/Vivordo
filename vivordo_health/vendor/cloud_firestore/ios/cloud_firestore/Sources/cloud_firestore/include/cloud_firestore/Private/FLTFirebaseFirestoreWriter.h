// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

#import <Foundation/Foundation.h>

@interface FLTFirebaseFirestoreWriter : FlutterStandardWriter
- (void)writeValue:(id)value;
@end

/// Vivordo patch: an event payload already encoded off the main thread; the
/// event channel's codec writes these bytes verbatim.
@interface FLTEncodedEventValue : NSObject
@property(nonatomic, readonly) NSData *bytes;
@end

/// Encodes `value` exactly as the event channel codec would inside a success
/// envelope, so the main thread only copies bytes. Safe on any thread for
/// immutable values such as Pigeon snapshots.
FLTEncodedEventValue *FLTEncodeEventValue(id value);
