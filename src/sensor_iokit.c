/* sensor_iokit.c — the live ambient light sensor on Apple laptops.
 *
 * macOS exposes no public API for the ALS, so we go through IOKit's private
 * HID event system, resolved at runtime with dlsym. That choice is contained
 * entirely in this file: nothing else in the project knows these symbols
 * exist, and on any other platform this translation unit is simply not built.
 *
 * The sensor is a Vishay VD6286 sitting behind the display glass next to the
 * camera. It answers HID event type 12 (ambient light); field 1 of that event
 * is illuminance in lux.
 */
#include "sensor.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

#include <CoreFoundation/CoreFoundation.h>

#define LS_ALS_EVENT_TYPE 12
#define LS_ALS_FIELD_LUX  ((LS_ALS_EVENT_TYPE << 16) | 1)

typedef CFTypeRef  (*fn_client_create)(CFAllocatorRef);
typedef CFArrayRef (*fn_copy_services)(CFTypeRef);
typedef CFTypeRef  (*fn_copy_event)(CFTypeRef, int64_t, CFTypeRef, int64_t);
typedef double     (*fn_event_float)(CFTypeRef, int64_t);

typedef struct {
    void            *iokit;
    fn_copy_event    copy_event;
    fn_event_float   event_float;
    CFTypeRef        client;
    CFArrayRef       services;
    CFTypeRef        als;      /* borrowed from services */
    double           poll_ms;
    double           t0;
    double           next_due;
} iokit_impl;

static double read_lux(iokit_impl *k)
{
    CFTypeRef ev = k->copy_event(k->als, LS_ALS_EVENT_TYPE, 0, 0);
    if (!ev)
        return -1.0;
    double v = k->event_float(ev, LS_ALS_FIELD_LUX);
    CFRelease(ev);
    return v;
}

static int iokit_read(ls_sensor *s, double *t_ms, double *lux)
{
    iokit_impl *k = s->impl;

    double now = ls_now_ms();
    if (k->next_due == 0.0)
        k->next_due = now;
    ls_sleep_ms(k->next_due - now);

    /* Advance on a fixed grid so a slow read does not make the cadence drift;
     * if we have fallen behind by more than a period, resynchronise. */
    k->next_due += k->poll_ms;
    now = ls_now_ms();
    if (k->next_due < now)
        k->next_due = now;

    *t_ms = now - k->t0;
    *lux  = read_lux(k);
    return 1;
}

static void iokit_destroy(ls_sensor *s)
{
    iokit_impl *k = s->impl;
    if (k->services)
        CFRelease(k->services);
    if (k->client)
        CFRelease(k->client);
    if (k->iokit)
        dlclose(k->iokit);
    free(k);
    free(s);
}

ls_sensor *ls_sensor_open_iokit(double poll_ms, char *err, size_t errlen)
{
    iokit_impl *k = calloc(1, sizeof(*k));
    if (!k) {
        snprintf(err, errlen, "out of memory");
        return NULL;
    }
    k->poll_ms = poll_ms;

    k->iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",
                      RTLD_NOW);
    if (!k->iokit) {
        snprintf(err, errlen, "cannot load IOKit: %s", dlerror());
        goto fail;
    }

    fn_client_create create   = (fn_client_create)dlsym(k->iokit, "IOHIDEventSystemClientCreate");
    fn_copy_services services = (fn_copy_services)dlsym(k->iokit, "IOHIDEventSystemClientCopyServices");
    k->copy_event             = (fn_copy_event)dlsym(k->iokit, "IOHIDServiceClientCopyEvent");
    k->event_float            = (fn_event_float)dlsym(k->iokit, "IOHIDEventGetFloatValue");

    if (!create || !services || !k->copy_event || !k->event_float) {
        snprintf(err, errlen,
                 "IOKit is missing the private HID event symbols this build "
                 "relies on (macOS may have changed them)");
        goto fail;
    }

    k->client = create(kCFAllocatorDefault);
    if (!k->client) {
        snprintf(err, errlen, "IOHIDEventSystemClientCreate failed");
        goto fail;
    }
    k->services = services(k->client);
    if (!k->services) {
        snprintf(err, errlen, "no HID services available");
        goto fail;
    }

    /* Identify the ALS by asking every service for an ambient light event and
     * keeping the first that answers — more robust than matching on names,
     * which differ across models. */
    for (CFIndex i = 0; i < CFArrayGetCount(k->services); i++) {
        CFTypeRef svc = CFArrayGetValueAtIndex(k->services, i);
        CFTypeRef ev  = k->copy_event(svc, LS_ALS_EVENT_TYPE, 0, 0);
        if (ev) {
            CFRelease(ev);
            k->als = svc;
            break;
        }
    }
    if (!k->als) {
        snprintf(err, errlen, "no ambient light sensor found on this machine");
        goto fail;
    }

    ls_sensor *s = calloc(1, sizeof(*s));
    if (!s) {
        snprintf(err, errlen, "out of memory");
        goto fail;
    }
    k->t0      = ls_now_ms();
    s->kind    = "iokit";
    s->read    = iokit_read;
    s->destroy = iokit_destroy;
    s->impl    = k;
    return s;

fail:
    if (k->services) CFRelease(k->services);
    if (k->client)   CFRelease(k->client);
    if (k->iokit)    dlclose(k->iokit);
    free(k);
    return NULL;
}
