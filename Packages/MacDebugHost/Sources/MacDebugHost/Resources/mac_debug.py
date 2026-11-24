"""Xcode custom launch command for a remote Mac run scheme."""
import base64
import json
import os
from pathlib import Path
import time
import uuid

import lldb


def connect(debugger, command, result, internal_dict):
    try:
        binding, location = command.split()
        binding = str(uuid.UUID(binding)).upper()
        runtime = Path(os.fsdecode(base64.b64decode(location, validate=True)))
        handoff = runtime / (binding + ".json")
        claimed = handoff.with_name(str(uuid.uuid4()) + ".claimed")
        handoff.rename(claimed)
        try:
            if time.time() - claimed.stat().st_mtime > 90:
                raise RuntimeError("The prepared launch expired. Run the scheme again.")
            with claimed.open() as stream:
                reply = json.load(stream)
        finally:
            claimed.unlink()
        if "failure" in reply:
            raise RuntimeError(reply["failure"]["_0"])
        run = reply["ready"]["_0"]

        platform = lldb.SBPlatform("remote-macosx")
        platform.SetSDKRoot(run["sysroot"])
        debugger.SetSelectedPlatform(platform)
        error = lldb.SBError()
        target = debugger.CreateTarget(run["executable"], None, "remote-macosx", True, error)
        if error.Fail():
            raise RuntimeError(error.GetCString())
        debugger.SetSelectedTarget(target)
        mappings = [(run["guestProduct"], run["product"])]
        for path in ("/System/Library", "/usr/lib"):
            mappings.append((path, run["symbols"] + path))
        for source, destination in mappings:
            target.AppendImageSearchPath(source, destination, error)
            if error.Fail():
                raise RuntimeError(error.GetCString())
        process = target.ConnectRemote(lldb.SBListener(), "unix-connect://" + run["socket"], "gdb-remote", error)
        if error.Fail() or not process.IsValid():
            raise RuntimeError(error.GetCString() or "The guest debugger disconnected.")
        result.AppendMessage("Debugging " + run["guestProduct"])
    except (ValueError, KeyError, OSError, RuntimeError) as exc:
        result.SetError("Remote debugging: " + str(exc))


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand(f"command script add -o -f {__name__}.connect mac-debug-connect")
