// lightswitch — a hand-over-the-screen kill switch for macOS.
// Uses the ambient light sensor as a gesture input: cup your hand over the
// top-center of the display (above the notch) and the shadow fires an action.
//
// build: clang -o lightswitch lightswitch.c -framework CoreFoundation -framework IOKit
// run:   ./lightswitch            (dry run — just prints)
//        ./lightswitch --kill     (actually sends Cmd-W to the front app)
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/time.h>
#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>

typedef CFTypeRef  (*ESCreate)(CFAllocatorRef);
typedef CFTypeRef  (*ESCopyEvent)(CFTypeRef,int64_t,CFTypeRef,int64_t);
typedef double     (*EvGetFloat)(CFTypeRef,int64_t);
typedef CFArrayRef (*ESCopyServices)(CFTypeRef);
#define ALS_TYPE 12
#define ALS_FIELD ((ALS_TYPE<<16)|1)

static ESCopyEvent ce; static EvGetFloat gf; static CFTypeRef alsSvc;
static double now(void){struct timeval t;gettimeofday(&t,0);return t.tv_sec+t.tv_usec/1e6;}
static double lux(void){
  CFTypeRef ev=ce(alsSvc,ALS_TYPE,0,0); if(!ev) return -1;
  double v=gf(ev,ALS_FIELD); CFRelease(ev); return v;
}
static void closeTab(void){
  CGEventRef d=CGEventCreateKeyboardEvent(NULL,(CGKeyCode)13,true);   // 13 = 'w'
  CGEventRef u=CGEventCreateKeyboardEvent(NULL,(CGKeyCode)13,false);
  CGEventSetFlags(d,kCGEventFlagMaskCommand); CGEventSetFlags(u,kCGEventFlagMaskCommand);
  CGEventPost(kCGHIDEventTap,d); CGEventPost(kCGHIDEventTap,u);
  CFRelease(d); CFRelease(u);
}
int main(int argc,char**argv){
  int doKill = argc>1 && !strcmp(argv[1],"--kill");
  void*h=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_NOW);
  ESCreate cr=dlsym(h,"IOHIDEventSystemClientCreate");
  ce=dlsym(h,"IOHIDServiceClientCopyEvent"); gf=dlsym(h,"IOHIDEventGetFloatValue");
  ESCopyServices cs=dlsym(h,"IOHIDEventSystemClientCopyServices");
  CFTypeRef c=cr(kCFAllocatorDefault); CFArrayRef svcs=cs(c);
  for(CFIndex i=0;i<CFArrayGetCount(svcs);i++){
    CFTypeRef s=CFArrayGetValueAtIndex(svcs,i);
    CFTypeRef ev=ce(s,ALS_TYPE,0,0); if(ev){alsSvc=s;CFRelease(ev);break;}
  }
  if(!alsSvc){printf("No ambient light sensor found.\n");return 1;}

  printf("calibrating ambient baseline (2s, don't shade the screen)...\n");
  double base=0; int n=0; double t0=now();
  while(now()-t0<2.0){ double v=lux(); if(v>=0){base+=v;n++;} usleep(50000); }
  base/=n;
  if(base<25){printf("Ambient light too low (%.0f lux) — need a lit room.\n",base);return 1;}
  double trig=base*0.45, rearm=base*0.75;
  printf("baseline %.0f lux | trigger below %.0f | re-arm above %.0f\n",base,trig,rearm);
  printf("%s\n\nCup your hand over the top-center of the screen.\n\n",
         doKill?"MODE: --kill (will send Cmd-W)":"MODE: dry run (prints only)");

  int armed=1, low=0; double lastFire=0;
  for(;;){
    double v=lux();
    if(v>=0){
      if(armed && v<trig){
        if(++low>=2 && now()-lastFire>1.0){          // 2 consecutive reads ~ 400ms
          printf("  >>> TRIGGERED  (%.0f lux, %.0f%% of baseline)%s\n",
                 v, v/base*100, doKill?"  -> Cmd-W sent":"");
          if(doKill) closeTab();
          lastFire=now(); armed=0; low=0;
        }
      } else if(!armed && v>rearm){ armed=1; printf("  (re-armed)\n"); }
      else if(v>=trig) low=0;
      // slow ambient drift tracking while armed and uncovered
      if(armed && v>rearm){ base=base*0.995+v*0.005; trig=base*0.45; rearm=base*0.75; }
    }
    fflush(stdout);
    usleep(100000);
  }
}
