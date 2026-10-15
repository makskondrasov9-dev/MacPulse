#!/usr/bin/env python3
"""Profile the packaged accessory app with a CPU-only menu; no persisted preferences change."""
import pathlib, subprocess, time, sys, re
app = pathlib.Path(sys.argv[1]).resolve()
duration = float(sys.argv[2]) if len(sys.argv) > 2 else 60
mode = sys.argv[3] if len(sys.argv) > 3 else "mono"
style = sys.argv[4] if len(sys.argv) > 4 else "full"
executable = app / 'Contents/MacOS/iMacMonitor'
flags = {'applicationMode':'accessory', 'desktopWidgetsEnabled':'NO', 'showCPUPercentage':'YES',
         'showRAMPercentage':'NO', 'showGPUPercentage':'NO', 'showCPUTemperature':'NO',
         'showNetworkSpeed':'NO', 'showMenuBarIP':'NO', 'showMenuBarVPN':'NO',
         'publicIPHistory':'NO', 'trackApplicationUsage':'NO', 'menuBarTextStyle':style, 'showCPUChart':'YES', 'showNetworkChart':'NO',
         'menuBarColorMode':mode, 'pollingInterval':'2'}
arguments = [str(executable)] + [v for k, value in flags.items() for v in ['-'+k,value]]
def reading(pid):
    raw = subprocess.check_output(['/bin/ps','-p',str(pid),'-o','time=','-o','rss='],text=True).strip().split()
    clock = raw[0].split(':')
    cpu = sum(float(v) * 60**i for i,v in enumerate(reversed(clock)))
    return cpu, int(raw[1]) / 1024
with open('.build/background-profile-app.log','ab') as log:
    process = subprocess.Popen(arguments,stdout=log,stderr=log)
    try:
        time.sleep(8)
        first, rss = reading(process.pid); start = time.monotonic()
        print(f'{app.name} [{mode}/{style}]: PID {process.pid}, warm RSS {rss:.1f} MiB; measuring {duration:.0f}s',flush=True)
        time.sleep(duration)
        last, rss_end = reading(process.pid); elapsed = time.monotonic()-start
        print(f'{app.name} [{mode}/{style}]: CPU {(last-first)/elapsed*100:.3f}% of one core; RSS {rss_end:.1f} MiB; delta {rss_end-rss:+.1f} MiB',flush=True)
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
