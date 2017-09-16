#import "ParsePushPlugin.h"
#import <Cordova/CDV.h>

#import <Parse/Parse.h>

@implementation ParsePushPlugin

- (void)pluginInitialize {
    //store userInfo dictionaries if js callback is not yet registered.
    self.pnQueue = [NSMutableArray new];
    self.hasRegistered = false;
}

- (void)registerCallback: (CDVInvokedUrlCommand*)command
{
    //
    // Save callbackId to trigger later when PN arrives
    //
    //
    self.callbackId = command.callbackId;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];

    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];

    if(self.pnQueue && self.pnQueue.count && self.isParseInitialized){
        [self flushPushNotificationQueue];
    }
}

- (void)initParse:(CDVInvokedUrlCommand *)command
{
    if (!self.isParseInitialized) {
        @try {
            // test if Parse client has been initialized in the main AppDelegate.m
            NSLog(@"Custom Parse.Push init already took place. appId: %@", [Parse getApplicationId]);
            self.isParseInitialized = YES;

        } @catch (NSException *exception) {
            //
            // default Parse Push setup. For custom setup, initialize the Parse client and
            // notification settings yourself in your main AppDelegate.m 's didFinishLaunchingWithOptions
            //
            NSString *appId      = [self getConfigForKey:@"ParseAppId"];
            NSString *serverUrl  = [self getConfigForKey:@"ParseServerUrl"];
            NSString *clientKey  = [self getConfigForKey:@"ParseClientKey"];
            NSString *autoReg = [self getConfigForKey:@"ParseAutoRegistration"];

            if ([@"DYNAMIC" caseInsensitiveCompare:serverUrl] == NSOrderedSame) {
                if (command == nil) {
                    NSException* invalidSettingException = [NSException
                        exceptionWithName:@"invalidCallException"
                        reason:@"Cannot call initParse without command when ParseServerUrl is set to DYNAMIC."
                        userInfo:nil];
                    @throw invalidSettingException;
                }
                serverUrl = [command.arguments objectAtIndex:0];
                if (serverUrl == nil || !serverUrl.length) {
                    NSException* invalidSettingException = [NSException
                        exceptionWithName:@"invalidSettingException"
                        reason:@"ParseServerUrl set to DYNAMIC but no url recevied from JS."
                        userInfo:nil];
                    @throw invalidSettingException;
                }
            } else if (command != nil) {
                NSException* invalidSettingException = [NSException
                    exceptionWithName:@"invalidSettingException"
                    reason:@"Cannot call initParse when ParseServerUrl is not set to DYNAMIC."
                    userInfo:nil];
                @throw invalidSettingException;
            }

            if(!appId.length){
                NSException* invalidSettingException = [NSException
                    exceptionWithName:@"invalidSettingException"
                    reason:@"Please set \"appId\" with a preference tag in config.xml"
                    userInfo:nil];
                @throw invalidSettingException;
            }

            if(!serverUrl.length){
                NSException* invalidSettingException = [NSException
                    exceptionWithName:@"invalidSettingException"
                    reason:@"Please set \"ParseServerUrl\" with a preference tag in config.xml"
                    userInfo:nil];
                @throw invalidSettingException;
            }

            if( [@"PARSE_DOT_COM" caseInsensitiveCompare:serverUrl] == NSOrderedSame ) {
                //
                // initialize for use with parse.com
                //
                NSLog(@"ParsePushPlugin: Initializing SDK for Parse.com");
                [Parse setApplicationId:appId clientKey:clientKey];
            } else{
                //
                // initialize for use with opensource parse-server
                //
                NSLog(@"ParsePushPlugin: Initializing SDK with server '%@'", serverUrl);
                [Parse initializeWithConfiguration:[ParseClientConfiguration configurationWithBlock:^(id<ParseMutableClientConfiguration> configuration) {
                    configuration.applicationId = appId;
                    configuration.server = serverUrl;
                    configuration.clientKey = clientKey;
                }]];
            }

            UIApplication *application = [UIApplication sharedApplication];
            if(!autoReg.length || [autoReg caseInsensitiveCompare:@"true"] == 0 || [application isRegisteredForRemoteNotifications]){
                // if autoReg is true or nonexistent (defaults to true)
                // or app already registered for PN, do/redo registration
                //
                // Note: redo registration because APNS device token can change and Apple
                // suggests re-registering on each app start. registerForPN() is idempotent so
                // no worries if it gets called multiple times.
                [self registerForPN];
            }

            self.isParseInitialized = YES;

            if (self.updatedDeviceToken != nil) {
                [self saveDeviceTokenToInstallation:self.updatedDeviceToken];
                self.updatedDeviceToken = nil;
            }

            if (self.pnQueue && self.pnQueue.count && self.callbackId) {
                [self flushPushNotificationQueue];
            }
        }
    }

    if (command != nil) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (BOOL)ensureParseInitialized:(CDVInvokedUrlCommand *)command
{
    if (!self.isParseInitialized) {
        CDVPluginResult* pluginResult = [CDVPluginResult 
            resultWithStatus:CDVCommandStatus_ERROR 
            messageAsString:@"Parse SDK not yet initialized."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return NO;
    }
    return YES;
}

- (void)register:(CDVInvokedUrlCommand *)command
{
    if (![self ensureParseInitialized:command]) return;

    [self registerForPN];

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getInstallationId:(CDVInvokedUrlCommand*) command
{
    if (![self ensureParseInitialized:command]) return;

    [self.commandDelegate runInBackground:^{
        CDVPluginResult* pluginResult = nil;
        PFInstallation *currentInstallation = [PFInstallation currentInstallation];
        NSString *installationId = currentInstallation.installationId;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:installationId];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)getInstallationObjectId:(CDVInvokedUrlCommand*) command
{
    if (![self ensureParseInitialized:command]) return;

    [self.commandDelegate runInBackground:^{
        CDVPluginResult* pluginResult = nil;
        PFInstallation *currentInstallation = [PFInstallation currentInstallation];
        NSString *objectId = currentInstallation.objectId;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:objectId];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)getSubscriptions: (CDVInvokedUrlCommand *)command
{
    if (![self ensureParseInitialized:command]) return;

    NSArray *channels = [PFInstallation currentInstallation].channels;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:channels];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)subscribe: (CDVInvokedUrlCommand *)command
{
    if (![self ensureParseInitialized:command]) return;

    CDVPluginResult* pluginResult = nil;
    PFInstallation *currentInstallation = [PFInstallation currentInstallation];
    NSString *channel = [command.arguments objectAtIndex:0];
    [currentInstallation addUniqueObject:channel forKey:@"channels"];
    [currentInstallation saveInBackground];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)unsubscribe: (CDVInvokedUrlCommand *)command
{
    if (![self ensureParseInitialized:command]) return;

    CDVPluginResult* pluginResult = nil;
    PFInstallation *currentInstallation = [PFInstallation currentInstallation];
    NSString *channel = [command.arguments objectAtIndex:0];
    [currentInstallation removeObject:channel forKey:@"channels"];
    [currentInstallation saveInBackground];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)resetBadge:(CDVInvokedUrlCommand *)command {
    if (![self ensureParseInitialized:command]) return;

    CDVPluginResult* pluginResult = nil;
    PFInstallation *currentInstallation = [PFInstallation currentInstallation];
    currentInstallation.badge = 0;

    [currentInstallation saveInBackground];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


- (void)registerForPN {
    //
    // carries out the actual device registration for push notification
    //
    UIApplication *application = [UIApplication sharedApplication];

    if(!self.hasRegistered){
        NSLog(@"ParsePushPlugin is registering your device for PN");

        if (IsAtLeastiOSVersion(@"10.0")) {

            UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
            center.delegate = self;

            [center requestAuthorizationWithOptions:(UNAuthorizationOptionSound | UNAuthorizationOptionAlert | UNAuthorizationOptionBadge) completionHandler:^(BOOL granted, NSError * _Nullable error){
                if( !error ){
                    [application registerForRemoteNotifications];
                }
            }];

        }
        else if (IsAtLeastiOSVersion(@"8.0")) {

            if ([application respondsToSelector:@selector(registerUserNotificationSettings:)]) {
                UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound categories:nil];
                [application registerUserNotificationSettings:settings];
                [application registerForRemoteNotifications];
            }

        }

        self.hasRegistered = true;
    }
}

- (void)jsCallback: (NSDictionary*)userInfo withAction: (NSString*)pnAction
{
   //
   // format the pn payload to be just 1 level deep and consistent with other platform versions of this plugin
   NSMutableDictionary* pnPayload = [NSMutableDictionary dictionaryWithDictionary:userInfo];
   [pnPayload addEntriesFromDictionary:pnPayload[@"aps"]];
   [pnPayload removeObjectForKey:@"aps"];

   NSArray* callbackArgs = [NSArray arrayWithObjects:pnPayload, pnAction, nil];
   CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsMultipart:callbackArgs];
   [pluginResult setKeepCallbackAsBool:YES];

   if(self.callbackId){
      [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
   } else{
      //
      //callback has not been registered by the js side,
      //queue things up so it can be flushed when js callback is registered.
      //cap queue size at reasonable number
      //
      if(self.pnQueue.count <= 10){
         [self.pnQueue addObject:pluginResult];
      }
   }
}

- (void)flushPushNotificationQueue
{
   while(self.pnQueue && self.pnQueue.count){
      //
      // de-queue the oldest pn and trigger callback
      CDVPluginResult* pluginResult = self.pnQueue[0];
      [self.pnQueue removeObjectAtIndex:0];

      [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
   }
}

- (NSString *)getConfigForKey:(NSString *)key
{
   //
   // get config.xml <preference> settings
   //
   return [self.commandDelegate.settings objectForKey:[key lowercaseString]];
}

- (void)saveDeviceTokenToInstallation: (NSData*)deviceToken
{
    if (self.isParseInitialized) {
        PFInstallation *currentInstallation = [PFInstallation currentInstallation];
        [currentInstallation setDeviceTokenFromData:deviceToken];
        [currentInstallation saveInBackground];
    } else {
        self.updatedDeviceToken = deviceToken;
    }
}

-(void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    NSLog(@"User info %@", notification.request.content.userInfo);

    UIApplication *application = [UIApplication sharedApplication];
    [self jsCallback:notification.request.content.userInfo withAction:(application.applicationState == UIApplicationStateActive) ? @"RECEIVE" : @"OPEN"];

    completionHandler(UNNotificationPresentationOptionAlert);
}

-(void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)())completionHandler {
    NSLog(@"User info %@", response.notification.request.content.userInfo);
    
    [self jsCallback:response.notification.request.content.userInfo withAction: @"OPEN"];
    
    completionHandler();
}

@end
