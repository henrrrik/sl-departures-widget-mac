SL Departures

1. Drag "SL Departures" onto the Applications folder.

2. The app is signed but not notarized by Apple, so macOS will refuse to
   open it until you clear the quarantine flag. In Terminal, run:

       xattr -dr com.apple.quarantine "/Applications/SL Departures.app"

3. Open SL Departures, click the menu bar item, and pick your stop.

To add the desktop widget: right-click the desktop -> Edit Widgets -> search
for "SL Departures".

https://github.com/henrrrik/sl-departures-widget-mac
