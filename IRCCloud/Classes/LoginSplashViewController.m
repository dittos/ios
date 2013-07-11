//
//  LoginSplashViewController.m
//  IRCCloud
//
//  Created by Sam Steele on 2/19/13.
//  Copyright (c) 2013 IRCCloud, Ltd. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "LoginSplashViewController.h"
#import "UIColor+IRCCloud.h"

@implementation LoginSplashViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _conn = [NetworkConnection sharedInstance];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    username.borderStyle = password.borderStyle = UITextBorderStyleNone;
    username.background = password.background = [[UIImage imageNamed:@"textbg"] resizableImageWithCapInsets:UIEdgeInsetsMake(14, 14, 14, 14)];
    username.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, username.frame.size.height)];
    username.leftViewMode = UITextFieldViewModeAlways;
    username.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, username.frame.size.height)];
    username.rightViewMode = UITextFieldViewModeAlways;
    password.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, password.frame.size.height)];
    password.leftViewMode = UITextFieldViewModeAlways;
    password.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, password.frame.size.height)];
    password.rightViewMode = UITextFieldViewModeAlways;
    [login setBackgroundImage:[[UIImage imageNamed:@"sendbg_active"] resizableImageWithCapInsets:UIEdgeInsetsMake(14, 14, 14, 14)] forState:UIControlStateNormal];
    [login setBackgroundImage:[[UIImage imageNamed:@"sendbg"] resizableImageWithCapInsets:UIEdgeInsetsMake(14, 14, 14, 14)] forState:UIControlStateDisabled];
    [login setTitleColor:[UIColor selectedBlueColor] forState:UIControlStateNormal];
    [login setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
    [login setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];
    login.titleLabel.shadowOffset = CGSizeMake(0, 1);
    [login.titleLabel setFont:[UIFont fontWithName:@"Helvetica-Bold" size:14.0]];
    login.adjustsImageWhenDisabled = YES;
    login.adjustsImageWhenHighlighted = NO;
    login.enabled = NO;
    
    [version setText:[NSString stringWithFormat:@"Version %@",[[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleVersionKey]]];
}

-(void)viewWillAppear:(BOOL)animated {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateConnecting:)
                                                 name:kIRCCloudConnectivityNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleEvent:)
                                                 name:kIRCCloudEventNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillBeHidden:)
                                                 name:UIKeyboardWillHideNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backlogStarted:)
                                                 name:kIRCCloudBacklogStartedNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backlogProgress:)
                                                 name:kIRCCloudBacklogProgressNotification object:nil];

    NSString *session = [[NSUserDefaults standardUserDefaults] stringForKey:@"session"];
    if(session != nil && [session length] > 0) {
        if(_conn.state == kIRCCloudStateDisconnected) {
            loginView.alpha = 0;
            loadingView.alpha = 1;
            progress.hidden = YES;
            progress.progress = 0;
            [activity startAnimating];
            activity.hidden = NO;
            [status setText:@"Connecting"];
            [_conn connect];
        }
    } else {
        password.text = @"";
        loadingView.alpha = 0;
        loginView.alpha = 1;
    }
}

-(void)handleEvent:(NSNotification *)notification {
    kIRCEvent event = [[notification.userInfo objectForKey:kIRCCloudEventKey] intValue];
    IRCCloudJSONObject *o = nil;
    
    switch(event) {
        case kIRCEventFailureMsg:
            o = notification.object;
            if([[o objectForKey:@"message"] isEqualToString:@"auth"]) {
                [[NetworkConnection sharedInstance] unregisterAPNs:[[NSUserDefaults standardUserDefaults] objectForKey:@"APNs"]];
                //TODO: check the above result, and retry if it fails
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"APNs"];
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"session"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [_conn performSelectorOnMainThread:@selector(disconnect) withObject:nil waitUntilDone:YES];
                [_conn performSelectorOnMainThread:@selector(cancelIdleTimer) withObject:nil waitUntilDone:YES];
                [_conn clearPrefs];
                _conn.reconnectTimestamp = 0;
                [[ServersDataSource sharedInstance] clear];
                [[UsersDataSource sharedInstance] clear];
                [[ChannelsDataSource sharedInstance] clear];
                [[EventsDataSource sharedInstance] clear];
                [activity stopAnimating];
                loginView.alpha = 1;
                loadingView.alpha = 0;
            } else if([[o objectForKey:@"message"] isEqualToString:@"set_shard"]) {
                [[NSUserDefaults standardUserDefaults] setObject:[o objectForKey:@"cookie"] forKey:@"session"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                progress.hidden = YES;
                progress.progress = 0;
                [activity startAnimating];
                activity.hidden = NO;
                [status setText:@"Connecting"];
                [_conn connect];
            } else if([[o objectForKey:@"message"] isEqualToString:@"temp_unavailable"]) {
                error.text = @"Your account is temporarily unavailable";
                error.hidden = NO;
                CGRect frame = error.frame;
                frame.size.height = [error.text sizeWithFont:error.font constrainedToSize:CGSizeMake(frame.size.width,INT_MAX) lineBreakMode:error.lineBreakMode].height;
                error.frame = frame;
                [_conn disconnect];
                _conn.idleInterval = 30;
                [_conn scheduleIdleTimer];
            } else {
                error.text = [o objectForKey:@"message"];
                error.hidden = NO;
                CGRect frame = error.frame;
                frame.size.height = [error.text sizeWithFont:error.font constrainedToSize:CGSizeMake(frame.size.width,INT_MAX) lineBreakMode:error.lineBreakMode].height;
                error.frame = frame;
            }
            break;
        default:
            break;
    }
}

-(void)updateConnecting:(NSNotification *)notification {
    int state = _conn.state;
    if(_conn.state == kIRCCloudStateConnecting || [_conn reachable] == kIRCCloudUnknown) {
        [status setText:@"Connecting"];
        activity.hidden = NO;
        [activity startAnimating];
        progress.progress = 0;
        progress.hidden = YES;
        error.text = nil;
    } else if(_conn.state == kIRCCloudStateDisconnected) {
        if(_conn.reconnectTimestamp > 0) {
            int seconds = (int)(_conn.reconnectTimestamp - [[NSDate date] timeIntervalSince1970]) + 1;
            [status setText:[NSString stringWithFormat:@"Reconnecting in %i second%@", seconds, (seconds == 1)?@"":@"s"]];
            activity.hidden = NO;
            [activity startAnimating];
            progress.progress = 0;
            progress.hidden = YES;
            [self performSelector:@selector(updateConnecting:) withObject:nil afterDelay:1];
        } else {
            if([_conn reachable])
                [status setText:@"Disconnected"];
            else
                [status setText:@"Offline"];
            activity.hidden = YES;
            progress.progress = 0;
            progress.hidden = YES;
        }
    }
}

-(void)viewDidDisappear:(BOOL)animated {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)backlogStarted:(NSNotification *)notification {
#ifdef DEBUG
    NSLog(@"This is a debug build, skipping APNs registration");
#else
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound | UIRemoteNotificationTypeAlert)];
#endif
    [status setText:@"Loading"];
    activity.hidden = YES;
    progress.progress = 0;
    progress.hidden = NO;
}

-(void)backlogProgress:(NSNotification *)notification {
    [progress setProgress:[notification.object floatValue] animated:YES];
}

-(void)keyboardWillShow:(NSNotification*)notification {
    [UIView beginAnimations:nil context:nil];
    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        logo.frame = CGRectMake(112, 16, 96, 96);
        loginView.frame = CGRectMake(0, 112, 320, 160);
    } else {
        logo.frame = CGRectMake(128, 246-180, 256, 256);
        loginView.frame = CGRectMake(392, 302-180, 612, 144);
    }
    [UIView commitAnimations];
}

-(void)keyboardWillBeHidden:(NSNotification*)notification {
    [UIView beginAnimations:nil context:nil];
    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        logo.frame = CGRectMake(96, 36, 128, 128);
        loginView.frame = CGRectMake(0, 200, 320, 160);
    } else {
        logo.frame = CGRectMake(128, 246, 256, 256);
        loginView.frame = CGRectMake(392, 302, 612, 144);
    }
    [UIView commitAnimations];
}

-(void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(IBAction)loginButtonPressed:(id)sender {
    [username resignFirstResponder];
    [password resignFirstResponder];
    [UIView beginAnimations:nil context:nil];
    loginView.alpha = 0;
    loadingView.alpha = 1;
    [UIView commitAnimations];
    [status setText:@"Signing in"];
    progress.hidden = YES;
    progress.progress = 0;
    [activity startAnimating];
    activity.hidden = NO;
    error.text = nil;
    error.hidden = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *result = [[NetworkConnection sharedInstance] login:[username text] password:[password text]];
        if([[result objectForKey:@"success"] intValue] == 1) {
            [[NSUserDefaults standardUserDefaults] setObject:[result objectForKey:@"session"] forKey:@"session"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [status setText:@"Connecting"];
            [_conn connect];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [UIView beginAnimations:nil context:nil];
                loginView.alpha = 1;
                loadingView.alpha = 0;
                [UIView commitAnimations];
                NSString *message = @"Unable to login to IRCCloud.  Please check your username and password, and try again shortly.";
                if([[result objectForKey:@"message"] isEqualToString:@"auth"]
                   || [[result objectForKey:@"message"] isEqualToString:@"email"]
                   || [[result objectForKey:@"message"] isEqualToString:@"password"]
                   || [[result objectForKey:@"message"] isEqualToString:@"legacy_account"])
                    message = @"Incorrect username or password.  Please try again.";
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Login Failed" message:message delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
                [alert show];
            });
        }
    });
}

-(IBAction)textFieldChanged:(id)sender {
    login.enabled = (username.text.length > 0 && password.text.length > 0);
}

-(BOOL)textFieldShouldReturn:(UITextField *)textField {
    if(textField == username)
        [password becomeFirstResponder];
    else
        [self loginButtonPressed:textField];
    return YES;
}

@end
