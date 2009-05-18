//
//  AppController.m
//  RemoveImported
//
//  Created by Andrea Nall on 5/17/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "AppController.h"
#import <Dreamwidth/Dreamwidth.h>
#import <XMLRPC/XMLRPC.h>

@interface AppController ()

-(NSString *)lastSync;
-(void)setLastSync:(NSString *)ls;

-(NSNumber *)last_itemid;
-(void)setLast_itemid:(NSNumber *)ls;

-(NSString *)lastgrab;
-(void)setLastgrab:(NSString *)ls;

-(NSString *)stepTime:(NSString *)time by:(NSTimeInterval)i;

-(void)prepareAndCallGetEventStep1;
-(void)prepareAndCallGetEventStep2;

-(void)prepareAndCallHoward1;
-(void)prepareAndCallHoward2;

-(void)countImported;

-(void)deleteTopEvent;

@end

int keysSort(id num1, id num2, void *context) {
    NSMutableDictionary *_sync = (NSMutableDictionary *)context;
    
    NSString *_a = [[_sync objectForKey:num1] objectAtIndex:1];
    NSString *_b = [[_sync objectForKey:num2] objectAtIndex:1];

    return [_a compare:_b];
}

@implementation AppController

- (void) awakeFromNib {
    self.lastSync = @"";
}

-(IBAction)doIt:(id)sender {
    [goButton setEnabled:NO];
    [deleteButton setEnabled:NO];
    [user release];
    user = [[DWUser alloc] initWithUsername:username andPassword:password];
    user.delegate = self;
    [progress startAnimation:sender];
    [progressText setStringValue:@"Logging in..."];
    [user login];
}

-(IBAction)deleteEm:(id)sender {
    [goButton setEnabled:NO];
    [deleteButton setEnabled:NO];
    [progress startAnimation:sender];
    [progress setMinValue:0];
    [progress setMaxValue:[importedEvents count]];
    [progress setDoubleValue:0];
    [progressText setStringValue:[NSString stringWithFormat:@"%i events remaining",[importedEvents count]]];
    [progress setIndeterminate:NO];
    [self deleteTopEvent];
}

-(void)loginFailed:(DWUser *)user {
    [progress stopAnimation:self];
    [progressText setStringValue:@"Failed"];
    [goButton setEnabled:YES];
    [deleteButton setEnabled:NO];
}

-(void)loginSucceeded:(DWUser *)user {
    [progressText setStringValue:@"Loading user data..."];
}

-(void)journalLoaded:(DWJournal *)journal {
    __first = nil;
    [progressText setStringValue:@"Starting syncitems..."];
    
    [triedSyncs release];
    triedSyncs = [[NSMutableDictionary alloc] init];
    
    [sync release];
    sync = [[NSMutableDictionary alloc] init];
    
    [events release];
    events = [[NSMutableArray alloc] init];
    
    [importedEvents release];
    importedEvents = [[NSMutableArray alloc] init];
    
    self.lastSync = @"";
    
    [DWXMLRPCRequest asyncRequestFor:user withMethod:@"syncitems" andArgs:[NSDictionary dictionaryWithObjectsAndKeys:lastSync, @"lastsync",nil] withDelegate:self andArg:nil];
    mode = RI_SYNCITEMS;
}

-(void)journalLoadFailed:(DWJournal *)journal {    
    [progress stopAnimation:self];
    [progressText setStringValue:@"Failed"];
    [goButton setEnabled:YES];
    [deleteButton setEnabled:NO];
}

-(NSString *)stepTime:(NSString *)time by:(NSTimeInterval)i {
    NSDate *_date = [NSDate dateWithString:[time stringByAppendingFormat:@" +0000"]];
    _date = [NSDate dateWithTimeIntervalSince1970:[_date timeIntervalSince1970]+i];
    return [_date descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S" timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]
                                          locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
}

-(void)asyncRequest:(DWXMLRPCRequest *)req didReceiveResponse: (XMLRPCResponse *)response {
    [req retain];
    NSDictionary *obj = [response object];
    if (mode == RI_SYNCITEMS) {
        NSArray *_syncitems = [obj objectForKey:@"syncitems"];
        {
            NSEnumerator *_iEnum = [_syncitems objectEnumerator];
            NSDictionary *_item;
            while ((_item = [_iEnum nextObject])) {
                NSString *_s_time = [self stepTime:[_item objectForKey:@"time"] by:-1];
                NSString *_action = [_item objectForKey:@"action"];
                NSString *_s_item = [_item objectForKey:@"item"];
                
                if ([lastSync compare:_s_time] == NSOrderedAscending)
                    self.lastSync = _s_time;
                
                if ([_s_item hasPrefix:@"L-"]) {
                    _s_item = [_s_item substringFromIndex:2];
                    [sync setObject:[NSArray arrayWithObjects:_action,_s_time,nil] forKey:[NSNumber numberWithInt:[_s_item intValue]]];
                }
            }
        }
        NSNumber *_num;
        if (_num = [triedSyncs objectForKey:lastSync]) {
            _num = [NSNumber numberWithInt:[_num intValue]+1];
        } else {
            _num = [NSNumber numberWithInt:1];
        }
        [triedSyncs setObject:_num forKey:lastSync];
        if ([_num intValue] < 2) {
            [DWXMLRPCRequest asyncRequestFor:user withMethod:@"syncitems" andArgs:[NSDictionary dictionaryWithObjectsAndKeys:lastSync, @"lastsync",nil] withDelegate:self andArg:nil];
        } else {
            [progress setIndeterminate:NO];
            [progress setMinValue:0];
            [progress setMaxValue:[sync count]];
            [progress setDoubleValue:0];
            [progressText setStringValue:@"Fetching entries..."];
            [self prepareAndCallGetEventStep1];
        }
    } else if (mode == RI_GETEVENTS && [response isFault]) {
        if ([[response faultString] rangeOfString:@"broken"].location != NSNotFound) {
            [self prepareAndCallHoward1];
        }
    } else if (mode == RI_GETEVENTS || mode == RI_GETEVENTS_HOWARD) {
        NSDictionary *_events = [obj objectForKey:@"events"];
        {
            NSEnumerator *_iEnum = [_events objectEnumerator];
            NSDictionary *_item;
            while ((_item = [_iEnum nextObject])) {
                [sync removeObjectForKey:[_item objectForKey:@"itemid"]];
                if (![[_item objectForKey:@"event"] isKindOfClass:[NSString class]]) {
                    NSData *d_event = [_item objectForKey:@"event"];
                    NSString *s_event = [[[NSString alloc] initWithData:d_event encoding:NSUTF8StringEncoding] autorelease];
                    _item = [_item mutableCopy];
                    [(NSMutableDictionary *)_item setObject:s_event forKey:@"event"];
                }
                [events addObject:_item];
            }
        }
        [progress setDoubleValue:[progress maxValue]-(double)[sync count]];
        if (mode == RI_GETEVENTS) {
            [self prepareAndCallGetEventStep1];
        } else if (mode == RI_GETEVENTS_HOWARD) {
            [self prepareAndCallHoward2];
        }
    } else if (mode == RI_EATING) {
        [self deleteTopEvent];
    }
}

-(void)prepareAndCallGetEventStep1 {
    mode = RI_GETEVENTS;
    
    if ([sync count] > 0) {
        tries = 0;
        count = 0;
        self.last_itemid = nil;
        self.lastgrab = nil;
    
        [self prepareAndCallGetEventStep2];
    } else {
        [progress setIndeterminate:YES];
        [progress stopAnimation:self];
        [self countImported];
        
        [goButton setEnabled:YES];
    }
}

-(void)countImported {
    NSEnumerator *_iEnum = [events objectEnumerator];
    NSDictionary *_item;
    while ((_item = [_iEnum nextObject])) {
        NSDictionary *_props = [_item objectForKey:@"props"];
        if ([_props objectForKey:@"import_source"] != nil) {
            [importedEvents addObject:_item];
        }
    }
    if ([importedEvents count]) {
        [progressText setStringValue:[NSString stringWithFormat:@"Ready to delete %i (out of %i) events",[importedEvents count],[events count]]];
        [deleteButton setEnabled:YES];
    } else {
        [progressText setStringValue:@"No events to delete"];
        [deleteButton setEnabled:NO];
    }
}

-(void)deleteTopEvent {
    mode = RI_EATING;
    if ([importedEvents count] == 0) {
        [progress setIndeterminate:YES];
        [progress stopAnimation:self];
        [progressText setStringValue:@"Done"];
        
        [goButton setEnabled:YES];
        [deleteButton setEnabled:NO];
    }
    
    NSDictionary *_event = [importedEvents lastObject];
    [importedEvents removeLastObject];
    
    [progress setDoubleValue:([progress maxValue]-(double)[importedEvents count])];
    [progressText setStringValue:[NSString stringWithFormat:@"%i events remaining",[importedEvents count]]];
    
    [[DWXMLRPCRequest asyncRequestFor:user
                           withMethod:@"editevent"
                              andArgs:[NSDictionary dictionaryWithObjectsAndKeys:
                                       [NSNumber numberWithInt:1],@"ver",
                                       [_event objectForKey:@"itemid"],@"itemid",
                                       @"",@"event",
                                       @"unix",@"lineendings",nil]
                         withDelegate:self andArg:nil] retain];
}

-(void)prepareAndCallGetEventStep2 {
    [progressText setStringValue:[NSString stringWithFormat:@"Fetching entries..."]];
    if ( tries++ <= 10) {
        NSArray *keys = [[sync allKeys] sortedArrayUsingFunction:keysSort context:sync];
        self.last_itemid = [keys objectAtIndex:0];
        self.lastgrab = [self stepTime:[[sync objectForKey:last_itemid] objectAtIndex:1] by:-tries];
        
        [[DWXMLRPCRequest asyncRequestFor:user
                              withMethod:@"getevents"
                                 andArgs:[NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSNumber numberWithInt:1],@"ver",
                                          self.lastgrab,@"lastsync",
                                          @"syncitems",@"selecttype",
                                          @"unix",@"lineendings",nil]
                            withDelegate:self andArg:nil] retain];
    }
}

-(void)prepareAndCallHoward1 {
    mode = RI_GETEVENTS_HOWARD;
    
    [stop_after release];
    stop_after = [[self stepTime:lastgrab by:20] retain];
    
    [h_keys release];
    h_keys = [[[[sync allKeys] sortedArrayUsingFunction:keysSort context:sync] mutableCopy] retain];
    
    while ([h_keys count] > 20 && [(NSString *)([[sync objectForKey:[h_keys lastObject]] objectAtIndex:1]) compare:stop_after] == NSOrderedDescending) {
        [h_keys removeLastObject];
    }
    
    [self prepareAndCallHoward2];
}

-(void)prepareAndCallHoward2 {
    [progressText setStringValue:[NSString stringWithFormat:@"Fetching entries... (Howard-mode) %i",[h_keys count]]];
    if ([h_keys count] == 0) {
        [self prepareAndCallGetEventStep1];
        return;
    }
    
    NSNumber *num = [[h_keys objectAtIndex:0] retain];
    [h_keys removeObjectAtIndex:0];
    [sync removeObjectForKey:num];
    
    [DWXMLRPCRequest asyncRequestFor:user
                          withMethod:@"getevents"
                             andArgs:[NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithInt:1],@"ver",
                                      [num autorelease],@"itemid",
                                      @"one",@"selecttype",
                                      @"unix",@"lineendings",nil]
                        withDelegate:self andArg:nil];
}

-(void)asyncRequest:(DWXMLRPCRequest *)req didFailWithError: (NSError *)error {    
    [progress stopAnimation:self];
    [progressText setStringValue:@"Failed"];
}

-(NSString *)lastSync { return lastSync; }
-(void)setLastSync:(NSString *)ls {
    if (ls != lastSync) {
        [lastSync release];
        lastSync = [ls retain];
    }
}

-(NSNumber *)last_itemid { return last_itemid; }
-(void)setLast_itemid:(NSNumber *)ls {
    if (ls != last_itemid) {
        [last_itemid release];
        last_itemid = [ls retain];
    }
}

-(NSString *)lastgrab { return lastgrab; }
-(void)setLastgrab:(NSString *)ls {
    if (ls != lastgrab) {
        [lastgrab release];
        lastgrab = [ls retain];
    }
}

-(NSString *)username { return username; }
-(void)setUsername:(NSString *)un {
    [self willChangeValueForKey:@"username"];
    if (un != username) {
        [username release];
        username = [un retain];
    }
    [self didChangeValueForKey:@"username"];
}

-(NSString *)password { return password; }
-(void)setPassword:(NSString *)pw {
    [self willChangeValueForKey:@"password"];
    if (pw != password) {
        [password release];
        password = [pw retain];
    }
    [self didChangeValueForKey:@"password"];
}

@end
