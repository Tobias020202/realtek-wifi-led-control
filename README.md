# Realtek Wi-Fi LED Control for Windows

![Platform](https://img.shields.io/badge/platform-Windows-0078D4)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![License](https://img.shields.io/badge/license-MIT-green)

This little tool controls the status LED of Realtek Wi-Fi adapters on Windows. Turn the light off when it bothers you and bring it back whenever you miss it.

You never flash firmware and never patch a driver. The tool simply writes one registry value that the original Realtek driver already understands.

## How it works

Every time the adapter starts, the driver reads the value `LedCtrl` from its network class key. The tool sets that value for you.

| Value | What the LED does |
|-------|-------------------|
| `0` | stays off |
| `1` | blinks, which is the driver default |
| `2` | stays on |

## What you need

* Windows 10 or 11 with PowerShell 5.1, which ships with the system
* A Realtek adapter that uses the `rtwlanu.sys` driver family
* Administrator rights, the tool asks for them when it starts

Known supported chips are RTL8188, 8192, 8723, 8812, 8814, 8821 and 8822. The tool checks every adapter before it changes anything and warns you when a driver does not seem to support LED control.

## Quick start

1. Plug in your adapter. The stock driver is enough.
2. Open `led-off.cmd`. Windows asks for admin rights, so confirm with Yes.
3. When the tool finds more than one Realtek adapter, pick yours from the menu. Then the LED goes dark.

To bring the blinking back, open `led-blink.cmd`. Reverts are always one click away.

## Command line

Prefer the console? Run the script directly, for example in an admin PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File Set-RealtekWifiLed.ps1 -Value 0 -Adapter 1
```

| Parameter | What it does |
|-----------|--------------|
| `-Value 0\|1\|2` | Chooses the state: off, blink or on. Defaults to `0`. |
| `-Adapter <number>` | Picks an adapter by its number from the printed list. |
| `-Adapter <text>` | Picks an adapter by name, for example `8192` finds the RTL8192EU. |
| `-All` | Applies the change to every Realtek adapter it finds. |
| `-DryRun` | Shows what would happen without touching anything. |
| `-NoRestart` | Skips the restart. The driver reads the value the next time you plug the adapter in. |
| `-Pause` | Waits for Enter before the window closes. The `.cmd` files use this. |

## Picking the right adapter

The tool lists every Realtek Wi-Fi adapter it finds together with its registry key. One adapter means no questions, the tool just uses it. Several adapters mean you can answer the menu, name a number with `-Adapter`, or match a piece of the name like `8812`. `-All` applies your choice everywhere.

## Good to know

* Your setting survives reboots and replugging.
* A driver update resets the value to the Realtek default. Run the tool again when that happens.
* Every write comes with a backup. The tool exports the full registry key into the `backup` folder first, and you restore it by double clicking the `.reg` file.
* Some cheap sticks wire the LED straight to the USB power line. No software can switch those off, and tape is the only cure there.
* The tool does not guess. It checks the driver INF and the driver file for `LedCtrl` support and tells you when it cannot find it.

## Where this knowledge comes from

The strings `LedCtrl` and `LedStrategy` sit in plain sight inside `rtwlanu.sys`. Realtek INF files install `LedCtrl = "1"` as their default. The open source Linux drivers for the same chips document the identical option as `rtw_led_ctrl`, and the values line up: 0 off, 1 blink, 2 on.

## Safety

* The tool changes one registry value and nothing else.
* It creates a backup before every write.
* It never touches firmware or driver files, so your adapter cannot get bricked.
* It works with the signed stock driver and needs no test signing.

## License

MIT. See [LICENSE](LICENSE).
