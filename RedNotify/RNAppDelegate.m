//
//  Copyright (c) 2013 feedtailor Inc. All rights reserved.
//


#import "RNAppDelegate.h"
#import "AFNetworking.h"

// http://www.redmine.org/projects/redmine/wiki/Rest_api

#define REDMINE_URL @"http://www.example.com/redmine/"

@interface RNAppDelegate () <NSUserNotificationCenterDelegate>
{
    NSStatusItem* statusItem;
    __unsafe_unretained NSWindow *_logWindow;
}
@property (unsafe_unretained) IBOutlet NSWindow *prefWindow;
@property (unsafe_unretained) IBOutlet NSTextView *logView;
@property (unsafe_unretained) IBOutlet NSWindow *logWindow;
@property (weak) IBOutlet NSTextField *apiKeyFld;

@property (nonatomic, strong) AFHTTPClient* client;
@property (weak) IBOutlet NSMenu *statusMenu;
@property (nonatomic, strong) NSNumber* userId;
@property (nonatomic, strong) NSString* apiKey;

@end

@implementation RNAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    [statusItem setImage:[NSImage imageNamed:@"feed"]];
    [statusItem setAlternateImage:[NSImage imageNamed:@"feed-w"]];
    [statusItem setHighlightMode:YES];
    [statusItem setMenu:self.statusMenu];
 
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    self.apiKey = [defaults objectForKey:@"apiKey"];
    if (self.apiKey) {
        [self performSelector:@selector(loadUserInfo) withObject:nil afterDelay:0];
    } else {
        [self showPref:nil];
    }
}

- (IBAction)showPref:(id)sender
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    [NSApp activateIgnoringOtherApps:YES];
    [self.prefWindow makeKeyAndOrderFront:nil];
}

- (IBAction)ok:(id)sender
{
    [self.prefWindow orderOut:sender];
    self.apiKey = [self.apiKeyFld stringValue];
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.apiKey forKey:@"apiKey"];
    [defaults synchronize];
    
    [self loadUserInfo];
}

- (IBAction)doUpdate:(id)sender
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    if (self.apiKey) {
        if (self.userId) {
            [self update:sender];
        } else {
            [self loadUserInfo];
        }
    } else {
        [self showPref:nil];
    }
}

- (IBAction)showLog:(id)sender
{
    [NSApp activateIgnoringOtherApps:YES];
    [self.logWindow orderFront:sender];
}

-(void) loadUserInfo
{
    [self addLog:[NSString stringWithFormat:@"%s", __PRETTY_FUNCTION__]];
    if (!self.client) {
        self.client = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:REDMINE_URL]];
    }
    [self.client setDefaultHeader:@"X-Redmine-API-Key" value:self.apiKey];

    NSMutableURLRequest* req = [self.client requestWithMethod:@"GET" path:@"users/current.json" parameters:nil];
    [req setHTTPShouldHandleCookies:NO];
    AFJSONRequestOperation* op = [AFJSONRequestOperation JSONRequestOperationWithRequest:req success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        NSDictionary* user = [JSON objectForKey:@"user"];
        if (user) {
            self.userId = [user objectForKey:@"id"];
        }
        if (self.userId) {
            [self update:nil];
        } else {
            [self notifyError:@"cannot get user's info" informativeText:@""];
        }
        
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [self addLog:[error description]];
        [self notifyError:error];
    }];
    [self.client enqueueHTTPRequestOperation:op];
}

-(void) notifyError:(NSError*)error
{
    [self notifyError:[error localizedDescription] informativeText:[error localizedFailureReason]];
}

-(void) notifyError:(NSString*)description informativeText:(NSString*)informativeText
{
    NSUserNotification* not = [[NSUserNotification alloc] init];
    not.title = @"エラー";
    not.subtitle = description;
    not.informativeText = informativeText;
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:not];
}

-(void) update:(id)sender
{
    [self addLog:[NSString stringWithFormat:@"%s", __PRETTY_FUNCTION__]];
    
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy/MM/dd HH:mm:ss ZZZ"];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSDate* date = [defaults objectForKey:@"lastUpdated"];
    NSMutableURLRequest* req = [self.client requestWithMethod:@"GET" path:@"issues.json" parameters:@{@"assigned_to_id": self.userId}];
    [req setHTTPShouldHandleCookies:NO];
    AFJSONRequestOperation* op = [AFJSONRequestOperation JSONRequestOperationWithRequest:req success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        NSArray* issues = [JSON objectForKey:@"issues"];
        if (![issues isKindOfClass:[NSArray class]]) {
            [self waitNextUpdate];
            return;
        }
        
        for (NSDictionary* issue in issues) {
            NSDate* updated = [formatter dateFromString:[issue objectForKey:@"updated_on"]];
            if (date && [date compare:updated] == NSOrderedDescending) {
                continue;
            }
            
            NSString* issueId = [issue objectForKey:@"id"];
            [self loadIssue:issueId];
        }
        
        [defaults setObject:[NSDate date] forKey:@"lastUpdated"];
        [defaults synchronize];
        
        [self waitNextUpdate];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [self addLog:[error description]];
        [self notifyError:error];
        [self waitNextUpdate];
    }];
    [self.client enqueueHTTPRequestOperation:op];
}

-(void) loadIssue:(NSString*)issueId
{
    [self addLog:[NSString stringWithFormat:@"%s %@", __PRETTY_FUNCTION__, issueId]];

    NSMutableURLRequest* req = [self.client requestWithMethod:@"GET" path:[NSString stringWithFormat:@"issues/%@.json", issueId] parameters:@{@"include": @"journals"}];
    [req setHTTPShouldHandleCookies:NO];
    AFJSONRequestOperation* op = [AFJSONRequestOperation JSONRequestOperationWithRequest:req success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        NSDictionary* issue = [JSON objectForKey:@"issue"];
        NSArray* journals = [issue objectForKey:@"journals"];
        if (journals && [journals isKindOfClass:[NSArray class]] && [journals count] > 0) {
            NSDictionary* lastJournal = [journals lastObject];
            NSNumber* userId = [[lastJournal objectForKey:@"user"] objectForKey:@"id"];
            if ([self.userId isEqualToNumber:userId]) {
                // ignore if last updated by me
                return;
            }
        } else {
            // new issue
            NSNumber* authorId = [[issue objectForKey:@"author"] objectForKey:@"id"];
            if ([self.userId isEqualToNumber:authorId]) {
                // ignore if created by me
                return;
            }
        }
        
        NSString* track = [[issue objectForKey:@"tracker"] objectForKey:@"name"];
        NSString* status = [[issue objectForKey:@"status"] objectForKey:@"name"];
        NSString* proj = [[issue objectForKey:@"project"] objectForKey:@"name"];
        
        NSUserNotification* not = [[NSUserNotification alloc] init];
        not.title = [NSString stringWithFormat:@"%@ #%@:", track, issueId];
        not.subtitle = [NSString stringWithFormat:@"(%@) %@", status, proj];
        not.informativeText = [issue objectForKey:@"subject"];
        not.userInfo = @{@"issue":issueId};
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:not];

    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        // ignore
        [self addLog:[error description]];
    }];
    [self.client enqueueHTTPRequestOperation:op];
}

-(void) waitNextUpdate
{
    [self performSelector:@selector(update:) withObject:nil afterDelay:300];
}

-(void) userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    if (notification.userInfo) {
        NSString* issueId = [notification.userInfo objectForKey:@"issue"];
        if (issueId) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@issues/%@", REDMINE_URL, issueId]]];
        }
    }
    
    [center removeDeliveredNotification:notification];
}

-(void) addLog:(NSString*)msg
{
    self.logView.string = [self.logView.string stringByAppendingFormat:@"\n[%@] %@", [NSDate date], msg];
    [self.logView setSelectedRange:NSMakeRange([self.logView.string length], 0)];
}

@end
