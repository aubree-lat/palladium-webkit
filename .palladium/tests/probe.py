#!/usr/bin/env python3
import json
import os
import sys
import subprocess
from pathlib import Path
from urllib.parse import unquote

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import GLib, Gtk, WebKit2

window = Gtk.Window()
window.set_default_size(320, 200)
webview = WebKit2.WebView()
settings = webview.get_settings()
settings.set_media_playback_requires_user_gesture(False)
settings.set_enable_media_stream(True)
settings.set_enable_webrtc(True)
settings.set_enable_mediasource(True)
settings.set_enable_media_capabilities(True)
webview.set_settings(settings)
window.add(webview)
window.show_all()

script = "Promise.resolve().then(async function(){" + Path(sys.argv[1]).read_text(encoding="utf-8") + "}).then(function(result){document.title='WEBKIT_RESULT:'+encodeURIComponent(JSON.stringify(result))}).catch(function(e){document.title='WEBKIT_RESULT:'+encodeURIComponent(JSON.stringify({ok:false,error:e.name+': '+e.message,stage:document.title}))});"

exit_status = 3
control_module = None
completed_controls = set()
webview.connect("permission-request", lambda view, request: (request.allow(), True)[1])


def poll_title():
    global exit_status, control_module
    title = webview.get_title() or ""
    if title.startswith("WEBKIT_CONTROL:"):
        operation = title.split(":", 1)[1]
        if operation in completed_controls:
            return True
        try:
            if operation == "add":
                control_module = subprocess.check_output(["pactl", "load-module", "module-null-sink", "sink_name=palladium-hotplug"], text=True).strip()
            elif operation == "default":
                subprocess.run(["pactl", "set-default-sink", "palladium-hotplug"], check=True)
            elif operation == "remove" and control_module:
                subprocess.run(["pactl", "unload-module", control_module], check=True)
                control_module = None
            else:
                raise ValueError("unsupported probe control")
            completed_controls.add(operation)
            view_script = "window.__PALLADIUM_DEVICE_CONTROL__=" + json.dumps(operation)
            webview.evaluate_javascript(view_script, -1, None, None, None, None, None)
        except Exception as error:
            print(json.dumps({"ok": False, "error": str(error)}))
            exit_status = 1
            Gtk.main_quit()
            return False
        return True
    if not title.startswith("WEBKIT_RESULT:"):
        return True
    result = json.loads(unquote(title[len("WEBKIT_RESULT:"):]))
    result["webkitVersion"] = "%s.%s.%s" % (
        WebKit2.get_major_version(),
        WebKit2.get_minor_version(),
        WebKit2.get_micro_version(),
    )
    processes = []
    for path in Path("/proc").glob("[0-9]*/status"):
        try:
            fields = dict(line.split(":", 1) for line in path.read_text().splitlines() if ":" in line)
            processes.append((int(path.parent.name), int(fields["PPid"]), fields["Name"].strip(), int(fields.get("RssAnon", "0").split()[0]) * 1024))
        except (OSError, KeyError, ValueError):
            continue
    family = {os.getpid()}
    while True:
        children = {pid for pid, parent, _, _ in processes if parent in family}
        if children.issubset(family):
            break
        family.update(children)
    memory = [anonymous for pid, _, name, anonymous in processes if pid in family and name.startswith("WebKitWebProc")]
    result["processMemory"] = {"webProcesses": len(memory), "webProcessAnonymousBytes": sum(memory) if memory else None}
    result["ok"] = result.get("ok", not bool(result.get("error")))
    print(json.dumps(result, sort_keys=True))
    exit_status = 0 if result["ok"] else 1
    Gtk.main_quit()
    return False


def on_load(view, event):
    if event == WebKit2.LoadEvent.FINISHED:
        view.evaluate_javascript(script, -1, None, None, None, None, None)
        GLib.timeout_add(200, poll_title)


def timed_out():
    global exit_status
    print(json.dumps({"ok": False, "reason": "probe timed out", "stage": webview.get_title()}, sort_keys=True))
    exit_status = 2
    Gtk.main_quit()
    return False


webview.connect("load-changed", on_load)
webview.load_html("<html><body>palladium webkit probe</body></html>", "https://discord.com/")
GLib.timeout_add_seconds(30, timed_out)
Gtk.main()
if control_module:
    subprocess.run(["pactl", "unload-module", control_module], check=False)
sys.exit(exit_status)
