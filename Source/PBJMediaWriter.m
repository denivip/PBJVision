//
//  PBJMediaWriter.m
//  Vision
//
//  Created by Patrick Piemonte on 1/27/14.
//  Copyright (c) 2013-present, Patrick Piemonte, http://patrickpiemonte.com
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to
//  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//  the Software, and to permit persons to whom the Software is furnished to do so,
//  subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//  FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//  COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//  IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "PBJMediaWriter.h"
#import "PBJVisionUtilities.h"

#import <UIKit/UIDevice.h>
#import <MobileCoreServices/UTCoreTypes.h>

#define LOG_WRITER 0
#if !defined(NDEBUG) && LOG_WRITER
#   define DLog(fmt, ...) NSLog((@"writer: " fmt), ##__VA_ARGS__);
#else
#   define DLog(...)
#endif

@interface PBJMediaWriter ()
{
    AVAssetWriter *_assetWriter;
	AVAssetWriterInput *_assetWriterAudioInput;
	AVAssetWriterInput *_assetWriterVideoInput;
    
    NSURL *_outputURL;
    
    CMTime _audioTimestamp;
    CMTime _videoTimestamp;
    BOOL isMuted;
}

@end

@implementation PBJMediaWriter

@synthesize delegate = _delegate;
@synthesize outputURL = _outputURL;
@synthesize audioTimestamp = _audioTimestamp;
@synthesize videoTimestamp = _videoTimestamp;

#pragma mark - getters/setters

- (BOOL)isAudioReady
{
    AVAuthorizationStatus audioAuthorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
            
    BOOL isAudioNotAuthorized = (audioAuthorizationStatus == AVAuthorizationStatusNotDetermined || audioAuthorizationStatus == AVAuthorizationStatusDenied);
    BOOL isAudioSetup = (_assetWriterAudioInput != nil) || isAudioNotAuthorized;
    
    return isAudioSetup;
}

- (BOOL)isVideoReady
{
    AVAuthorizationStatus videoAuthorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

    BOOL isVideoNotAuthorized = (videoAuthorizationStatus == AVAuthorizationStatusNotDetermined || videoAuthorizationStatus == AVAuthorizationStatusDenied);
    BOOL isVideoSetup = (_assetWriterVideoInput != nil) || isVideoNotAuthorized;
    
    return isVideoSetup;
}

- (NSError *)error
{
    return _assetWriter.error;
}

#pragma mark - init

- (id)initWithOutputURL:(NSURL *)outputURL format:(NSString*)format
{
    self = [super init];
    if (self) {
        NSError *error = nil;
        if(format == nil){
            format = (NSString *)kUTTypeMPEG4;
        }
        _assetWriter = [AVAssetWriter assetWriterWithURL:outputURL fileType:format error:&error];
        if (error) {
            DLog(@"error setting up the asset writer (%@)", error);
            _assetWriter = nil;
            return nil;
        }

        _outputURL = outputURL;
        
        _assetWriter.shouldOptimizeForNetworkUse = YES;
        _assetWriter.metadata = [self _metadataArray];

        _audioTimestamp = kCMTimeInvalid;
        _videoTimestamp = kCMTimeInvalid;

        // ensure authorization is permitted, if not already prompted
        // it's possible to capture video without audio or audio without video
        if ([[AVCaptureDevice class] respondsToSelector:@selector(authorizationStatusForMediaType:)]) {
        
            AVAuthorizationStatus audioAuthorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
            
            if (audioAuthorizationStatus == AVAuthorizationStatusNotDetermined || audioAuthorizationStatus == AVAuthorizationStatusDenied) {
                if (audioAuthorizationStatus == AVAuthorizationStatusDenied && [_delegate respondsToSelector:@selector(mediaWriterDidObserveAudioAuthorizationStatusDenied:)]) {
                    [_delegate mediaWriterDidObserveAudioAuthorizationStatusDenied:self];
                }
            }
            
            AVAuthorizationStatus videoAuthorizationStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
            
            if (videoAuthorizationStatus == AVAuthorizationStatusNotDetermined || videoAuthorizationStatus == AVAuthorizationStatusDenied) {
                if (videoAuthorizationStatus == AVAuthorizationStatusDenied && [_delegate respondsToSelector:@selector(mediaWriterDidObserveVideoAuthorizationStatusDenied:)]) {
                    [_delegate mediaWriterDidObserveVideoAuthorizationStatusDenied:self];
                }
            }
            
        }
        //DLog(@"%@: prepared to write to (%@)", self, outputURL);
    }
    return self;
}

#pragma mark - private

- (NSArray *)_metadataArray
{
    UIDevice *currentDevice = [UIDevice currentDevice];
    
    // device model
    AVMutableMetadataItem *modelItem = [[AVMutableMetadataItem alloc] init];
    [modelItem setKeySpace:AVMetadataKeySpaceCommon];
    [modelItem setKey:AVMetadataCommonKeyModel];
    [modelItem setValue:[currentDevice localizedModel]];

    // software
    AVMutableMetadataItem *softwareItem = [[AVMutableMetadataItem alloc] init];
    [softwareItem setKeySpace:AVMetadataKeySpaceCommon];
    [softwareItem setKey:AVMetadataCommonKeySoftware];
    [softwareItem setValue:@"PBJVision"];

    // creation date
    AVMutableMetadataItem *creationDateItem = [[AVMutableMetadataItem alloc] init];
    [creationDateItem setKeySpace:AVMetadataKeySpaceCommon];
    [creationDateItem setKey:AVMetadataCommonKeyCreationDate];
    [creationDateItem setValue:[NSString PBJformattedTimestampStringFromDate:[NSDate date]]];

    return @[modelItem, softwareItem, creationDateItem];
}

#pragma mark - setup

- (BOOL)setupAudioWithSettings:(NSDictionary *)audioSettings
{
	if (!_assetWriterAudioInput && [_assetWriter canApplyOutputSettings:audioSettings forMediaType:AVMediaTypeAudio]) {
    
		_assetWriterAudioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioSettings];
		_assetWriterAudioInput.expectsMediaDataInRealTime = YES;
        
		if (_assetWriterAudioInput && [_assetWriter canAddInput:_assetWriterAudioInput]) {
			[_assetWriter addInput:_assetWriterAudioInput];
		
            DLog(@"%@: setup audio input with settings sampleRate (%f) channels (%lu) bitRate (%ld)", self,
                [[audioSettings objectForKey:AVSampleRateKey] floatValue],
                (unsigned long)[[audioSettings objectForKey:AVNumberOfChannelsKey] unsignedIntegerValue],
                (long)[[audioSettings objectForKey:AVEncoderBitRateKey] integerValue]);
        
        } else {
			DLog(@"couldn't add asset writer audio input");
		}
        
	} else {
    
        _assetWriterAudioInput = nil;
		DLog(@"couldn't apply audio output settings");
	
    }
    
    return self.isAudioReady;
}

- (BOOL)setupVideoWithSettings:(NSDictionary *)videoSettings
{
	if (!_assetWriterVideoInput && [_assetWriter canApplyOutputSettings:videoSettings forMediaType:AVMediaTypeVideo]) {
    
		_assetWriterVideoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
		_assetWriterVideoInput.expectsMediaDataInRealTime = YES;
		_assetWriterVideoInput.transform = CGAffineTransformIdentity;

		if (_assetWriterVideoInput && [_assetWriter canAddInput:_assetWriterVideoInput]) {
			[_assetWriter addInput:_assetWriterVideoInput];

#if !defined(NDEBUG) && LOG_WRITER
            NSDictionary *videoCompressionProperties = videoSettings[AVVideoCompressionPropertiesKey];
            if (videoCompressionProperties) {
                DLog(@"%@: setup video with compression settings bps (%f) frameInterval (%ld)", self,
                        [videoCompressionProperties[AVVideoAverageBitRateKey] floatValue],
                        (long)[videoCompressionProperties[AVVideoMaxKeyFrameIntervalKey] integerValue]);
            } else {
                DLog(@"setup video");
            }
#endif

		} else {
			DLog(@"couldn't add asset writer video input");
		}
        
	} else {
    
        _assetWriterVideoInput = nil;
		DLog(@"couldn't apply video output settings");
        
	}
    
    return self.isVideoReady;
}

- (void) muteAudioInBuffer:(CMSampleBufferRef)sampleBuffer
{
    CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
    if(numSamples == 0){
        return;
    }
    NSUInteger channelIndex = 0;
    CMBlockBufferRef audioBlockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t sampleSize = CMSampleBufferGetSampleSize (sampleBuffer, 0);//sizeof(SInt16)
    size_t audioBlockBufferOffset = (channelIndex * numSamples * sampleSize);
    size_t lengthAtOffset = 0;
    size_t totalLength = 0;
    Byte *samples = NULL;
    CMBlockBufferGetDataPointer(audioBlockBuffer, audioBlockBufferOffset, &lengthAtOffset, &totalLength, (char **)(&samples));
    memset(samples, 0, numSamples*sampleSize);
    //for (NSInteger i=0; i<numSamples; i++) {
    //    samples[i] = (SInt16)0;
    //}
    
}

- (void)muteAudio:(BOOL)muteOrNot {
    isMuted = muteOrNot;
}

#pragma mark - sample buffer writing

- (void)writeSampleBuffer:(CMSampleBufferRef)sampleBuffer withMediaTypeVideo:(BOOL)video
{
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        DLog("%@: skipping buffer, samples not ready", self);
        return;
    }

    // setup the writer
	if ( _assetWriter.status == AVAssetWriterStatusUnknown ) {
    
        if ([_assetWriter startWriting]) {
            CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
			[self initializeWriting:timestamp];
            DLog(@"%@: started writing with status (%ld)", self, (long)_assetWriter.status);
		} else {
			DLog(@"%@: error when starting to write (%@)", self, [_assetWriter error]);
            return;
		}
        
	}
    
    // check for completion state
    if ( _assetWriter.status == AVAssetWriterStatusFailed ) {
        DLog(@"writer failure, (%@)", _assetWriter.error.localizedDescription);
        return;
    }
    
    if (_assetWriter.status == AVAssetWriterStatusCancelled) {
        DLog(@"writer cancelled");
        return;
    }
    
    if ( _assetWriter.status == AVAssetWriterStatusCompleted) {
        DLog(@"writer finished and completed");
        return;
    }
	
    // perform write
	if ( _assetWriter.status == AVAssetWriterStatusWriting ) {

        CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
        if (duration.value > 0) {
            timestamp = CMTimeAdd(timestamp, duration);
        }
        
		if (video) {
			if (_assetWriterVideoInput.readyForMoreMediaData) {
				if ([_assetWriterVideoInput appendSampleBuffer:sampleBuffer]) {
                    //DLog("%@: appendSampleBuffer ok", self);
                    _videoTimestamp = timestamp;
				} else {
					DLog(@"writer error appending video (%@)", [_assetWriter error]);
                }
            }
            else{
                DLog("%@: skipping buffer", self);
            }
		} else {
            if(isMuted){
                [self muteAudioInBuffer:sampleBuffer];
            }
			if (_assetWriterAudioInput.readyForMoreMediaData) {
				if ([_assetWriterAudioInput appendSampleBuffer:sampleBuffer]) {
                    _audioTimestamp = timestamp;
				} else {
					DLog(@"writer error appending audio (%@)", [_assetWriter error]);
                }
			}
		}
        
	}
}

- (void)initializeWriting:(CMTime)timestamp
{
    [_assetWriter startSessionAtSourceTime:timestamp];
}

- (void)finalizeWriting
{
    if(CMTIME_IS_INVALID(_videoTimestamp)){
        return;
    }
    [_assetWriter endSessionAtSourceTime:_videoTimestamp];
    return;
}

- (BOOL)canBeFinalized
{
    if(CMTIME_IS_INVALID(_videoTimestamp)){
        return NO;
    }
    return YES;
}

- (void)finishWritingWithCompletionHandler:(void (^)(void))handler
{
    DLog("%@: finalizing", self);
    if (_assetWriter.status == AVAssetWriterStatusUnknown) {
        DLog(@"%@: asset writer is in an unknown state, wasn't recording", self);
        return;
    }
    if(![self canBeFinalized]){
        // Nothing to save
        DLog(@"%@: asset writer recorded nothing", self);
        return;
    }
    [self finalizeWriting];
    [_assetWriter finishWritingWithCompletionHandler:handler];
}


@end
