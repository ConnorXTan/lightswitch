/* overlay_macos.m — the glow around the notch.
 *
 * Everything AppKit lives in this file; see overlay.h for the contract. The
 * shape of the code follows the project's ui.c split: ls_glow_eval decides
 * what the overlay looks like and is unit-tested elsewhere, while this file
 * is deliberately dumb — it owns a borderless window, two shape layers, and
 * a 30 Hz timer that maps {mode, intensity, progress, pulse} onto them.
 *
 * Threading: the poll loop runs on a worker pthread and hands us POD
 * snapshots through ls_overlay_publish (a mutex-guarded mailbox). The
 * renderer extrapolates the snapshot's clock forward so the ~10 Hz sample
 * rate still animates smoothly at 30 fps.
 */
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include "overlay.h"
#include "sensor.h"   /* ls_now_ms */

#include <pthread.h>
#include <stdio.h>

#define PAD_X       24.0   /* how far the glow bleeds around the notch */
#define PAD_BELOW   24.0
#define BLEED_TOP   12.0   /* path extends past the screen edge so only
                              the sides and bottom of the ring render */
#define FPS         60.0

/* Envelope smoothing between the ~10 Hz samples: fast attack so the ring
 * feels attached to the hand, slower release so it lets go gracefully. */
#define TAU_UP_MS       40.0
#define TAU_DOWN_MS    200.0
#define TAU_ARC_MS      60.0

/* ---- mailbox ------------------------------------------------------------ */

static struct {
    pthread_mutex_t mu;
    ls_glow_input   in;
    double          wall_ms;
    int             have;
    int             done;
} g_mail = { .mu = PTHREAD_MUTEX_INITIALIZER };

void ls_overlay_publish(const ls_glow_input *in, double wall_ms)
{
    pthread_mutex_lock(&g_mail.mu);
    g_mail.in      = *in;
    g_mail.wall_ms = wall_ms;
    g_mail.have    = 1;
    pthread_mutex_unlock(&g_mail.mu);
}

typedef struct {
    void *(*fn)(void *);
    void *arg;
} poll_thunk;

static void *poll_trampoline(void *p)
{
    poll_thunk *t = p;
    t->fn(t->arg);
    pthread_mutex_lock(&g_mail.mu);
    g_mail.done = 1;
    pthread_mutex_unlock(&g_mail.mu);
    return NULL;
}

/* ---- drawing ------------------------------------------------------------ */

static NSWindow     *g_win;
static CAShapeLayer *g_ring;
static CAShapeLayer *g_arc;

static NSColor *mode_color(ls_glow_mode m)
{
    switch (m) {
    case LS_GLOW_CALIBRATING:
        return [NSColor colorWithSRGBRed:0.60 green:0.60 blue:0.62 alpha:1.0];
    case LS_GLOW_IDLE:
        return [NSColor colorWithSRGBRed:0.92 green:0.92 blue:0.95 alpha:1.0];
    case LS_GLOW_COVERING:
        return [NSColor colorWithSRGBRed:1.00 green:0.72 blue:0.30 alpha:1.0];
    case LS_GLOW_FIRED:
        return [NSColor colorWithSRGBRed:0.35 green:0.95 blue:0.75 alpha:1.0];
    case LS_GLOW_FAULT:
        return [NSColor colorWithSRGBRed:1.00 green:0.30 blue:0.30 alpha:1.0];
    }
    return [NSColor whiteColor];
}

/* The screen with a notch if there is one, else the main screen (the glow
 * degrades to a pill at the top edge). Returns the notch rect in screen
 * coordinates through *notch. */
static NSScreen *pick_screen(NSRect *notch)
{
    NSScreen *screen = [NSScreen mainScreen];
    double h = 0.0, w = 200.0;

    if (@available(macOS 12.0, *)) {
        for (NSScreen *s in [NSScreen screens]) {
            if (s.safeAreaInsets.top > 0.0) {
                screen = s;
                break;
            }
        }
        h = screen.safeAreaInsets.top;
        if (h > 0.0) {
            NSRect l = screen.auxiliaryTopLeftArea;
            NSRect r = screen.auxiliaryTopRightArea;
            if (l.size.width > 0.0 && r.size.width > 0.0)
                w = screen.frame.size.width - l.size.width - r.size.width;
        }
    }
    if (h <= 0.0)
        h = 30.0;   /* no notch: a centred pill of about the same size */

    NSRect f = screen.frame;
    notch->origin.x   = f.origin.x + (f.size.width - w) / 2.0;
    notch->origin.y   = f.origin.y + f.size.height - h;
    notch->size.width  = w;
    notch->size.height = h;
    return screen;
}

static int build_window(void)
{
    NSRect notch;
    (void)pick_screen(&notch);

    NSRect frame = NSMakeRect(notch.origin.x - PAD_X,
                              notch.origin.y - PAD_BELOW,
                              notch.size.width + 2.0 * PAD_X,
                              notch.size.height + PAD_BELOW);

    g_win = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSWindowStyleMaskBorderless
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    if (!g_win)
        return -1;
    g_win.opaque             = NO;
    g_win.backgroundColor    = [NSColor clearColor];
    g_win.hasShadow          = NO;
    g_win.ignoresMouseEvents = YES;
    g_win.level              = NSStatusWindowLevel + 1;
    g_win.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorStationary |
                               NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSView *view = g_win.contentView;
    view.wantsLayer = YES;

    /* One rounded rect hugging the notch, its top edge pushed past the
     * screen edge so the ring reads as sides and a bottom. */
    NSRect box = NSMakeRect(PAD_X, PAD_BELOW,
                            notch.size.width,
                            notch.size.height + BLEED_TOP);
    CGPathRef path =
        CGPathCreateWithRoundedRect(NSRectToCGRect(box), 10.0, 10.0, NULL);

    g_ring = [CAShapeLayer layer];
    g_ring.path        = path;
    g_ring.fillColor   = NULL;
    g_ring.lineWidth   = 3.0;
    g_ring.frame       = view.bounds;

    g_arc = [CAShapeLayer layer];
    g_arc.path         = path;
    g_arc.fillColor    = NULL;
    g_arc.lineWidth    = 5.0;
    g_arc.lineCap      = kCALineCapRound;
    g_arc.strokeEnd    = 0.0;
    g_arc.frame        = view.bounds;

    CGPathRelease(path);

    [view.layer addSublayer:g_ring];
    [view.layer addSublayer:g_arc];
    [g_win orderFrontRegardless];
    return 0;
}

static double g_intensity;   /* smoothed display values */
static double g_progress;
static double g_last_ms;

static void apply_frame(const ls_glow_frame *f)
{
    double now = ls_now_ms();
    double dt  = g_last_ms > 0.0 ? now - g_last_ms : 0.0;
    g_last_ms = now;

    g_intensity = ls_glow_approach(g_intensity, f->intensity, dt,
                                   f->intensity > g_intensity ? TAU_UP_MS
                                                              : TAU_DOWN_MS);
    g_progress  = ls_glow_approach(g_progress, f->progress, dt, TAU_ARC_MS);

    NSColor *c = mode_color(f->mode);
    double scale = 1.0 + 0.10 * f->pulse;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    g_ring.strokeColor   = c.CGColor;
    g_ring.opacity       = (float)(0.25 + 0.75 * g_intensity);
    g_ring.shadowColor   = c.CGColor;
    g_ring.shadowOpacity = (float)(0.9 * g_intensity + 0.1 * f->pulse);
    g_ring.shadowRadius  = 4.0 + 14.0 * g_intensity + 8.0 * f->pulse;
    g_ring.shadowOffset  = CGSizeZero;
    g_ring.transform     = CATransform3DMakeScale(scale, scale, 1.0);

    g_arc.strokeColor = c.CGColor;
    g_arc.strokeEnd   = (CGFloat)g_progress;
    g_arc.opacity     = g_progress > 0.005 ? 0.9f : 0.0f;
    g_arc.transform   = g_ring.transform;

    [CATransaction commit];
}

/* -stop: only takes effect once the app processes an event, and a timer
 * firing is not an event; post a synthetic one so [NSApp run] returns. */
static void wake_app(void)
{
    NSEvent *e = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                    location:NSZeroPoint
                               modifierFlags:0
                                   timestamp:0
                                windowNumber:0
                                     context:nil
                                     subtype:0
                                       data1:0
                                       data2:0];
    [NSApp postEvent:e atStart:YES];
}

/* ---- entry point -------------------------------------------------------- */

int ls_overlay_run(void *(*poll_main)(void *), void *poll_arg,
                   volatile sig_atomic_t *stop, char *err, size_t errlen)
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        if (build_window() != 0) {
            snprintf(err, errlen, "could not create the overlay window");
            return -1;
        }

        poll_thunk thunk = { poll_main, poll_arg };
        pthread_t  tid;
        if (pthread_create(&tid, NULL, poll_trampoline, &thunk) != 0) {
            snprintf(err, errlen, "could not start the sensor thread");
            [g_win orderOut:nil];
            return -1;
        }

        NSTimer *timer = [NSTimer
            timerWithTimeInterval:1.0 / FPS
                          repeats:YES
                            block:^(NSTimer *t) {
                              (void)t;
                              ls_glow_input in;
                              double wall;
                              int have, done;

                              pthread_mutex_lock(&g_mail.mu);
                              in   = g_mail.in;
                              wall = g_mail.wall_ms;
                              have = g_mail.have;
                              done = g_mail.done;
                              pthread_mutex_unlock(&g_mail.mu);

                              if (*stop || done) {
                                  [NSApp stop:nil];
                                  wake_app();
                                  return;
                              }
                              if (!have)
                                  return;

                              /* Move the snapshot's clock forward so 10 Hz
                               * samples animate smoothly at 30 fps. */
                              in.t_now += ls_now_ms() - wall;

                              ls_glow_frame f;
                              ls_glow_eval(&in, &f);
                              apply_frame(&f);
                            }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];

        [app run];

        [timer invalidate];
        pthread_join(tid, NULL);
        [g_win orderOut:nil];
    }
    return 0;
}
