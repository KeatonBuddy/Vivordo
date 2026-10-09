// Copyright 2021 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import FirebaseFirestore;
#if __has_include(<firebase_core/FLTFirebasePluginRegistry.h>)
#import <firebase_core/FLTFirebasePluginRegistry.h>
#else
#import <FLTFirebasePluginRegistry.h>
#endif

#import "include/cloud_firestore/Private/FLTDocumentSnapshotStreamHandler.h"
#import "include/cloud_firestore/Private/FLTFirebaseFirestoreUtils.h"
#import "include/cloud_firestore/Private/FirestorePigeonParser.h"
#import "include/cloud_firestore/Public/CustomPigeonHeaderFirestore.h"

#import <os/signpost.h>

// Vivordo patch: names each snapshot delivery in Instruments' Points of
// Interest track, so main-thread encoding stalls can be tied to a listener.
static os_log_t FLTDeliveryLog(void) {
  static os_log_t log;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    log = os_log_create("com.vivordo.firestore", OS_LOG_CATEGORY_POINTS_OF_INTEREST);
  });
  return log;
}

@interface FLTDocumentSnapshotStreamHandler ()
@property(readwrite, strong) id<FIRListenerRegistration> listenerRegistration;
@end

@implementation FLTDocumentSnapshotStreamHandler

- (nonnull instancetype)initWithFirestore:(nonnull FIRFirestore *)firestore
                                reference:(nonnull FIRDocumentReference *)reference
                   includeMetadataChanges:(BOOL)includeMetadataChanges
                  serverTimestampBehavior:(FIRServerTimestampBehavior)serverTimestampBehavior
                                   source:(FIRListenSource)source {
  self = [super init];
  if (self) {
    self.firestore = firestore;
    self.reference = reference;
    self.includeMetadataChanges = includeMetadataChanges;
    self.serverTimestampBehavior = serverTimestampBehavior;
    self.source = source;
  }
  return self;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
  id listener = ^(FIRDocumentSnapshot *snapshot, NSError *_Nullable error) {
    if (error) {
      NSArray *codeAndMessage = [FLTFirebaseFirestoreUtils ErrorCodeAndMessageFromNSError:error];
      NSString *code = codeAndMessage[0];
      NSString *message = codeAndMessage[1];
      NSDictionary *details = @{
        @"code" : code,
        @"message" : message,
      };
      dispatch_async(dispatch_get_main_queue(), ^{
        events([FLTFirebasePlugin createFlutterErrorFromCode:code
                                                     message:message
                                             optionalDetails:details
                                          andOptionalNSError:error]);
      });
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        os_log_t log = FLTDeliveryLog();
        os_signpost_id_t signpost = os_signpost_id_generate(log);
        os_signpost_interval_begin(log, signpost, "Firestore document", "%{public}@",
                                   snapshot.reference.parent.collectionID);
        // Emit the Pigeon object directly; the Pigeon-aware codec on the
        // MessageChannel serializes it end-to-end. Pigeon 26 no longer flattens
        // nested types via `toList`.
        events([FirestorePigeonParser toPigeonDocumentSnapshot:snapshot
                                       serverTimestampBehavior:self.serverTimestampBehavior]);
        os_signpost_interval_end(log, signpost, "Firestore document");
      });
    }
  };

  FIRSnapshotListenOptions *options = [[FIRSnapshotListenOptions alloc] init];
  FIRSnapshotListenOptions *optionsWithSourceAndMetadata = [[options
      optionsWithIncludeMetadataChanges:_includeMetadataChanges] optionsWithSource:_source];

  self.listenerRegistration =
      [_reference addSnapshotListenerWithOptions:optionsWithSourceAndMetadata listener:listener];

  return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
  [self.listenerRegistration remove];
  self.listenerRegistration = nil;

  return nil;
}

@end
