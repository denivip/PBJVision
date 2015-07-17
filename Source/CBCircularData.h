//
//  CBCircularData.h
//  mstreamer
//
//  Created by IPv6 on 14/07/15.
//  Copyright (c) 2015 DENIVIP Group. All rights reserved.
//

#ifndef mstreamer_CBCircularData_h
#define mstreamer_CBCircularData_h
@interface CBCircularData : NSObject

- (instancetype)initWithDepth:(NSUInteger)maxBytes;
- (NSData*)readData:(NSUInteger)offset length:(NSInteger)len;
- (NSUInteger)writeData:(NSData*)dt;
- (void)removeAll;
- (NSDate*)getLastModified;
- (NSUInteger)size;
- (NSUInteger)sizeCap;
- (NSUInteger)lowOffset;
- (NSArray*)dataBuffers;
@end
#endif
