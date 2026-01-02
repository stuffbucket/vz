//
//  virtualization_view.h
//
//  Core application infrastructure for VM graphics.
//  This file contains only the minimal components needed by all paths.
//
//  Created by codehex.
//

#pragma once

#import "virtualization_helper.h"
#import <Availability.h>
#import <Cocoa/Cocoa.h>
#import <Virtualization/Virtualization.h>

// VZApplication provides a custom event loop for VM graphics applications.
// It allows programmatic termination via the shouldKeepRunning flag.
@interface VZApplication : NSApplication {
    bool shouldKeepRunning;
}
@end