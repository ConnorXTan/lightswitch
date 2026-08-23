/* mediakey_macos.m — the only file that can press a media key.
 *
 * Media transport is delivered as an NX_SYSDEFINED event (subtype 8), and
 * the only sanctioned way to construct one is +[NSEvent otherEventWithType:].
 * That AppKit dependency stops here: action.c calls ls_media_key_post and
 * knows nothing else. The event encoding mirrors what the physical F7-F9
 * keys produce, which is why players respond to it.
 */
#import <AppKit/AppKit.h>

#include "mediakey.h"

#include <stdio.h>

static int post_one(int keytype, int down)
{
    /* data1 layout for subtype 8: key type in the high word, key state
     * (0x0A pressed, 0x0B released) in the second byte. */
    NSInteger data1 = ((NSInteger)keytype << 16) | ((down ? 0x0A : 0x0B) << 8);
    NSEvent *ev = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                     location:NSZeroPoint
                                modifierFlags:(down ? 0xA00 : 0xB00)
                                    timestamp:0
                                 windowNumber:0
                                      context:nil
                                      subtype:8
                                        data1:data1
                                        data2:-1];
    if (!ev || !ev.CGEvent)
        return -1;
    CGEventPost(kCGHIDEventTap, ev.CGEvent);
    return 0;
}

int ls_media_key_post(int nx_keytype, char *err, size_t errlen)
{
    @autoreleasepool {
        if (post_one(nx_keytype, 1) != 0 || post_one(nx_keytype, 0) != 0) {
            snprintf(err, errlen, "could not create media key event");
            return -1;
        }
    }
    return 0;
}
