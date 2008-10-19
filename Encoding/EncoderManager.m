/*
 *  Copyright (C) 2008 Stephen F. Booth <me@sbooth.org>
 *  All Rights Reserved
 */

#import "EncoderManager.h"
#import "PlugInManager.h"
#import "EncoderInterface/EncoderInterface.h"
#import "EncoderInterface/EncodingOperation.h"

#import "TrackMetadata.h"
#import "AlbumMetadata.h"
#import "TrackDescriptor.h"
#import "SessionDescriptor.h"
#import "CompactDisc.h"
#import "TrackExtractionRecord.h"
#import "ImageExtractionRecord.h"

#import "FileUtilities.h"

// ========================================
// Flatten the metadata objects into a single NSDictionary
// ========================================
static NSDictionary *
metadataForTrackExtractionRecord(TrackExtractionRecord *trackExtractionRecord)
{
	NSCParameterAssert(nil != trackExtractionRecord);
	
	NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
	
	// Only a single track was extracted
	TrackMetadata *trackMetadata = trackExtractionRecord.track.metadata;
	AlbumMetadata *albumMetadata = trackMetadata.track.session.disc.metadata;

	// Track number and total
	if(trackMetadata.track.number)
		[metadata setObject:trackMetadata.track.number forKey:kMetadataTrackNumberKey];
	if(trackMetadata.track.session.tracks.count)
		[metadata setObject:[NSNumber numberWithUnsignedInteger:trackMetadata.track.session.tracks.count] forKey:kMetadataTrackTotalKey];
	
	// Album metadata
	if(albumMetadata.artist)
		[metadata setObject:albumMetadata.artist forKey:kMetadataAlbumArtistKey];
	if(albumMetadata.date)
		[metadata setObject:albumMetadata.date forKey:kMetadataReleaseDateKey];
	if(albumMetadata.discNumber)
		[metadata setObject:albumMetadata.discNumber forKey:kMetadataDiscNumberKey];
	if(albumMetadata.discTotal)
		[metadata setObject:albumMetadata.discTotal forKey:kMetadataDiscTotalKey];
	if(albumMetadata.isCompilation)
		[metadata setObject:albumMetadata.isCompilation forKey:kMetadataCompilationKey];
	if(albumMetadata.MCN)
		[metadata setObject:albumMetadata.MCN forKey:kMetadataMCNKey];
	if(albumMetadata.title)
		[metadata setObject:albumMetadata.title forKey:kMetadataAlbumTitleKey];
	
	// Track metadata
	if(trackMetadata.artist)
		[metadata setObject:trackMetadata.artist forKey:kMetadataArtistKey];
	if(trackMetadata.composer)
		[metadata setObject:trackMetadata.composer forKey:kMetadataComposerKey];
	if(trackMetadata.date)
		[metadata setObject:trackMetadata.date forKey:kMetadataReleaseDateKey];
	if(trackMetadata.genre)
		[metadata setObject:trackMetadata.genre forKey:kMetadataGenreKey];
	if(trackMetadata.ISRC)
		[metadata setObject:trackMetadata.ISRC forKey:kMetadataISRCKey];
	if(trackMetadata.title)
		[metadata setObject:trackMetadata.title forKey:kMetadataTitleKey];

	return [metadata copy];
}

static NSDictionary *
metadataForExtractedImageRecord(ExtractedImageRecord *imageExtractionRecord)
{
	NSCParameterAssert(nil != imageExtractionRecord);
	
	NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
#if 0
	// Multiple tracks were extracted, so fill in album details only
	TrackMetadata *trackMetadata = imageExtractionRecord.firstTrack.track.metadata;
	AlbumMetadata *albumMetadata = trackMetadata.track.session.disc.metadata;
	
	// Track number and total
	if(trackMetadata.track.session.tracks.count)
		[metadata setObject:[NSNumber numberWithUnsignedInteger:trackMetadata.track.session.tracks.count] forKey:kMetadataTrackTotalKey];
	
	// Album metadata
	if(albumMetadata.artist)
		[metadata setObject:albumMetadata.artist forKey:kMetadataAlbumArtistKey];
	if(albumMetadata.date)
		[metadata setObject:albumMetadata.date forKey:kMetadataReleaseDateKey];
	if(albumMetadata.discNumber)
		[metadata setObject:albumMetadata.discNumber forKey:kMetadataDiscNumberKey];
	if(albumMetadata.discTotal)
		[metadata setObject:albumMetadata.discTotal forKey:kMetadataDiscTotalKey];
	if(albumMetadata.isCompilation)
		[metadata setObject:albumMetadata.isCompilation forKey:kMetadataCompilationKey];
	if(albumMetadata.MCN)
		[metadata setObject:albumMetadata.MCN forKey:kMetadataMCNKey];
	if(albumMetadata.title)
		[metadata setObject:albumMetadata.title forKey:kMetadataAlbumTitleKey];
#endif
	return [metadata copy];
}

// ========================================
// Create the output filename to use for the given ExtractionRecord
// ========================================
static NSString *
filenameForTrackExtractionRecord(TrackExtractionRecord *trackExtractionRecord)
{
	NSCParameterAssert(nil != trackExtractionRecord);
		
	// Only a single track was extracted
	TrackDescriptor *track = trackExtractionRecord.track;

	NSString *title = track.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Title", @"");
	
	// Build up the sanitized track name
	return [NSString stringWithFormat:@"%02lu %@", track.number.unsignedIntegerValue, makeStringSafeForFilename(title)];
}

static NSString *
filenameForExtractedImageRecord(ImageExtractionRecord *imageExtractionRecord)
{
	NSCParameterAssert(nil != imageExtractionRecord);
	
	NSString *filename = nil;
	CompactDisc *disc = imageExtractionRecord.disc;
#if 0
	NSString *title = disc.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Album", @"");
	
	// Build up the sanitized file name
	if(imageExtractionRecord.tracks.count != disc.firstSession.tracks.count) {
		TrackExtractionRecord *firstTrack = imageExtractionRecord.firstTrack;
		TrackExtractionRecord *lastTrack = extractionRecord.lastTrack;
		
		filename = [NSString stringWithFormat:@"%@ (%@ - %@)", makeStringSafeForFilename(title), firstTrack.track.number, lastTrack.track.number];
	}
	else
		filename = makeStringSafeForFilename(title);
#endif
	return filename;
}

// ========================================
// Sorting function for sorting bundles by encoder names
// ========================================
static NSComparisonResult
encoderBundleSortFunction(id bundleA, id bundleB, void *context)
{
	
#pragma unused(context)
	
	NSCParameterAssert(nil != bundleA);
	NSCParameterAssert(nil != bundleB);
	NSCParameterAssert([bundleA isKindOfClass:[NSBundle class]]);
	NSCParameterAssert([bundleB isKindOfClass:[NSBundle class]]);
	
	NSString *bundleAName = [bundleA objectForInfoDictionaryKey:@"EncoderName"];
	NSString *bundleBName = [bundleB objectForInfoDictionaryKey:@"EncoderName"];

	return [bundleAName compare:bundleBName];;
}

// ========================================
// Context objects for observeValueForKeyPath:ofObject:change:context:
// ========================================
static NSString * const kEncodingOperationKVOContext		= @"org.sbooth.Rip.EncoderManager.EncodingOperationKVOContext";

// ========================================
// KVC key names for the encoder dictionaries
// ========================================
NSString * const	kEncoderBundleKey						= @"bundle";
NSString * const	kEncoderSettingsKey						= @"settings";

// ========================================
// Static variables
// ========================================
static EncoderManager *sSharedEncoderManager				= nil;

@implementation EncoderManager

@synthesize queue = _queue;

+ (id) sharedEncoderManager
{
	if(!sSharedEncoderManager)
		sSharedEncoderManager = [[self alloc] init];
	return sSharedEncoderManager;
}

+ (NSSet *) keyPathsForValuesAffectingDefaultEncoderSettings
{
	return [NSSet setWithObject:@"defaultEncoder"];
}

- (id) init
{
	if((self = [super init]))
		_queue = [[NSOperationQueue alloc] init];
	return self;
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if(kEncodingOperationKVOContext == context) {
		EncodingOperation *operation = (EncodingOperation *)object;
		
		if([keyPath isEqualToString:@"isCancelled"] || [keyPath isEqualToString:@"isFinished"]) {
//			[operation removeObserver:self forKeyPath:@"isExecuting"];
			[operation removeObserver:self forKeyPath:@"isCancelled"];
			[operation removeObserver:self forKeyPath:@"isFinished"];
			
			// Remove the temporary file
			NSError *error = nil;
			if(![[NSFileManager defaultManager] removeItemAtPath:[operation.inputURL path] error:&error])
				[[NSApplication sharedApplication] presentError:error];
		}
	}
	else
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (NSArray *) availableEncoders
{
	PlugInManager *plugInManager = [PlugInManager sharedPlugInManager];
	
	NSError *error = nil;
	NSArray *availableEncoders = [plugInManager plugInsConformingToProtocol:@protocol(EncoderInterface) error:&error];
	
	return [availableEncoders sortedArrayUsingFunction:encoderBundleSortFunction context:NULL];
}

- (NSBundle *) defaultEncoder
{
	NSString *bundleIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:@"defaultEncoder"];
	NSBundle *bundle = [[PlugInManager sharedPlugInManager] plugInForIdentifier:bundleIdentifier];
	
	// If the default wasn't found, return any available encoder
	if(!bundle)
		bundle = [self.availableEncoders lastObject];
	
	return bundle;
}

- (void) setDefaultEncoder:(NSBundle *)encoder
{
	NSParameterAssert(nil != encoder);
	
	// Verify this is a valid encoder
	if(![self.availableEncoders containsObject:encoder])
		return;
	
	[self willChangeValueForKey:@"settingsForDefaultMusicDatabase"];

	// Set this as the default encoder
	NSString *bundleIdentifier = [encoder bundleIdentifier];
	[[NSUserDefaults standardUserDefaults] setObject:bundleIdentifier forKey:@"defaultEncoder"];
	
	// If no settings are present for this encoder, store the defaults
	if(![[NSUserDefaults standardUserDefaults] dictionaryForKey:bundleIdentifier]) {
		// Instantiate the encoder interface
		id <EncoderInterface> encoderInterface = [[[encoder principalClass] alloc] init];
		
		// Grab the encoder's settings dictionary
		[[NSUserDefaults standardUserDefaults] setObject:[encoderInterface defaultSettings] forKey:bundleIdentifier];
	}
}

- (NSDictionary *) defaultEncoderSettings
{
	return [self settingsForEncoder:self.defaultEncoder];
}

- (void) setDefaultEncoderSettings:(NSDictionary *)encoderSettings
{
	[self storeSettings:encoderSettings forEncoder:self.defaultEncoder];
}

- (NSDictionary *) settingsForEncoder:(NSBundle *)encoder
{
	NSParameterAssert(nil != encoder);
	
	// Verify this is a valid encoder
	if(![self.availableEncoders containsObject:encoder])
		return nil;
	
	NSString *bundleIdentifier = [encoder bundleIdentifier];
	NSDictionary *encoderSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:bundleIdentifier];
	
	// If no settings are present for this encoder, use the defaults
	if(!encoderSettings) {
		// Instantiate the encoder interface
		id <EncoderInterface> encoderInterface = [[[encoder principalClass] alloc] init];
		
		// Grab the encoder's settings dictionary
		encoderSettings = [encoderInterface defaultSettings];
		
		// Store the defaults
		if(encoderSettings)
			[[NSUserDefaults standardUserDefaults] setObject:encoderSettings forKey:bundleIdentifier];
	}
	
	return [encoderSettings copy];
}

- (void) storeSettings:(NSDictionary *)encoderSettings forEncoder:(NSBundle *)encoder
{

	NSParameterAssert(nil != encoder);
	
	// Verify this is a valid encoder
	if(![self.availableEncoders containsObject:encoder])
		return;
	
	NSString *bundleIdentifier = [encoder bundleIdentifier];
	if(encoderSettings)
		[[NSUserDefaults standardUserDefaults] setObject:encoderSettings forKey:bundleIdentifier];
	else
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:bundleIdentifier];
}

- (void) restoreDefaultSettingsForEncoder:(NSBundle *)encoder
{
	NSParameterAssert(nil != encoder);
	
	// Verify this is a valid encoder
	if(![self.availableEncoders containsObject:encoder])
		return;
	
	NSString *bundleIdentifier = [encoder bundleIdentifier];

	// Instantiate the encoder interface
	id <EncoderInterface> encoderInterface = [[[encoder principalClass] alloc] init];
	
	// Grab the encoder's settings dictionary
	NSDictionary *encoderSettings = [encoderInterface defaultSettings];
	
	// Store the defaults
	if(encoderSettings)
		[[NSUserDefaults standardUserDefaults] setObject:encoderSettings forKey:bundleIdentifier];
	else
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:bundleIdentifier];
}

- (NSURL *) outputURLForCompactDisc:(CompactDisc *)disc
{
	NSParameterAssert(nil != disc);
	
	NSString *title = disc.metadata.title;
	if(nil == title)
		title = NSLocalizedString(@"Unknown Album", @"");
	
	NSString *artist = disc.metadata.artist;
	if(nil == artist)
		artist = NSLocalizedString(@"Unknown Artist", @"");
	
	// Build up the sanitized Artist/Album structure
	NSArray *pathComponents = [NSArray arrayWithObjects:makeStringSafeForFilename(artist), makeStringSafeForFilename(title), nil];
	NSString *path = [NSString pathWithComponents:pathComponents];
	
	// Append it to the output folder
	NSURL *outputFolderURL = [NSUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] dataForKey:@"outputDirectory"]];
	NSString *outputPath = [[outputFolderURL path] stringByAppendingPathComponent:path];
	
	return [NSURL fileURLWithPath:outputPath];
}

- (BOOL) encodeURL:(NSURL *)inputURL forTrackExtractionRecord:(TrackExtractionRecord *)TrackExtractionRecord error:(NSError **)error;
{
	NSParameterAssert(nil != inputURL);
	NSParameterAssert(nil != TrackExtractionRecord);
	
	NSString *defaultEncoder = [[NSUserDefaults standardUserDefaults] stringForKey:@"defaultEncoder"];
	
	PlugInManager *plugInManager = [PlugInManager sharedPlugInManager];
	NSBundle *encoderBundle = [plugInManager plugInForIdentifier:defaultEncoder];
	
	if(![encoderBundle loadAndReturnError:error])
		return NO;
	
	NSDictionary *encoderSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:defaultEncoder];
	
	Class encoderClass = [encoderBundle principalClass];
	NSObject <EncoderInterface> *encoderInterface = [[encoderClass alloc] init];
	
	// Build the filename for the output from the disc's folder, the track's name and number,
	// and the encoder's output path extension
	NSURL *baseURL = [self outputURLForCompactDisc:TrackExtractionRecord.track.session.disc];
	NSString *filename = filenameForTrackExtractionRecord(TrackExtractionRecord);
	NSString *pathExtension = [encoderInterface pathExtensionForSettings:encoderSettings];
	NSString *pathname = [filename stringByAppendingPathExtension:pathExtension];
	NSString *outputPath = [[baseURL path] stringByAppendingPathComponent:pathname];
	
	// Ensure the output folder exists
	if(![[NSFileManager defaultManager] createDirectoryAtPath:[baseURL path] withIntermediateDirectories:YES attributes:nil error:error])
		return NO;
	
	// Don't overwrite existing output files
	if([[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
#if DEBUG
		NSLog(@"Output file %@ exists", [outputPath lastPathComponent]);
#endif
		if(error)
			*error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EEXIST userInfo:nil];

		return NO;
	}
	
	EncodingOperation *encodingOperation = [encoderInterface encodingOperation];
	
	encodingOperation.inputURL = inputURL;
	encodingOperation.outputURL = [NSURL fileURLWithPath:outputPath];
	encodingOperation.settings = encoderSettings;
	encodingOperation.metadata = metadataForTrackExtractionRecord(TrackExtractionRecord);
	
	// Observe the operation's progress
//	[encodingOperation addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];
	[encodingOperation addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];
	[encodingOperation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:kEncodingOperationKVOContext];

#if DEBUG
	NSLog(@"Encoding %@ to %@ using %@", [encodingOperation.inputURL path], [encodingOperation.outputURL path], [encoderBundle objectForInfoDictionaryKey:@"EncoderName"]);
#endif

	[self.queue addOperation:encodingOperation];
	
	// Communicate the output URL back to the caller
	TrackExtractionRecord.URL = encodingOperation.outputURL;
	
	return YES;
}

- (BOOL) encodeURL:(NSURL *)inputURL forExtractedImageRecord:(ExtractedImageRecord *)extractedImageRecord error:(NSError **)error
{
	NSBeep();
}

@end
