/**
 * Magtek Module
 *
 * Appcelerator Titanium is Copyright (c) 2009-2010 by Appcelerator, Inc.
 * and licensed under the Apache Public License (version 2)
 * #############
 * The reader will always send data in blocks of 500 bytes.  If card data is more than 500 bytes, the 
 reader will send this using 2 blocks of 500 bytes.  If card data is less than or equal to 500 bytes, 
 the reader will only send 1 block with 500 bytes.  If data is less than 500 bytes in a block, the 
 reader will use a lower case ‘x’ (0x78) as padding characters.  Note: The longest message always 
 fits within 2 blocks
 */
#import "TiMagtekModule.h"
#import "TiBase.h"
#import "TiHost.h"
#import "TiUtils.h"
#import "TiBlob.h"

@implementation TiMagtekModule

#pragma mark Internal

// this is generated for your module, please do not change it
-(id)moduleGUID
{
	return @"57754725-fe67-4e3f-90c7-1137ad0a5b13";
}

// this is generated for your module, please do not change it
-(NSString*)moduleId
{
	return @"ti.magtek";
}

#pragma mark Lifecycle

-(void)startup
{
	// this method is called when the module is first loaded
	// you *must* call the superclass
	fullbuffer =  [[NSMutableString alloc] init];
	[super startup];
	//fullbuffer = [[NSMutableData alloc] initWithLength:0];
	NSLog(@"[INFO] Magtek iDynamo Reader Module loaded",self);
}

-(void)cleanup
{
	if (session!=nil)
	{
		[[session inputStream] setDelegate:nil];
		[[session outputStream] setDelegate:nil];
		
		[[session inputStream] close];
		[[session outputStream] close];
	}
	RELEASE_TO_NIL(session);
	RELEASE_TO_NIL(accessory);
	RELEASE_TO_NIL(fullbuffer);
}

-(void)_destroy
{
	[self cleanup];
	
	// this method is called when the module is being unloaded
	// typically this is during shutdown. make sure you don't do too
	// much processing here or the app will be quit forceably
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center removeObserver:self name:EAAccessoryDidConnectNotification object:nil];
	[center removeObserver:self name:EAAccessoryDidDisconnectNotification object:nil];
	
	// you *must* call the superclass
	[super _destroy];
}

#pragma mark Cleanup 

-(void)dealloc
{
	[self cleanup];
	
	// release any resources that have been retained by the module
	[super dealloc];
}

#pragma mark Internal Memory Management

-(void)didReceiveMemoryWarning:(NSNotification*)notification
{
	// optionally release any resources that can be dynamically
	// reloaded once memory is available - such as caches
	[super didReceiveMemoryWarning:notification];
}

#pragma mark Device

- (BOOL)openSessionForProtocol:(NSString *)protocolString
{
    NSArray *accessories = [[EAAccessoryManager sharedAccessoryManager]
							connectedAccessories];
	
    for (EAAccessory *obj in accessories)
    {
		NSLog(@"ACCESSORY INSTALLED = %@",obj);
		
        if ([[obj protocolStrings] containsObject:protocolString])
        {
            accessory = [obj retain];
			NSLog(@"FOUND ACCESSORY = %@",accessory);
            break;
        }
    }
	
    if (accessory)
    {
        session = [[EASession alloc] initWithAccessory:accessory
										   forProtocol:protocolString];
        if (session)
        {
            [[session inputStream] setDelegate:self];
            [[session inputStream] scheduleInRunLoop:[NSRunLoop mainRunLoop]
											 forMode:NSDefaultRunLoopMode];
            [[session inputStream] open];
            //[[session outputStream] setDelegate:self];
           // [[session outputStream] scheduleInRunLoop:[NSRunLoop mainRunLoop]
			//								  forMode:NSDefaultRunLoopMode];
            //[[session outputStream] open];
        }
    }
	
    return session!=nil;
}

- (void)stream:(NSStream*)theStream handleEvent:(NSStreamEvent)streamEvent
{
	static BOOL waitForMoreData = NO;
    switch (streamEvent)
    {
        case NSStreamEventHasBytesAvailable:
		
			NSLog(@"------- NSStreamEventHasBytesAvailable ---------");
			uint8_t readBuf[1024];
			memset(readBuf, 0, sizeof(readBuf));
			//read input stream
			NSInteger numberRead = [ (NSInputStream *) theStream read:readBuf maxLength:1024];
			NSString *tempString = [[NSString alloc] initWithFormat:@"%s",readBuf];
			if(waitForMoreData){
				[fullbuffer appendString:tempString];
				waitForMoreData = NO;
				[self parseCardData];
			} else if (numberRead >= 493) {
				[fullbuffer setString:@""];
				[fullbuffer appendString:tempString];
				
				if([tempString characterAtIndex:numberRead-1] !='x'){
					//more data is coming so we need to wait for it
					waitForMoreData = YES;
				} else {
					[self parseCardData];
				}

			} else {
				[fullbuffer setString:@""];
				[fullbuffer appendString:tempString];
				[self parseCardData];
			}
			[tempString release];
		
			break;
		case NSStreamEventErrorOccurred:
			[fullbuffer setString:@""];
			[self fireEvent:@"swipeError"];
			break;
			
		case NSStreamEventOpenCompleted:
			NSLog(@"NSStreamEventOpenCompleted :");
			//NSLog(@"----------- NO MORE BUFFER ----------- %s",_data);
			break;
		
		case NSStreamEventEndEncountered:
			NSLog(@"**** NSStreamEventEndEncountered ****");
			[fullbuffer setString:@""];
			[self fireEvent:@"disconnected"];
			break;
 
		case NSStreamEventHasSpaceAvailable:
            break;
		
        default:
            break;
    }
	
}

-(void)parseCardData
{
	@try{
		
		NSRange range = [fullbuffer rangeOfString:@"^"];
		if (range.location!=NSNotFound)
		{
			NSString *subbuffer = [fullbuffer substringFromIndex:range.location+1]; 
			range = [subbuffer rangeOfString:@"^"];
			NSString *fullname = [subbuffer substringToIndex:range.location];
			range = [fullname rangeOfString:@"/"];
			if (range.location!=NSNotFound)
			{
				NSString *first = [fullname substringFromIndex:range.location+1];
				NSString *last = [fullname substringToIndex:range.location];
				fullname = [NSString stringWithFormat:@"%@ %@",first,last];
			}
			range = [subbuffer rangeOfString:@";"];
			
			subbuffer = [subbuffer substringFromIndex:range.location+1];
			
			NSArray *tokens = [subbuffer componentsSeparatedByString:@"="];
			if ([tokens count] > 1)
			{
				NSString *ccExpiry = [[tokens objectAtIndex:1] substringToIndex:4];
				ccExpiry = [NSString stringWithFormat:@"%c%c/%c%c",[ccExpiry characterAtIndex:2],[ccExpiry characterAtIndex:3],[ccExpiry characterAtIndex:0],[ccExpiry characterAtIndex:1]];
				NSMutableDictionary *event = [NSMutableDictionary dictionary];
				NSData *data = [fullbuffer dataUsingEncoding:NSUTF8StringEncoding];
				TiBlob *blob = [[[TiBlob alloc] initWithData:data mimetype:@"binary/octet-stream"] autorelease];
				[event setValue:fullname forKey:@"name"];
				[event setValue:[tokens objectAtIndex:0] forKey:@"cardnumber"];
				[event setValue:ccExpiry forKey:@"expiration"];
				[event setValue:blob forKey:@"data"];
				[self fireEvent:@"swipe" withObject:event];
			} else {
				NSMutableDictionary *event = [NSMutableDictionary dictionary];
				[event setValue:@"token count" forKey:@"message"];
				[self fireEvent:@"swipeError"];
			}
		} else {
			NSString *message = [NSString stringWithFormat:@"not found"];
			NSMutableDictionary *event = [NSMutableDictionary dictionary];
			[event setValue:message forKey:@"message"];
			[self fireEvent:@"swipeError" withObject:event];
		}
		
	} @catch(NSException *e) {
		NSLog(@"------ **** SWIPE ERROR **** -----");
		NSString *message = [NSString stringWithFormat:@"exception"];
		NSMutableDictionary *event = [NSMutableDictionary dictionary];
		[event setValue:message forKey:@"message"];
		[self fireEvent:@"swipeError" withObject:event];
	} @finally {
		[fullbuffer setString:@""];
	}
	
}

-(NSMutableDictionary*)accessoryToDictionary:(EAAccessory*)accessory_
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	[dict setValue:NUMINT([accessory_ connectionID]) forKey:@"connectionId"];
	[dict setValue:[accessory_ name] forKey:@"name"];
	[dict setValue:[accessory_ manufacturer] forKey:@"manufacturer"];
	[dict setValue:[accessory_ modelNumber] forKey:@"modelNumber"];
	[dict setValue:[accessory_ name] forKey:@"name"];
	[dict setValue:[accessory_ serialNumber] forKey:@"serialNumber"];
	[dict setValue:[accessory_ hardwareRevision] forKey:@"hardwareRevision"];
	[dict setValue:[accessory_ firmwareRevision] forKey:@"firmwareRevision"];
	return dict;
}

-(void)deviceConnected:(NSNotification*)note
{
	NSLog(@"DEVICE CONNECTED = %@",note);
	
	[self cleanup];
	
	[self openSessionForProtocol:protocol];
	if (session!=nil)
	{
		accessory = [[[note userInfo] objectForKey:EAAccessoryKey] retain];
		NSDictionary *event = [self accessoryToDictionary:accessory];
		[self fireEvent:@"connected" withObject:event];
	}
}

-(void)deviceDisconnected:(NSNotification*)note
{
	NSLog(@"DEVICE DISCONNECTED = %@",note);
	
	EAAccessory *accessory_ = [[note userInfo] objectForKey:EAAccessoryKey];
	if ([accessory_ isEqual:accessory])
	{
		NSDictionary *event = [self accessoryToDictionary:accessory];
		[self fireEvent:@"disconnected" withObject:event];
		
		RELEASE_TO_NIL(session);
		RELEASE_TO_NIL(accessory);
	}
}

#pragma Public APIs

-(void)registerDevice:(id)args
{
	ENSURE_UI_THREAD(registerDevice,args);
	ENSURE_SINGLE_ARG(args,NSString);
	
	protocol = [args retain];
	[[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
	
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(deviceConnected:) name:EAAccessoryDidConnectNotification object:nil];
	[center addObserver:self selector:@selector(deviceDisconnected:) name:EAAccessoryDidDisconnectNotification object:nil];
	
	[self openSessionForProtocol:protocol];
	
	NSLog(@"OPEN SESSION = %@, %@",session,accessory);
	
	if (session!=nil && accessory!=nil)
	{
		NSDictionary *event = [self accessoryToDictionary:accessory];
		[self fireEvent:@"connected" withObject:event];
	}
}

@end
