/* mediakey.h — press the keys that aren't keys.
 *
 * Media transport (play/pause, next track) is not a keyboard keycode; it is
 * an NX_SYSDEFINED event of subtype 8, and the only sanctioned way to build
 * one is through AppKit. That choice is contained entirely in
 * mediakey_macos.m: nothing else in the project knows AppKit exists. Off
 * macOS the symbol is never referenced, so no stub is needed.
 */
#ifndef LS_MEDIAKEY_H
#define LS_MEDIAKEY_H

#include <stddef.h>

/* Posts a press+release of the given NX_KEYTYPE_* code to the system event
 * stream. Returns 0 on success, -1 with a reason in err. */
int ls_media_key_post(int nx_keytype, char *err, size_t errlen);

#endif /* LS_MEDIAKEY_H */
