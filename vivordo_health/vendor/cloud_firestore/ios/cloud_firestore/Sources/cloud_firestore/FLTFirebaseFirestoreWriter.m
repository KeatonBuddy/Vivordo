// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import FirebaseFirestore;
@import FirebaseCore;

#import "include/cloud_firestore/Private/FLTFirebaseFirestoreWriter.h"
#import "include/cloud_firestore/Private/FLTFirebaseFirestoreUtils.h"
#import "include/cloud_firestore/Public/FLTFirebaseFirestorePlugin.h"

// Pigeon codec used by the plugin's event channels (FirestoreMessages.g.m).
@interface FirebaseFirestoreHostApiCodecReaderWriter : FlutterStandardReaderWriter
@end

@implementation FLTEncodedEventValue
- (instancetype)initWithBytes:(NSData *)bytes {
  self = [super init];
  if (self) _bytes = bytes;
  return self;
}
@end

FLTEncodedEventValue *FLTEncodeEventValue(id value) {
  static FlutterStandardReaderWriter *readerWriter;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    readerWriter = [[FirebaseFirestoreHostApiCodecReaderWriter alloc] init];
  });
  NSMutableData *data = [NSMutableData data];
  FlutterStandardWriter *writer = [readerWriter writerWithData:data];
  // encodeSuccessEnvelope writes one 0 byte before the value. Writing it here
  // too keeps the codec's 8-byte alignment padding identical once spliced.
  [writer writeByte:0];
  [writer writeValue:value];
  return [[FLTEncodedEventValue alloc]
      initWithBytes:[data subdataWithRange:NSMakeRange(1, data.length - 1)]];
}

static const UInt8 FLTStandardFieldList = 12;
static const UInt8 FLTStandardFieldMap = 13;

@implementation FLTFirebaseFirestoreWriter : FlutterStandardWriter
- (void)writeValue:(id)value {
  if ([value isKindOfClass:[FLTEncodedEventValue class]]) {
    [self writeData:((FLTEncodedEventValue *)value).bytes];
    return;
  }
  // Vivordo patch: snapshot payloads are almost entirely plain values, and
  // each one used to walk every Firestore type check first. On the iOS main
  // thread that was ~28% of hang time, so plain types are handled up front.
  if ([value isKindOfClass:[NSNumber class]]) {
    double number = [(NSNumber *)value doubleValue];
    if (isinf(number)) {
      [self writeByte:number > 0 ? FirestoreDataTypeInfinity
                                 : FirestoreDataTypeNegativeInfinity];
    } else if (isnan(number)) {
      [self writeByte:FirestoreDataTypeNaN];
    } else {
      [super writeValue:value];
    }
    return;
  }
  if ([value isKindOfClass:[NSString class]]) {
    [super writeValue:value];
    return;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSDictionary *map = value;
    [self writeByte:FLTStandardFieldMap];
    [self writeSize:(UInt32)map.count];
    for (id key in map) {
      [self writeValue:key];
      [self writeValue:map[key]];
    }
    return;
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSArray *list = value;
    [self writeByte:FLTStandardFieldList];
    [self writeSize:(UInt32)list.count];
    for (id item in list) {
      [self writeValue:item];
    }
    return;
  }
  if ([value isKindOfClass:[NSDate class]]) {
    [self writeByte:FirestoreDataTypeDateTime];
    NSDate *date = value;
    NSTimeInterval time = date.timeIntervalSince1970;
    SInt64 ms = (SInt64)(time * 1000.0);
    [self writeBytes:&ms length:8];
  } else if ([value isKindOfClass:[FIRTimestamp class]]) {
    FIRTimestamp *timestamp = value;
    SInt64 seconds = timestamp.seconds;
    int nanoseconds = timestamp.nanoseconds;
    [self writeByte:FirestoreDataTypeTimestamp];
    [self writeBytes:(UInt8 *)&seconds length:8];
    [self writeBytes:(UInt8 *)&nanoseconds length:4];
  } else if ([value isKindOfClass:[FIRGeoPoint class]]) {
    FIRGeoPoint *geoPoint = value;
    Float64 latitude = geoPoint.latitude;
    Float64 longitude = geoPoint.longitude;
    [self writeByte:FirestoreDataTypeGeoPoint];
    [self writeAlignment:8];
    [self writeBytes:(UInt8 *)&latitude length:8];
    [self writeBytes:(UInt8 *)&longitude length:8];
  } else if ([value isKindOfClass:[FIRVectorValue class]]) {
    FIRVectorValue *vector = value;
    [self writeByte:FirestoreDataTypeVectorValue];
    [self writeValue:vector.array];
  } else if ([value isKindOfClass:[FIRDocumentReference class]]) {
    FIRDocumentReference *document = value;
    NSString *documentPath = [document path];
    NSString *appName = [FLTFirebasePlugin firebaseAppNameFromIosName:document.firestore.app.name];
    [self writeByte:FirestoreDataTypeDocumentReference];
    [self writeValue:appName];
    [self writeValue:documentPath];

    FIRFirestore *firestore = document.firestore;

    FLTFirebaseFirestoreExtension *extension =
        [FLTFirebaseFirestoreUtils getCachedInstanceForFirestore:firestore];
    [self writeValue:extension.databaseURL];

  } else if ([value isKindOfClass:[FIRDocumentSnapshot class]]) {
    [self writeValue:[self FIRDocumentSnapshot:value]];
  } else if ([value isKindOfClass:[FIRLoadBundleTaskProgress class]]) {
    [self writeValue:[self FIRLoadBundleTaskProgress:value]];
  } else if ([value isKindOfClass:[FIRQuerySnapshot class]]) {
    [self writeValue:[self FIRQuerySnapshot:value]];
  } else if ([value isKindOfClass:[FIRDocumentChange class]]) {
    [self writeValue:[self FIRDocumentChange:value]];
  } else if ([value isKindOfClass:[FIRSnapshotMetadata class]]) {
    [self writeValue:[self FIRSnapshotMetadata:value]];
  } else if ([value isKindOfClass:[NSData class]]) {
    NSData *blob = value;
    [self writeByte:FirestoreDataTypeBlob];
    [self writeSize:(UInt32)blob.length];
    [self writeData:blob];
  } else {
    [super writeValue:value];
  }
}

- (NSDictionary *)FIRSnapshotMetadata:(FIRSnapshotMetadata *)snapshotMetadata {
  return @{
    @"hasPendingWrites" : @(snapshotMetadata.hasPendingWrites),
    @"isFromCache" : @(snapshotMetadata.isFromCache),
  };
}

- (NSDictionary *)FIRDocumentChange:(FIRDocumentChange *)documentChange {
  NSString *type;

  switch (documentChange.type) {
    case FIRDocumentChangeTypeAdded:
      type = @"DocumentChangeType.added";
      break;
    case FIRDocumentChangeTypeModified:
      type = @"DocumentChangeType.modified";
      break;
    case FIRDocumentChangeTypeRemoved:
      type = @"DocumentChangeType.removed";
      break;
  }

  NSNumber *oldIndex;
  NSNumber *newIndex;

  // Note the Firestore C++ SDK here returns a maxed UInt that is != NSUIntegerMax, so we make one
  // ourselves so we can convert to -1 for Dart.
  NSUInteger MAX_VAL = (NSUInteger)[@(-1) integerValue];

  if (documentChange.newIndex == NSNotFound || documentChange.newIndex == 4294967295 ||
      documentChange.newIndex == MAX_VAL) {
    newIndex = @([@(-1) intValue]);
  } else {
    newIndex = @([@(documentChange.newIndex) intValue]);
  }

  if (documentChange.oldIndex == NSNotFound || documentChange.oldIndex == 4294967295 ||
      documentChange.oldIndex == MAX_VAL) {
    oldIndex = @([@(-1) intValue]);
  } else {
    oldIndex = @([@(documentChange.oldIndex) intValue]);
  }

  return @{
    @"type" : type,
    @"data" : documentChange.document.data,
    @"path" : documentChange.document.reference.path,
    @"oldIndex" : oldIndex,
    @"newIndex" : newIndex,
    @"metadata" : documentChange.document.metadata,
  };
}

- (FIRServerTimestampBehavior)toServerTimestampBehavior:(NSString *)serverTimestampBehavior {
  if (serverTimestampBehavior == nil) {
    return FIRServerTimestampBehaviorNone;
  }

  if ([serverTimestampBehavior isEqualToString:@"estimate"]) {
    return FIRServerTimestampBehaviorEstimate;
  } else if ([serverTimestampBehavior isEqualToString:@"previous"]) {
    return FIRServerTimestampBehaviorPrevious;
  } else {
    return FIRServerTimestampBehaviorNone;
  }
}

- (NSDictionary *)FIRDocumentSnapshot:(FIRDocumentSnapshot *)documentSnapshot {
  if (documentSnapshot == nil) {
    NSLog(@"Error: documentSnapshot is nil");
    return nil;
  }

  NSNumber *documentSnapshotHash = @([documentSnapshot hash]);
  NSString *timestampBehaviorString =
      [FLTFirebaseFirestorePlugin.serverTimestampMap objectForKey:documentSnapshotHash];

  FIRServerTimestampBehavior serverTimestampBehavior =
      [self toServerTimestampBehavior:timestampBehaviorString];

  [FLTFirebaseFirestorePlugin.serverTimestampMap removeObjectForKey:documentSnapshotHash];

  return @{
    @"path" : documentSnapshot.reference.path,
    @"data" : documentSnapshot.exists
        ? (id)[documentSnapshot dataWithServerTimestampBehavior:serverTimestampBehavior]
        : [NSNull null],
    @"metadata" : documentSnapshot.metadata,
  };
}
- (NSDictionary *)FIRLoadBundleTaskProgress:(FIRLoadBundleTaskProgress *)progress {
  NSString *state;

  switch (progress.state) {
    case FIRLoadBundleTaskStateError:
      state = @"error";
      break;
    case FIRLoadBundleTaskStateSuccess:
      state = @"success";
      break;
    case FIRLoadBundleTaskStateInProgress:
      state = @"running";
      break;
  }
  return @{
    @"bytesLoaded" : @(progress.bytesLoaded),
    @"documentsLoaded" : @(progress.documentsLoaded),
    @"totalBytes" : @(progress.totalBytes),
    @"totalDocuments" : @(progress.totalDocuments),
    @"taskState" : state,
  };
}

- (NSDictionary *)FIRQuerySnapshot:(FIRQuerySnapshot *)querySnapshot {
  if (querySnapshot == nil) {
    NSLog(@"Error: querySnapshot is nil");
    return nil;
  }

  NSNumber *querySnapshotHash = @([querySnapshot hash]);

  NSMutableArray *paths = [NSMutableArray array];
  NSMutableArray *documents = [NSMutableArray array];
  NSMutableArray *metadatas = [NSMutableArray array];
  NSString *timestampBehaviorString =
      [FLTFirebaseFirestorePlugin.serverTimestampMap objectForKey:querySnapshotHash];

  FIRServerTimestampBehavior serverTimestampBehavior =
      [self toServerTimestampBehavior:timestampBehaviorString];

  [FLTFirebaseFirestorePlugin.serverTimestampMap removeObjectForKey:querySnapshotHash];

  for (FIRDocumentSnapshot *document in querySnapshot.documents) {
    [paths addObject:document.reference.path];
    [documents addObject:[document dataWithServerTimestampBehavior:serverTimestampBehavior]];
    [metadatas addObject:document.metadata];
  }

  return @{
    @"paths" : paths,
    @"documentChanges" : querySnapshot.documentChanges,
    @"documents" : documents,
    @"metadatas" : metadatas,
    @"metadata" : querySnapshot.metadata,
  };
}
@end
