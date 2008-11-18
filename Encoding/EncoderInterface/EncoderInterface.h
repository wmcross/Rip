/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import <Cocoa/Cocoa.h>

@class EncodingOperation, EncodingPostProcessingOperation;

// ========================================
// The interface encoders must implement to integrate with Rip
// ========================================
@protocol EncoderInterface

// The default encoder settings, if any
- (NSDictionary *) defaultSettings;

// Create an instance of NSViewController allowing users to edit the encoder's configuration
// The controller's representedObject will be set to the applicable encoder settings (NSDictionary *)
- (NSViewController *) configurationViewController;

// Provide an instance of an EncodingOperation subclass
- (EncodingOperation *) encodingOperation;

// Provide an instance of an EncodingPostProcessingOperation subclass
- (EncodingPostProcessingOperation *) encodingPostProcessingOperation;

// Determine which filename extension should be used for output based on the given settings
- (NSString *) pathExtensionForSettings:(NSDictionary *)settings;

@end
