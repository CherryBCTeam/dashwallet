//
//  ZNFirstViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "ZNPayViewController.h"
#import "ZNAmountViewController.h"
#import "ZNWallet.h"
#import "ZNPaymentRequest.h"
#import "ZNKey.h"
#import "ZNTransaction.h"
#import "ZNButton.h"
#import "ZNStoryboardSegue.h"
#import <QuartzCore/QuartzCore.h>
#import "NSString+Base58.h"
#import "MBProgressHUD.h"

#define BUTTON_HEIGHT 44.0
#define BUTTON_MARGIN 10.0

//#define CONNECT_TIMEOUT 5.0

#define CLIPBOARD_ID    @"clipboard"
#define QR_ID           @"qr"
#define URL_ID          @"url"
#define CLIPBOARD_LABEL @"pay address from clipboard"

@interface ZNPayViewController ()

//@property (nonatomic, strong) GKSession *session;
@property (nonatomic, strong) NSMutableArray *requests;
@property (nonatomic, strong) NSMutableArray *requestIDs;
@property (nonatomic, strong) NSMutableArray *requestButtons;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, strong) NSString *addressInWallet;
@property (nonatomic, strong) id urlObserver, activeObserver;
@property (nonatomic, strong) ZNTransaction *sweepTx;

@property (nonatomic, strong) IBOutlet UILabel *label;
@property (nonatomic, strong) IBOutlet UIButton *infoButton;

@property (nonatomic, strong) ZBarReaderViewController *zbarController;
//@property (nonatomic, strong) Reachability *reachability;

@end

@implementation ZNPayViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    //TODO: add a field for manually entering a payment address
    //TODO: make title use dynamic font size
    //BUG: clipboard button title is offcenter (ios7 specific font layout bug?)
    ZNPaymentRequest *req = [ZNPaymentRequest new];
    ZNWallet *w = [ZNWallet sharedInstance];
    
    req.label = @"scan QR code";
    
    self.requests = [NSMutableArray arrayWithObject:req];
    self.requestIDs = [NSMutableArray arrayWithObject:QR_ID];
    self.requestButtons = [NSMutableArray array];
    self.selectedIndex = NSNotFound;
    
    self.infoButton.frame = CGRectMake(self.infoButton.frame.origin.x, self.infoButton.frame.origin.y, 16.0, 16.0);
    
    self.urlObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:bitcoinURLNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            ZNPaymentRequest *req = [ZNPaymentRequest requestWithURL:note.userInfo[@"url"]];
        
            if (! req.label.length) req.label = req.paymentAddress;
            
            if (req.amount > 0 && [req.label rangeOfString:[w stringForAmount:req.amount]].location == NSNotFound) {
                req.label = [NSString stringWithFormat:@"%@ - %@", req.label,
                             [[ZNWallet sharedInstance] stringForAmount:req.amount]];
            }
        
            if ([self.requestIDs indexOfObject:URL_ID] != NSNotFound) {
                [self.requests removeObjectAtIndex:[self.requestIDs indexOfObject:URL_ID]];
                [self.requestIDs removeObjectAtIndex:[self.requestIDs indexOfObject:URL_ID]];
            }
        
            [self.requests insertObject:req atIndex:0];
            [self.requestIDs insertObject:URL_ID atIndex:0];
            [self layoutButtonsAnimated:YES];
        }];
    
    self.activeObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [self layoutButtonsAnimated:YES]; // check the clipboard for changes
        }];
    
}

- (void)dealloc
{
    if (self.urlObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.urlObserver];
    if (self.activeObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
 
//    self.session = [[GKSession alloc] initWithSessionID:GK_SESSION_ID
//                    displayName:[UIDevice.currentDevice.name stringByAppendingString:@" Wallet"]
//                    sessionMode:GKSessionModeClient];
//    self.session.delegate = self;
//    [self.session setDataReceiveHandler:self withContext:nil];
//    self.session.available = YES;

    [self layoutButtonsAnimated:NO];
}

//- (void)viewWillDisappear:(BOOL)animated
//{
//    [super viewWillDisappear:animated];
//
//    self.session.available = NO;
//    [self.session disconnectFromAllPeers];
//    self.session = nil;
//}

- (void)layoutButtonsAnimated:(BOOL)animated
{
    ZNWallet *w = [ZNWallet sharedInstance];
    ZNPaymentRequest *req = [ZNPaymentRequest requestWithString:[[UIPasteboard generalPasteboard] string]];
    
    if (! req.isValid) {
        req.paymentAddress = nil;
        req.label = CLIPBOARD_LABEL;
    }
    else if (req.amount > 0 && [req.label rangeOfString:[w stringForAmount:req.amount]].location == NSNotFound) {
        req.label = [NSString stringWithFormat:@"%@ - %@", req.label, [w stringForAmount:req.amount]];
    }
    else if (! req.label.length) req.label = req.paymentAddress;
    
    if ([self.requestIDs indexOfObject:CLIPBOARD_ID] == NSNotFound) {
        [self.requests addObject:req];
        [self.requestIDs addObject:CLIPBOARD_ID];
    }
    else [self.requests replaceObjectAtIndex:[self.requestIDs indexOfObject:CLIPBOARD_ID] withObject:req];

    while (self.requests.count > self.requestButtons.count) {
        ZNButton *button = [ZNButton buttonWithType:UIButtonTypeCustom];

        button.style = ZNButtonStyleBlue;
        button.imageEdgeInsets = UIEdgeInsetsMake(0, -10, 0, 10);
        button.alpha = animated ? 0 : 1;
        button.frame =
            CGRectMake(BUTTON_MARGIN*2, self.view.frame.size.height/2 +
                       (BUTTON_HEIGHT + BUTTON_MARGIN*2)*(self.requestButtons.count - self.requests.count/2.0 - 0.5),
                       self.view.frame.size.width - BUTTON_MARGIN*4, BUTTON_HEIGHT);
        [button addTarget:self action:@selector(doIt:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:button];
        [self.requestButtons addObject:button];
    }

    void (^block)(void) = ^{
        [self.requestButtons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            CGPoint c = CGPointMake([obj center].x, self.view.frame.size.height/2 +
                                    (BUTTON_HEIGHT + BUTTON_MARGIN*2)*(idx - self.requests.count/2.0));
            
            [obj setCenter:c];
            
            if (self.selectedIndex != NSNotFound) {
                [obj setEnabled:NO];
                [obj setAlpha:idx < self.requests.count ? 0.5 : 0];
            }
            else {
                [obj setEnabled:YES];
                [obj setAlpha:idx < self.requests.count ? 1 : 0];
            }

            if (idx < self.requests.count) {
                ZNPaymentRequest *req = self.requests[idx];

                [obj setTitle:req.label forState:UIControlStateNormal];
                
                if ([req.label rangeOfString:BTC].location != NSNotFound) {
                    [obj titleLabel].font = [UIFont fontWithName:@"HelveticaNeue" size:15];
                }
                else [obj titleLabel].font = [UIFont fontWithName:@"HelveticaNeue-Light" size:17];

                if ([self.addressInWallet isEqual:req.paymentAddress]) [obj setEnabled:NO];
            }
            
            if ([self.requestIDs[idx] isEqual:QR_ID]) {
                [obj setImage:[UIImage imageNamed:@"cameraguide-blue-small.png"] forState:UIControlStateNormal];
                [obj setImage:[UIImage imageNamed:@"cameraguide-small.png"] forState:UIControlStateHighlighted];
            }
            else {
                [obj setImage:nil forState:UIControlStateNormal];
                [obj setImage:nil forState:UIControlStateHighlighted];
            }
        }];
        
        self.label.center = CGPointMake(self.label.center.x,
                                        [self.requestButtons[0] center].y - BUTTON_HEIGHT - BUTTON_MARGIN/2);
        self.infoButton.center = CGPointMake(self.infoButton.center.x, self.label.center.y + 1.0);
    };
    
    if (animated) {
        [UIView animateWithDuration:SEGUE_DURATION animations:block completion:^(BOOL finished) {
            while (self.requestButtons.count > self.requests.count) {
                [self.requestButtons.lastObject removeFromSuperview];
                [self.requestButtons removeLastObject];
            }
        }];
    }
    else {
        block();

        while (self.requestButtons.count > self.requests.count) {
            [self.requestButtons.lastObject removeFromSuperview];
            [self.requestButtons removeLastObject];
        }
    }
}

- (void)confirmRequest:(ZNPaymentRequest *)request
{
    if (! request.isValid) {
        if ([request.label isEqual:CLIPBOARD_LABEL]) {
            [[[UIAlertView alloc] initWithTitle:nil message:@"The clipboard doesn't contain a valid bitcoin address."
              delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:@"Not a valid bitcoin address." message:request.paymentAddress
              delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }

        self.selectedIndex = NSNotFound;
        return;
    }
    
    ZNWallet *w = [ZNWallet sharedInstance];
    
    if ([w containsAddress:request.paymentAddress]) {
        [[[UIAlertView alloc] initWithTitle:nil message:@"This payment address is already in your wallet." delegate:nil
          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        
        self.addressInWallet = request.paymentAddress;
        self.selectedIndex = NSNotFound;
    }
    else if (request.amount == 0) {
        ZNAmountViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"ZNAmountViewController"];
            
        c.request = request;
        c.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [w stringForAmount:w.balance],
                                  [w localCurrencyStringForAmount:w.balance]];
        
        [ZNStoryboardSegue segueFrom:self.navigationController.topViewController to:c];
            
        self.selectedIndex = NSNotFound;
    }
    else if (request.amount < TX_MIN_OUTPUT_AMOUNT) {
        [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment"
          message:[@"Bitcoin payments can't be less than "
                   stringByAppendingString:[w stringForAmount:TX_MIN_OUTPUT_AMOUNT]]
          delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        self.selectedIndex = NSNotFound;
    }
    else {
        ZNTransaction *tx = [w transactionFor:request.amount to:request.paymentAddress withFee:NO];
        ZNTransaction *txWithFee = [w transactionFor:request.amount to:request.paymentAddress withFee:YES];
        
        uint64_t txFee = [w transactionFee:txWithFee];
        NSString *fee = [w stringForAmount:txFee];
        NSString *localCurrencyFee = [w localCurrencyStringForAmount:txFee];
        NSTimeInterval t = [w timeUntilFree:tx];
        
        if (! txWithFee) fee = [w stringForAmount:tx.standardFee];
        
        if (! tx) {
            [[[UIAlertView alloc] initWithTitle:@"Insuficient Funds" message:nil delegate:nil cancelButtonTitle:@"OK"
              otherButtonTitles:nil] show];
            self.selectedIndex = NSNotFound;
        }
        else if (t == DBL_MAX) {
            [[[UIAlertView alloc] initWithTitle:@"transaction fee needed"
              message:[NSString stringWithFormat:@"the bitcoin network needs a fee of %@ (%@) to send this payment",
                       fee, localCurrencyFee] delegate:self cancelButtonTitle:@"cancel"
              otherButtonTitles:[NSString stringWithFormat:@"+ %@ (%@)", fee, localCurrencyFee], nil] show];
        }
        else if (t > DBL_EPSILON) {
            NSUInteger minutes = t/60, hours = t/(60*60), days = t/(60*60*24);
            NSString *time = [NSString stringWithFormat:@"%d %@%@", days ? days : (hours ? hours : minutes),
                              days ? @"day" : (hours ? @"hour" : @"minutes"),
                              days > 1 ? @"s" : (days == 0 && hours > 1 ? @"s" : @"")];
            
            [[[UIAlertView alloc]
              initWithTitle:[NSString stringWithFormat:@"%@ (%@) transaction fee recommended", fee, localCurrencyFee]
              message:[NSString stringWithFormat:@"estimated confirmation time with no fee: %@", time] delegate:self
              cancelButtonTitle:nil otherButtonTitles:@"no fee",
              [NSString stringWithFormat:@"+ %@ (%@)", fee, localCurrencyFee], nil] show];
        }
        else {            
            NSString *amount = [NSString stringWithFormat:@"%@ (%@)", [w stringForAmount:request.amount],
                                [w localCurrencyStringForAmount:request.amount]];

            [[[UIAlertView alloc] initWithTitle:@"Confirm Payment"
              message:request.message ? request.message : request.paymentAddress delegate:self
             cancelButtonTitle:@"cancel" otherButtonTitles:amount, nil] show];
        }
    }
}

- (void)confirmSweep:(NSString *)privKey
{
    if (! [privKey isValidBitcoinPrivateKey]) return;
    
    ZNWallet *w = [ZNWallet sharedInstance];
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    
    hud.mode = MBProgressHUDModeIndeterminate;
    hud.labelText = @"checking private key balance...";
    hud.labelFont = [UIFont fontWithName:@"HelveticaNeue" size:15.0];

    [w sweepPrivateKey:privKey withFee:YES completion:^(ZNTransaction *tx, NSError *error) {
        [hud hide:YES];

        if (error) {
            [[[UIAlertView alloc] initWithTitle:nil message:error.localizedDescription delegate:self
              cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            return;
        }
        
        __block uint64_t fee = tx.standardFee, amount = fee;
        
        [tx.outputAmounts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            amount += [obj unsignedLongLongValue];
        }];

        self.sweepTx = tx;
        [[[UIAlertView alloc] initWithTitle:nil
         message:[NSString stringWithFormat:@"Sweep %@ (%@) from this private key into your wallet? "
         "The bitcoin network will receive a fee of %@ (%@).", [w stringForAmount:amount],
         [w localCurrencyStringForAmount:amount], [w stringForAmount:fee], [w localCurrencyStringForAmount:fee]]
         delegate:self cancelButtonTitle:@"cancel" otherButtonTitles:[NSString stringWithFormat:@"%@ (%@)",
         [w stringForAmount:amount], [w localCurrencyStringForAmount:amount]], nil] show];
    }];
}

#pragma mark - IBAction

- (IBAction)info:(id)sender
{
    
}

- (IBAction)doIt:(id)sender
{
    self.selectedIndex = [self.requestButtons indexOfObject:sender];
    
    if (self.selectedIndex == NSNotFound) {
        NSAssert(FALSE, @"%s:%d %s: selectedIndex = NSNotFound", __FILE__, __LINE__,  __func__);
        return;
    }
    
    if ([self.requestIDs[self.selectedIndex] isEqual:QR_ID]) {
        self.selectedIndex = NSNotFound;

        self.zbarController = [ZBarReaderViewController new];
        self.zbarController.readerDelegate = self;
        self.zbarController.cameraOverlayView =
            [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"cameraguide.png"]];
        
        CGPoint c = self.zbarController.view.center;
        
        self.zbarController.cameraOverlayView.center = CGPointMake(c.x, c.y - 10.0);
        [self.navigationController presentViewController:self.zbarController animated:YES completion:^{
            NSLog(@"present qr reader complete");
        }];
        
        for (UIView *v in self.zbarController.view.subviews) {
            for (id t in v.subviews) {
                if ([t isKindOfClass:[UIToolbar class]] && [[t items] count] > 0) {
                    [t setItems:@[[t items][0]]];
                }
            }
        }
    }
    else {
        [sender setEnabled:NO];
        [self confirmRequest:self.requests[self.selectedIndex]];
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        self.sweepTx = nil;
        self.selectedIndex = NSNotFound;
        [self layoutButtonsAnimated:YES];
        return;
    }
    
    ZNWallet *w = [ZNWallet sharedInstance];
    
    if (self.sweepTx) {
        [w publishTransaction:self.sweepTx completion:^(NSError *error) {
            self.selectedIndex = NSNotFound;
            [self layoutButtonsAnimated:YES];
            
            if (error) {
                [[[UIAlertView alloc] initWithTitle:@"Couldn't sweep balance." message:error.localizedDescription
                  delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
                return;
            }
            
            MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
            
            hud.mode = MBProgressHUDModeText;
            hud.labelText = @"swept!";
            hud.labelFont = [UIFont fontWithName:@"HelveticaNeue-Medium" size:17.0];
            [hud hide:YES afterDelay:2.0];
        }];
        
        self.sweepTx = nil;
        return;
    }
    else if (self.selectedIndex == NSNotFound) return;

    ZNPaymentRequest *request = self.requests[self.selectedIndex];
    ZNTransaction *tx = [w transactionFor:request.amount to:request.paymentAddress withFee:NO];
    ZNTransaction *txWithFee = [w transactionFor:request.amount to:request.paymentAddress withFee:YES];
    NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
    
    if ([title hasPrefix:@"+ "] || [title isEqual:@"no fee"]) {
        if ([title hasPrefix:@"+ "]) tx = txWithFee;
        
        if (! tx) {
            [[[UIAlertView alloc] initWithTitle:@"Insuficient Funds" message:nil delegate:nil cancelButtonTitle:@"OK"
              otherButtonTitles:nil] show];
            self.selectedIndex = NSNotFound;
            [self layoutButtonsAnimated:YES];
            return;
        }

        uint64_t total = request.amount + [w transactionFee:tx];
        NSString *amount = [NSString stringWithFormat:@"%@ (%@)", [w stringForAmount:total],
                            [w localCurrencyStringForAmount:total]];

        [[[UIAlertView alloc] initWithTitle:@"Confirm Payment"
          message:request.message ? request.message : request.paymentAddress delegate:self
          cancelButtonTitle:@"cancel" otherButtonTitles:amount, nil] show];
        return;
    }

    if ([w amountForString:title] > request.amount) tx = txWithFee;
    
    NSLog(@"signing transaction");
    [w signTransaction:tx];
    
    if (! [tx isSigned]) {
        [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:@"error signing bitcoin transaction"
          delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        self.selectedIndex = NSNotFound;
        [self layoutButtonsAnimated:YES];
        return;
    }

    NSLog(@"signed transaction:\n%@", [tx toHex]);
        
    if (self.selectedIndex == NSNotFound || [self.requestIDs[self.selectedIndex] isEqual:QR_ID] ||
        [self.requestIDs[self.selectedIndex] isEqual:CLIPBOARD_ID]) {
        
        //TODO: check for duplicate transactions
        [w publishTransaction:tx completion:^(NSError *error) {
            if (error) {
                [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:error.localizedDescription
                  delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
                self.selectedIndex = NSNotFound;
                [self layoutButtonsAnimated:YES];
                return;
            }
            
            MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];

            hud.mode = MBProgressHUDModeText;
            hud.labelText = @"sent!";
            hud.labelFont = [UIFont fontWithName:@"HelveticaNeue-Medium" size:17.0];
            [hud hide:YES afterDelay:2.0];
        }];
    }
//    else { // this should be wrapped in #ifdef for bluetooth support
//        NSLog(@"sending signed request to %@", self.requestIDs[self.selectedIndex]);
//        
//        NSError *error = nil;
//        
//        [self.session sendData:[[tx toHex] dataUsingEncoding:NSUTF8StringEncoding]
//         toPeers:@[self.requestIDs[self.selectedIndex]] withDataMode:GKSendDataReliable error:&error];
//    
//        if (error) {
//            [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:error.localizedDescription delegate:nil
//             cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
//        }
//    
//        [self.requestIDs removeObjectAtIndex:self.selectedIndex];
//        [self.requests removeObjectAtIndex:self.selectedIndex];
//    }

    self.selectedIndex = NSNotFound;
    
    [self layoutButtonsAnimated:YES];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)reader didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    ZNPaymentRequest *req = self.requests[[self.requestIDs indexOfObject:QR_ID]];

    for (id result in info[ZBarReaderControllerResults]) {
        NSString *s = (id)[result data];

        req.data = [s dataUsingEncoding:NSUTF8StringEncoding];
        req.label = @"scan QR code";
        
        if (! req.paymentAddress && ! [s isValidBitcoinPrivateKey]) {
            [[[UIAlertView alloc] initWithTitle:@"not a bitcoin QR code" message:nil delegate:nil
              cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
        else {
            [(id)self.zbarController.cameraOverlayView setImage:[UIImage imageNamed:@"cameraguide-green.png"]];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                self.selectedIndex = [self.requestIDs indexOfObject:QR_ID];
                if (req.paymentAddress) [self confirmRequest:req];
                else [self confirmSweep:s];
                [reader dismissViewControllerAnimated:YES completion:nil];
                self.zbarController = nil;
            });
        }
        
        break;
    }
}

//#pragma mark - GKSessionDelegate
//
//// Indicates a state change for the given peer.
//- (void)session:(GKSession *)session peer:(NSString *)peerID didChangeState:(GKPeerConnectionState)state
//{
//    NSLog(@"%@ didChangeState:%@", peerID, state == GKPeerStateAvailable ? @"available" :
//          state == GKPeerStateUnavailable ? @"unavailable" :
//          state == GKPeerStateConnecting ? @"connecting" :
//          state == GKPeerStateConnected ? @"connected" :
//          state == GKPeerStateDisconnected ? @"disconnected" : @"unkown");
//    
//    if (state == GKPeerStateAvailable) {
//        if (! [self.requestIDs containsObject:peerID]) {
//            [self.requestIDs addObject:peerID];
//            [self.requests addObject:[ZNPaymentRequest new]];
//            
//            [session connectToPeer:peerID withTimeout:CONNECT_TIMEOUT];
//            
//            [self layoutButtonsAnimated:YES];
//        }
//    }
//    else if (state == GKPeerStateUnavailable || state == GKPeerStateDisconnected) {
//        if ([self.requestIDs containsObject:peerID]) {
//            NSUInteger idx = [self.requestIDs indexOfObject:peerID];
//            
//            [self.requestIDs removeObjectAtIndex:idx];
//            [self.requests removeObjectAtIndex:idx];
//            [self layoutButtonsAnimated:YES];
//        }
//    }
//}
//
//// Indicates a connection request was received from another peer.
////
//// Accept by calling -acceptConnectionFromPeer:
//// Deny by calling -denyConnectionFromPeer:
//- (void)session:(GKSession *)session didReceiveConnectionRequestFromPeer:(NSString *)peerID
//{
//    NSAssert(FALSE, @"%s:%d %s: recieved connection request (not in client mode)", __FILE__, __LINE__,  __func__);
//    return;
//    
//    
//    [session denyConnectionFromPeer:peerID];
//}
//
//// Indicates a connection error occurred with a peer, including connection request failures or timeouts.
//- (void)session:(GKSession *)session connectionWithPeerFailed:(NSString *)peerID withError:(NSError *)error
//{
//    [[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:error.localizedDescription delegate:nil
//                      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
//    
//    if (self.selectedIndex != NSNotFound && [self.requestIDs[self.selectedIndex] isEqual:peerID]) {
//        self.selectedIndex = NSNotFound;
//    }
//    
//    if ([self.requestIDs containsObject:peerID]) {
//        NSUInteger idx = [self.requestIDs indexOfObject:peerID];
//        
//        [self.requestIDs removeObjectAtIndex:idx];
//        [self.requests removeObjectAtIndex:idx];
//        [self layoutButtonsAnimated:YES];
//    }
//}
//
//// Indicates an error occurred with the session such as failing to make available.
//- (void)session:(GKSession *)session didFailWithError:(NSError *)error
//{
//    if (self.selectedIndex != NSNotFound && ! [self.requestIDs[self.selectedIndex] isEqual:CLIPBOARD_ID] &&
//        ! [self.requestIDs[self.selectedIndex] isEqual:QR_ID]) {
//        self.selectedIndex = NSNotFound;
//    }
//    
//    NSIndexSet *indexes =
//        [self.requestIDs indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
//            return ! [obj isEqual:CLIPBOARD_ID] && ! [obj isEqual:QR_ID];
//        }];
//    
//    [self.requestIDs removeObjectsAtIndexes:indexes];
//    [self.requests removeObjectsAtIndexes:indexes];
//    
//    [self layoutButtonsAnimated:YES];
//    
//    //[[[UIAlertView alloc] initWithTitle:@"Couldn't make payment" message:error.localizedDescription delegate:nil
//    //                  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
//}
//
//- (void)receiveData:(NSData *)data fromPeer:(NSString *)peer inSession:(GKSession *)session context:(void *)context
//{
//    NSUInteger idx = [self.requestIDs indexOfObject:peer];
//    
//    if (idx == NSNotFound) {
//        NSAssert(FALSE, @"%s:%d %s: idx = NSNotFound", __FILE__, __LINE__,  __func__);
//        return;
//    }
//    
//    ZNPaymentRequest *req = self.requests[idx];
//    
//    [req setData:data];
//    
//    if (! req.valid) {
//        [[[UIAlertView alloc] initWithTitle:@"Couldn't validate payment request"
//                                    message:@"The payment reqeust did not contain a valid merchant signature" delegate:self
//                          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
//        
//        if (self.selectedIndex == idx) {
//            self.selectedIndex = NSNotFound;
//        }
//        
//        [self.requestIDs removeObjectAtIndex:idx];
//        [self.requests removeObjectAtIndex:idx];
//        [self layoutButtonsAnimated:YES];
//        
//        return;
//    }
//    
//    NSLog(@"got payment reqeust for %@", peer);
//    NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
//    
//    if (self.selectedIndex == idx) [self confirmRequest:req];
//}

@end
