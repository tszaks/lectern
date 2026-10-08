# Makes the two Do Not Disturb shortcuts that Lectern runs while presenting.
# Run once: python3 mac/shortcuts/make.py  (it signs them with /usr/bin/shortcuts sign)
import plistlib, subprocess, os, uuid
here = os.path.dirname(os.path.abspath(__file__))
for name, on in [("Lectern Do Not Disturb On", True), ("Lectern Do Not Disturb Off", False)]:
    params = {"UUID": str(uuid.uuid4()).upper(), "Enabled": on,
              "FocusModes": {"Identifier": "com.apple.donotdisturb.mode.default", "DisplayString": "Do Not Disturb"}}
    if on:
        params["AssertionType"] = "Turned Off"  # stays on until Lectern turns it off
    wf = {
        "WFWorkflowActions": [{"WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set", "WFWorkflowActionParameters": params}],
        "WFWorkflowClientVersion": "2700.0.4", "WFWorkflowHasOutputFallback": False,
        "WFWorkflowIcon": {"WFWorkflowIconGlyphNumber": 59772, "WFWorkflowIconStartColor": 1440408063},
        "WFWorkflowImportQuestions": [], "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowMinimumClientVersion": 900, "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowName": name, "WFWorkflowOutputContentItemClasses": [], "WFWorkflowTypes": [],
    }
    raw = os.path.join(here, name + ".unsigned.shortcut")
    with open(raw, "wb") as f:
        plistlib.dump(wf, f, fmt=plistlib.FMT_BINARY)
    out = os.path.join(here, name + ".shortcut")
    subprocess.run(["/usr/bin/shortcuts", "sign", "--mode", "anyone", "--input", raw, "--output", out], check=True)
    os.remove(raw)
    print("made", out)
