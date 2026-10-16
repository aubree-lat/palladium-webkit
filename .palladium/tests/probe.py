#!/usr/bin/env python3
import json
import sys
from pathlib import Path
from urllib.parse import unquote

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import GLib, Gtk, WebKit2

window = Gtk.OffscreenWindow()
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

script = "Promise.resolve().then(async function(){" + Path(sys.argv[1]).read_text(encoding="utf-8") + "}).then(function(result){document.title='WEBKIT_RESULT:'+encodeURIComponent(JSON.stringify(result))}).catch(function(e){document.title='WEBKIT_RESULT:'+encodeURIComponent(JSON.stringify({ok:false,error:e.name+': '+e.message}))});"

exit_status = 3


def poll_title():
    global exit_status
    title = webview.get_title() or ""
    if not title.startswith("WEBKIT_RESULT:"):
        return True
    result = json.loads(unquote(title[len("WEBKIT_RESULT:"):]))
    result["webkitVersion"] = "%s.%s.%s" % (
        WebKit2.get_major_version(),
        WebKit2.get_minor_version(),
        WebKit2.get_micro_version(),
    )
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
    print(json.dumps({"ok": False, "reason": "probe timed out"}, sort_keys=True))
    exit_status = 2
    Gtk.main_quit()
    return False


webview.connect("load-changed", on_load)
webview.load_html("<html><body>palladium webkit probe</body></html>", "https://discord.com/")
GLib.timeout_add_seconds(30, timed_out)
Gtk.main()
sys.exit(exit_status)
