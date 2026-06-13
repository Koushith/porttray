# PortTray

a tiny macOS menu bar app that shows which ports are open, what app is using them, and lets you kill that process right from the tray. no dock icon, no window, just a thing that sits up top.

i built this because i kept running `lsof -i :3000` then `kill -9` a hundred times a day. now it's two clicks.

## download

grab the latest `PortTray.app.zip` from [Releases](../../releases/latest), unzip it, and drop it in `/Applications`.

it's not signed with a paid apple cert, so the first launch gets blocked by gatekeeper. get past it once:

- right click the app, then click Open, then Open again in the dialog

or from terminal:

```
xattr -dr com.apple.quarantine /Applications/PortTray.app
```

after that it just opens normally.

## what it does

- lists open ports with the owning app and PID
- switch between Listening (TCP), Established, and UDP
- filter by port number or app name
- Kill button on every row (SIGTERM, with a confirm). right click a row for Force Kill (SIGKILL)
- right click also gives you Open in Browser for local web ports, plus copy PID / port / address
- each row is tagged `local` (loopback only) or `exposed` (reachable from the network), so you can spot something listening on all interfaces at a glance
- live count badge next to the menu bar icon
- global hotkey: Cmd+Shift+P toggles the popover from anywhere
- Open at Login toggle in the gear menu
- auto refreshes every few seconds

killing a process owned by another user fails with a permission notice. that needs sudo, which this app does not do on purpose.

## build it yourself

needs the swift toolchain (comes with xcode).

```
git clone https://github.com/Koushith/porttray.git
cd porttray
./build.sh
open PortTray.app
```

`build.sh` compiles a release binary, assembles `PortTray.app`, and ad-hoc signs it so it runs locally.

## notes

- Open at Login registers from wherever the app currently lives, so move it to `/Applications` before turning it on. otherwise macOS may not relaunch it after a reboot.
- everything is read from `lsof` and processes are signalled with `/bin/kill`. no kernel extensions, no elevated privileges, around 1 to 2 MB, zero runtime dependencies.

## how it's built

swift, AppKit `NSStatusItem` + `NSPopover`, SwiftUI for the popover content.

```
Sources/PortTray/
  PortTrayApp.swift    app entry
  AppDelegate.swift    status item, popover, global hotkey, count badge
  PortListView.swift   popover UI and rows
  PortStore.swift      observable state and scan mode
  PortScanner.swift    lsof scan and kill
  LoginItem.swift      SMAppService launch at login
  MenuBarIcon.swift    custom template menu bar glyph
  Models.swift         PortEntry, ScanMode, Exposure
```
