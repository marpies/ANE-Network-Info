/*
 * Copyright 2017 FreshPlanet
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#import "AirNetworkInfo.h"
#import "Reachability.h"

#include <net/if_dl.h>
#include <ifaddrs.h>
#include <sys/ioctl.h>
#include <arpa/inet.h>
#include <net/if.h>

@implementation NetworkInfoiOSLibrary

- (id)initWithContext:(FREContext)extensionContext {
    
    if (self = [super init])
        _context = extensionContext;
    
    return self;
}

- (void)sendLog:(NSString*)log {
    
    [self sendEvent:@"log" level:log];
}

- (void)sendEvent:(NSString*)code {
    
    [self sendEvent:code level:@""];
}

- (void)sendEvent:(NSString*)code level:(NSString*)level {
    
    if (FREDispatchStatusEventAsync(_context, (const uint8_t*) [code UTF8String], (const uint8_t*) [level UTF8String]) != FRE_OK)
        NSLog(@"FREDispatchStatusEventAsync ERROR code: %@ level: %@", code, level);
}

- (void)startNetworkChangeNotifier {
    
    if (!_reachability)
        _reachability = [Reachability reachabilityForInternetConnection];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleNetworkChange:)
                                                 name:kReachabilityChangedNotification
                                               object:nil];
    
    if (_reachability)
        [_reachability startNotifier];
}

- (void)stopNetworkChangeNotifier {
    
    if (_reachability)
        [_reachability stopNotifier];
}

- (void)handleNetworkChange:(NSNotification*)notif {
    
    [self sendEvent:@"networkChange"];
}

- (int)getConnectivityStatus {
    
    NetworkStatus netStatus = [_reachability currentReachabilityStatus];
    
    return netStatus;
}

@end


DEFINE_ANE_FUNCTION(getInterfaces) {
    
    FREObject NetworkInterfaceArray[6];
    FREObject InterfacePropArray = NULL;
    
    struct ifaddrs* ifAddrStruct = NULL;
    struct ifaddrs* ifa = NULL;
    BOOL flag = FALSE;
    
    FREObject tempNetworkInterface = NULL;
    FREObject returnInterfacesArray = NULL;
    
    char* InterfaceName = "";
    char* INamehw = "";
    getifaddrs(&ifAddrStruct);
    
    const struct sockaddr_dl* dlAddr;
    const unsigned char* base;
    int hwindex;
    char* macAddress = (char*) malloc(18);
    
    FRENewObject((const uint8_t*) "Array", 0, NULL, &returnInterfacesArray, nil);
    FRENewObject((const uint8_t*) "Array", 0, NULL, &InterfacePropArray, nil);
    
    int i = 0, j = 0;
    
    // Process each interface address returned from getifaddrs().
    for (ifa = ifAddrStruct; ifa != NULL; ifa = ifa->ifa_next) {
        
        if (ifa->ifa_addr->sa_family == AF_LINK) {
            
            //  Find the hardware address
            dlAddr = (const struct sockaddr_dl*) ifa->ifa_addr;
            base = (const unsigned char*) &dlAddr->sdl_data[dlAddr->sdl_nlen];
            strcpy(macAddress, "");
            
            for (hwindex = 0; hwindex < dlAddr->sdl_alen; hwindex++) {
                
                if (hwindex != 0)
                    strcat(macAddress, ":");
                
                char partialAddr[3];
                sprintf(partialAddr, "%02X", base[hwindex]);
                strcat(macAddress, partialAddr);
            }
            
            INamehw = ifa->ifa_name;
        }
        
        // When iterating through the list of interface address structures provided by getifaddrs(), 
        // each interface name gets repeated at least twice with a different family type. 
        
        // Determine if the interface name is a repeat of the the previous interface name.
        int cmp = strcmp(InterfaceName, (const char*) (ifa->ifa_name));
        
        if (cmp != 0) {
            
            // This is the first occurence of the name.
            InterfaceName = ifa->ifa_name;
            
            // Determine if this is a valid Link Local Interface. If it is, InterfaceName and INamehw
            // have been set to the same value.
            if (strcmp(InterfaceName, INamehw) == 0) {
                
                // Add this interface hardware address to the actionscript array element
                FRENewObjectFromUTF8(32, (const uint8_t*) macAddress, &NetworkInterfaceArray[4]);
            }
            
            if (flag) {
                
                // flag is initially false, and set to true after the first iteration through for-loop.
                // Therefore, this code is executed one time for each different Interface name.
                
                // This code puts a new NetworkInterface object in the array of returned NetworkInterface
                // objects, and does reinitialization to prepare for the next name in the for-loop.
                
                // Assign InterfacePropArray to the NetworkInterfaceArray                                              
                NetworkInterfaceArray[5] = InterfacePropArray;
                j = 0;
                
                // Create a new object of class NetworkInterface
                FRENewObject((const uint8_t*) "com.freshplanet.ane.AirNetworkInfo.NativeNetworkInterface",
                        6,
                        NetworkInterfaceArray,
                        &tempNetworkInterface,
                        nil);
                
                // Put the new FREObject into the returnInterfacesArray
                FRESetArrayElementAt(returnInterfacesArray, i++, tempNetworkInterface);
                
                
                // Reinstantiate the InterfaceProperty Array 
                FRENewObject((const uint8_t*) "Array", 0, NULL, &InterfacePropArray, nil);
                
                // Clearing the NetworkInterfaceArray
                
                for (int index = 0; index <= 5; index++)
                    NetworkInterfaceArray[index] = nil;
            }
            
            flag = TRUE;
            
            // Add the interface name to the NetworkInterfaceArray
            FRENewObjectFromUTF8(strlen(ifa->ifa_name), (const uint8_t*) ifa->ifa_name, &NetworkInterfaceArray[0]);
            
            // Add the display Name to the NetworkInterfaceArray. For this implementation, the display name
            // is the same as the interface name.
            FRENewObjectFromUTF8(strlen(ifa->ifa_name), (const uint8_t*) ifa->ifa_name, &NetworkInterfaceArray[1]);
            
            // Create a dummy socket to fetch  mtu using ioctl calls
            int s = socket(AF_INET, SOCK_DGRAM, 0);
            
            if (s != -1) {
                
                struct ifreq ifr;
                memset(&ifr, 0, sizeof(ifr));
                strcpy(ifr.ifr_name, ifa->ifa_name);
                
                // Ioctl Call to find MTU
                if (ioctl(s, SIOCGIFMTU, (caddr_t) &ifr) >= 0)
                    FRENewObjectFromInt32(ifr.ifr_mtu, &NetworkInterfaceArray[2]);
                
                close(s);
            }
        }  // end if interface name is not a repeat
        
        // Each interface can have more than one element in its InterfacePropArray array.
        // This relationship corresponds to how on the ActionScript side, a NetworkInterface object
        // contains a vector of InterfaceAddress objects.
        
        
        if (ifa->ifa_addr->sa_family == AF_INET || ifa->ifa_addr->sa_family == AF_INET6)
            j++;
        else // Reinstantiate the InterfaceProperty Array
            FRENewObject((const uint8_t*) "Array", 0, NULL, &InterfacePropArray, NULL);
    }
    
    //++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++all the interfaces has been iterated ++++++++++++++
    
    // Assign InterfacePropArray to the NetworkInterfaceArray
    NetworkInterfaceArray[5] = InterfacePropArray;
    
    //Create a new object of class NetworkInterface
    FRENewObject((const uint8_t*) "com.freshplanet.ane.AirNetworkInfo.NativeNetworkInterface",
            6,
            NetworkInterfaceArray,
            &tempNetworkInterface,
            nil);
    
    // Put the new FREObject into the returnInterfacesArray
    FRESetArrayElementAt(returnInterfacesArray, i++, tempNetworkInterface);
    
    // Reinstantiate the InterfaceProperty Array
    FRENewObject((const uint8_t*) "Array", 0, NULL, &InterfacePropArray, NULL);
    
    //+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    if (ifAddrStruct != NULL)
        freeifaddrs(ifAddrStruct);
    
    // Return returnInterfacesArray to ActionScript Code
    return returnInterfacesArray;
}

DEFINE_ANE_FUNCTION(getConnectivityStatus) {
    
    CFTypeRef controller;
    FREGetContextNativeData(context, (void**) &controller);
    
    NetworkInfoiOSLibrary* networkLib = (__bridge NetworkInfoiOSLibrary*) controller;
    
    if (!controller)
        return AirNetworkInfo_FPANE_CreateError(@"context's NetworkInfoiOSLibrary is null", 0);
    
    int netStatus = [networkLib getConnectivityStatus];
    FREObject freObj = AirNetworkInfo_FPANE_IntToFREObject(netStatus);
    
    return freObj;
}

DEFINE_ANE_FUNCTION(getCarrierName) {
    
    
    CTTelephonyNetworkInfo *info = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = [info subscriberCellularProvider];
    
    NSString *carrierName = [carrier carrierName];
    
    return AirNetworkInfo_FPANE_NSStringToFREObject(carrierName);
}

void AirNetworkInfoContextInitializer(void* extData, const uint8_t* ctxType, FREContext ctx, uint32_t* numFunctionsToSet, const FRENamedFunction** functionsToSet) {
    
    NetworkInfoiOSLibrary* controller = [[NetworkInfoiOSLibrary alloc] initWithContext:ctx];
    FRESetContextNativeData(ctx, (void*) CFBridgingRetain(controller));
    
    [controller startNetworkChangeNotifier];
    
    static FRENamedFunction functions[] = {
            MAP_FUNCTION(getInterfaces, NULL),
            MAP_FUNCTION(getConnectivityStatus, NULL),
            MAP_FUNCTION(getCarrierName, NULL)
    };
    
    *numFunctionsToSet = sizeof(functions) / sizeof(FRENamedFunction);
    *functionsToSet = functions;
}

void AirNetworkInfoContextFinalizer(FREContext ctx) {
    
    CFTypeRef controller;
    FREGetContextNativeData(ctx, (void**) &controller);
    
    [(__bridge NetworkInfoiOSLibrary*) ctx stopNetworkChangeNotifier];
    
    CFBridgingRelease(controller);
}

void AirNetworkInfoInitializer(void** extDataToSet, FREContextInitializer* ctxInitializerToSet, FREContextFinalizer* ctxFinalizerToSet) {
    
    *extDataToSet = NULL;
    *ctxInitializerToSet = &AirNetworkInfoContextInitializer;
    *ctxFinalizerToSet = &AirNetworkInfoContextFinalizer;
}

void AirNetworkInfoFinalizer(void* extData) {
    
}




