// touchprobe — measures exactly what a normal macOS app can learn from the Touch ID sensor.
// Unprivileged: no sudo, no entitlements, no SIP changes.
//   build: clang -o touchprobe touchprobe.c -framework CoreFoundation -framework IOKit
//   run:   ./touchprobe [seconds]
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

typedef CFMutableDictionaryRef (*fn_chan)(CFStringRef,CFStringRef,uint64_t,uint64_t,uint64_t);
typedef CFTypeRef (*fn_sub)(void*,CFMutableDictionaryRef,CFMutableDictionaryRef*,uint64_t,CFTypeRef);
typedef CFDictionaryRef (*fn_samp)(CFTypeRef,CFMutableDictionaryRef,CFTypeRef);
typedef int64_t (*fn_int)(CFDictionaryRef,int32_t);
static fn_int gInt;

static long ioprop(const char*cls,const char*key){
  io_service_t s=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching(cls));
  if(!s) return -1;
  CFTypeRef r=IORegistryEntryCreateCFProperty(s,CFStringCreateWithCString(NULL,key,kCFStringEncodingUTF8),kCFAllocatorDefault,0);
  IOObjectRelease(s);
  if(!r) return -1;
  long v=-1; if(CFGetTypeID(r)==CFNumberGetTypeID()) CFNumberGetValue(r,kCFNumberLongType,&v);
  CFRelease(r); return v;
}
static int nameOf(CFDictionaryRef ch,char*o,size_t n){
  o[0]=0; CFArrayRef l=(CFArrayRef)CFDictionaryGetValue(ch,CFSTR("LegendChannel"));
  if(!l||CFGetTypeID(l)!=CFArrayGetTypeID()||CFArrayGetCount(l)<3) return 0;
  CFTypeRef s=CFArrayGetValueAtIndex(l,2);
  if(!s||CFGetTypeID(s)!=CFStringGetTypeID()) return 0;
  return CFStringGetCString((CFStringRef)s,o,n,kCFStringEncodingUTF8);
}
int main(int argc,char**argv){
  int secs=argc>1?atoi(argv[1]):25;
  void*h=dlopen("/usr/lib/libIOReport.dylib",RTLD_NOW);
  fn_chan chans=dlsym(h,"IOReportCopyChannelsInGroup");
  fn_sub  subf =dlsym(h,"IOReportCreateSubscription");
  fn_samp sampf=dlsym(h,"IOReportCreateSamples");
  gInt         =dlsym(h,"IOReportSimpleGetIntegerValue");
  CFMutableDictionaryRef c=chans(CFSTR("Mesa"),NULL,0,0,0);
  if(!c){printf("No Touch ID sensor found.\n");return 1;}
  CFMutableDictionaryRef sd=NULL; CFTypeRef sub=subf(NULL,c,&sd,0,NULL);
  CFMutableDictionaryRef use=sd?sd:c;

  long pImg=-1,pIntr=-1,pMesa=-1;
  printf("Touch ID probe — %ds. Rest a finger on the sensor, and try swiping across it.\n",secs);
  printf("Nothing else should be asking for authentication.\n\n");
  for(int t=0;t<secs*10;t++){
    long img=pImg,intr=pIntr;
    CFDictionaryRef smp=sampf(sub,use,NULL);
    if(smp){
      CFArrayRef a=(CFArrayRef)CFDictionaryGetValue(smp,CFSTR("IOReportChannels"));
      if(a&&CFGetTypeID(a)==CFArrayGetTypeID())
        for(CFIndex i=0;i<CFArrayGetCount(a);i++){
          CFDictionaryRef ch=CFArrayGetValueAtIndex(a,i);
          CFStringRef g=CFDictionaryGetValue(ch,CFSTR("IOReportSubGroupName"));
          if(!g||CFStringCompare(g,CFSTR("Mesa Events"),0)!=kCFCompareEqualTo) continue;
          char nm[128]; if(!nameOf(ch,nm,sizeof nm)) continue;
          long v=gInt(ch,0);
          if(!strcmp(nm,"Captured Images"))  img=v;
          if(!strcmp(nm,"Total Interrupts")) intr=v;
        }
      CFRelease(smp);
    }
    long mesa=ioprop("AppleBiometricSensor","mesa-state");
    if(t==0){
      printf("baseline:  captured-images=%ld  interrupts=%ld  mesa-state=%ld\n\n-- watching --\n",img,intr,mesa);
      pImg=img;pIntr=intr;pMesa=mesa;
    } else if(img!=pImg||intr!=pIntr||mesa!=pMesa){
      printf("  CHANGE  images %ld->%ld   interrupts %ld->%ld   mesa-state %ld->%ld\n",
             pImg,img,pIntr,intr,pMesa,mesa);
      pImg=img;pIntr=intr;pMesa=mesa;
    }
    fflush(stdout);
    usleep(100000);
  }
  printf("\nIf nothing printed under 'watching', the sensor is deaf while idle:\n"
         "it only reports when something has requested authentication.\n");
  return 0;
}
