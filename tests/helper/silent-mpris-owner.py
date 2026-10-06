#!/usr/bin/env python3
"""A session-bus peer that takes one MPRIS name from two connections in turn
and never answers a call sent to either. It prints how many Introspect and
GetAll calls reached it, then keeps both connections open until its standard
input closes, so none of those calls fails early."""
import sys
import threading
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

name, flips = sys.argv[1], int(sys.argv[2])
counts = {"Introspect": 0, "GetAll": 0}
lock = threading.Lock()


def swallow(connection, message, incoming, user_data):
    # Runs on GDBus's worker thread; returning None drops the message unanswered.
    if incoming and message.get_message_type() == Gio.DBusMessageType.METHOD_CALL:
        with lock:
            if message.get_member() in counts:
                counts[message.get_member()] += 1
        return None
    return message


address = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
flags = Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
connections = []
for _ in range(2):
    connection = Gio.DBusConnection.new_for_address_sync(address, flags, None, None)
    connection.add_filter(swallow, None)
    connections.append(connection)
# ALLOW_REPLACEMENT | REPLACE_EXISTING: every request takes the name over.
for i in range(flips):
    connections[i % 2].call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                 "RequestName", GLib.Variant("(su)", (name, 3)), GLib.VariantType("(u)"),
                                 Gio.DBusCallFlags.NONE, -1, None)
    time.sleep(0.005)
time.sleep(0.5)
with lock:
    print(counts["Introspect"], counts["GetAll"], flush=True)
sys.stdin.read()
