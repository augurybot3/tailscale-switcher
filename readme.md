# Tailscale Active User Switcher
### Based on current logged-in MacOS Profile

Detects existing macOS users and displays them
Interactively prompts for:

macOS username
Corresponding Tailscale profile name

This assumes you have Tailscale installed and multiple user accounts on both your Mac and Tailscale application.

You can set a nickname for a Tailscale username by typing:

```shell
# to see the current active logged in Tailscale username
tailscale switch --list
```
the currently logged in Tailscale user is designated with a `*`
example:
`john@example.com john@gmail.com *`

you can set a nickname for the username like so:

```shell
tailscale set --nickname=john
```
checking the switch list again will show

```shell
john@example.com john@gmail.com *
```



This script validates if users exist (with option to proceed anyway)
Creates a configuration file mapping macOS users to Tailscale profiles
Sets up the automation for each specified user
Provides a summary of the configuration

To use this script:

Save it as setup_tailscale_switcher.sh
Make it executable: chmod +x setup_tailscale_switcher.sh
Run with sudo: sudo ./setup_tailscale_switcher.sh
Follow the interactive prompts

The script requires jq for processing the JSON configuration (it will warn if not installed).
