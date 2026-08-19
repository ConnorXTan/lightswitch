# lightswitch

Uses the MacBook ambient light sensor (Vishay VD6286) as a gesture input.
Cup your hand over the top-center of the screen -> the shadow fires an action.

    clang -o lightswitch lightswitch.c -framework CoreFoundation -framework IOKit -framework ApplicationServices
    ./lightswitch          # dry run, prints only
    ./lightswitch --kill   # sends Cmd-W to the front app

Measured on this Mac: sensor refresh ~4.7 Hz (211 ms), idle noise +/-6 lux on a
~4830 lux baseline (0.12%). Occlusion is a ~100% signal drop, so detection is
reliable; detection latency ~400 ms (2 consecutive reads).

Notes:
- Turn OFF System Settings > Displays > "Automatically adjust brightness",
  otherwise macOS dims the screen when you shade the sensor.
- --kill needs Accessibility permission (System Settings > Privacy & Security).
- Needs a reasonably lit room; refuses to run below 25 lux baseline.

`touchprobe` is the Touch ID experiment: it shows the sensor is asleep
(mesa-state 1) unless an auth request is pending, which is why Touch ID
cannot be used as a hover/gesture input.
