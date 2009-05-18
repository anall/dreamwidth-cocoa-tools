//
//  AppController.h
//  RemoveImported
//
//  Created by Andrea Nall on 5/17/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Dreamwidth/Dreamwidth.h>

typedef enum {
    RI_SYNCITEMS,
    RI_GETEVENTS,
    RI_GETEVENTS_HOWARD,
    RI_EATING,
} RIMode;

@interface AppController : NSObject<DWUserDelegate, DWXMLRPCRequestDelegate> {
    NSObject *__ttw;
    NSDictionary *__first;
    
    NSString *username;
    NSString *password;
    IBOutlet NSProgressIndicator *progress;
    IBOutlet NSTextField *progressText;
    
    IBOutlet NSButton *goButton;
    IBOutlet NSButton *deleteButton;
    
    DWUser *user;
    
    // Mode
    RIMode mode;
    
    // syncitem things
    NSString *lastSync;
    NSMutableDictionary *triedSyncs;
    NSMutableDictionary *sync;

    NSMutableArray *events;
    
    // getevent/editevent
    int tries;
    int count;
    NSNumber *last_itemid;
    NSString *lastgrab;
    
    // getevent "Howard"
    NSMutableArray *h_keys;
    NSString *stop_after;
    
    // count imported
    NSMutableArray *importedEvents;
}

-(IBAction)doIt:(id)sender;
-(IBAction)deleteEm:(id)sender;

-(NSString *)username;
-(void)setUsername:(NSString *)un;

-(NSString *)password;
-(void)setPassword:(NSString *)pw;

@end
