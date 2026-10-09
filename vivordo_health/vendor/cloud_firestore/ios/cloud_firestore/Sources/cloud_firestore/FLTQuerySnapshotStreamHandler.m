// Copyright 2021 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import FirebaseFirestore;
#if __has_include(<firebase_core/FLTFirebasePluginRegistry.h>)
#import <firebase_core/FLTFirebasePluginRegistry.h>
#else
#import <FLTFirebasePluginRegistry.h>
#endif

#import "include/cloud_firestore/Private/FLTFirebaseFirestoreUtils.h"
#import "include/cloud_firestore/Private/FLTFirebaseFirestoreWriter.h"
#import "include/cloud_firestore/Private/FLTQuerySnapshotStreamHandler.h"
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

@interface FLTQuerySnapshotStreamHandler ()
@property(readwrite, strong) id<FIRListenerRegistration> listenerRegistration;
@property(nonatomic) dispatch_queue_t snapshotQueue;
@end

@implementation FLTQuerySnapshotStreamHandler

- (instancetype)initWithFirestore:(FIRFirestore *)firestore
                            query:(FIRQuery *)query
           includeMetadataChanges:(BOOL)includeMetadataChanges
          serverTimestampBehavior:(FIRServerTimestampBehavior)serverTimestampBehavior
                           source:(FIRListenSource)source {
  self = [super init];
  if (self) {
    _firestore = firestore;
    _query = query;
    _includeMetadataChanges = includeMetadataChanges;
    _serverTimestampBehavior = serverTimestampBehavior;
    _source = source;
    _snapshotQueue = dispatch_queue_create("io.flutter.plugins.firebase.firestore.query_snapshot",
                                           DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
  FIRQuery *query = self.query;

  if (query == nil) {
    return [FlutterError
        errorWithCode:@"sdk-error"
              message:@"An error occurred while parsing query arguments, see native logs for more "
                      @"information. Please report this issue."
              details:nil];
  }

  id listener = ^(FIRQuerySnapshot *_Nullable snapshot, NSError *_Nullable error) {
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
      dispatch_async(self.snapshotQueue, ^{
        // Emit the Pigeon object directly; the Pigeon-aware codec serializes nested
        // `InternalDocumentSnapshot` / `InternalDocumentChange` / `InternalSnapshotMetadata`
        // with their proper type codes. Pigeon 26 no longer flattens nested types
        // via `toList`.
        InternalQuerySnapshot *pigeonSnapshot =
            [FirestorePigeonParser toPigeonQuerySnapshot:snapshot
                                 serverTimestampBehavior:self.serverTimestampBehavior];
        // Vivordo patch: encode here, on this serial background queue, instead
        // of inside events() on the main thread, where re-encoding whole
        // metrics windows on every write stalled the UI.
        FLTEncodedEventValue *encoded = FLTEncodeEventValue(pigeonSnapshot);
        NSString *label =
            snapshot.documents.firstObject.reference.parent.collectionID ?: @"(empty)";
        unsigned long docs = snapshot.documents.count;
        unsigned long changes = snapshot.documentChanges.count;
        dispatch_async(dispatch_get_main_queue(), ^{
          os_log_t log = FLTDeliveryLog();
          os_signpost_id_t signpost = os_signpost_id_generate(log);
          os_signpost_interval_begin(log, signpost, "Firestore query",
                                     "%{public}@ docs=%lu changes=%lu", label, docs, changes);
          events(encoded);
          os_signpost_interval_end(log, signpost, "Firestore query");
        });
      });
    }
  };

  FIRSnapshotListenOptions *options = [[FIRSnapshotListenOptions alloc] init];
  FIRSnapshotListenOptions *optionsWithSourceAndMetadata = [[options
      optionsWithIncludeMetadataChanges:_includeMetadataChanges] optionsWithSource:_source];

  self.listenerRegistration = [query addSnapshotListenerWithOptions:optionsWithSourceAndMetadata
                                                           listener:listener];

  return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
  [self.listenerRegistration remove];
  self.listenerRegistration = nil;

  return nil;
}

@end
