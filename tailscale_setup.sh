 #!/bin/bash

# Exit on any error
set -e

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (sudo)"
    exit 1
fi

echo "=== Tailscale Auto-Switch Setup ==="
echo "This script will set up automatic Tailscale profile switching for macOS users."
echo

# Initialize user array
declare -a USERS=()
declare -a TAILSCALE_PROFILES=()

# Detect existing users
EXISTING_USERS=$(ls -la /Users | grep -v "Shared\|\.localized\|\." | awk '{print $9}' | tail -n +2)
echo "Detected users: $EXISTING_USERS"
echo

# Interactive user setup
while true; do
    read -p "Enter macOS username (or press Enter to finish): " USERNAME
    
    if [ -z "$USERNAME" ]; then
        break
    fi
    
    if [ ! -d "/Users/$USERNAME" ]; then
        echo "Warning: User '$USERNAME' doesn't exist. Continue anyway? (y/n)"
        read CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
            continue
        fi
    fi
    
    read -p "Enter Tailscale profile name for $USERNAME: " TAILSCALE_PROFILE
    
    USERS+=("$USERNAME")
    TAILSCALE_PROFILES+=("$TAILSCALE_PROFILE")
    
    echo "Added: macOS user '$USERNAME' → Tailscale profile '$TAILSCALE_PROFILE'"
    echo
done

# Check if we have users to configure
if [ ${#USERS[@]} -eq 0 ]; then
    echo "No users specified. Exiting."
    exit 0
fi

echo "Creating configuration for ${#USERS[@]} users..."

# Create tailscale_users.json
echo "Creating configuration file..."
echo "{" > /etc/tailscale_users.json
echo "    \"user_mappings\": {" >> /etc/tailscale_users.json

for i in "${!USERS[@]}"; do
    COMMA=""
    if [ $i -lt $(( ${#USERS[@]} - 1 )) ]; then
        COMMA=","
    fi
    echo "        \"${USERS[$i]}\": \"${TAILSCALE_PROFILES[$i]}\"$COMMA" >> /etc/tailscale_users.json
done

echo "    }" >> /etc/tailscale_users.json
echo "}" >> /etc/tailscale_users.json

chmod 644 /etc/tailscale_users.json

# Create AppleScript for Tailscale switching
echo "Creating AppleScript..."
cat > /usr/local/bin/tailscale_switcher.applescript << 'EOF'
#!/usr/bin/osascript

-- Get current macOS username
set currentUser to do shell script "whoami"

-- Path to config file
set configFile to "/etc/tailscale_users.json"

-- Check if config file exists
set configExists to do shell script "[ -f " & quoted form of configFile & " ] && echo 'exists' || echo 'not exists'"
if configExists is "not exists" then
    display notification "Configuration file not found: " & configFile
    return
end if

-- Get the expected Tailscale account name for this user from config
set expectedTailscaleUser to do shell script "jq -r '.user_mappings.\"" & currentUser & "\"' " & quoted form of configFile

if expectedTailscaleUser is "null" then
    display notification "No Tailscale mapping found for user " & currentUser & " in config"
    return
end if

-- Get current Tailscale account
set tailscaleOutput to do shell script "tailscale switch --list"
set currentTailscaleUser to do shell script "echo " & quoted form of tailscaleOutput & " | grep -E '\\*$' | awk '{print $2}'"

-- Log the current status
log "Current macOS user: " & currentUser
log "Expected Tailscale user: " & expectedTailscaleUser
log "Current Tailscale user: " & currentTailscaleUser

-- Check if correct account is active
if currentTailscaleUser is not equal to expectedTailscaleUser then
    log "Switching Tailscale account to " & expectedTailscaleUser
    do shell script "tailscale switch " & quoted form of expectedTailscaleUser
    
    -- Verify the switch was successful
    set tailscaleOutput to do shell script "tailscale switch --list"
    set newTailscaleUser to do shell script "echo " & quoted form of tailscaleOutput & " | grep -E '\\*$' | awk '{print $2}'"
    
    if newTailscaleUser is equal to expectedTailscaleUser then
        display notification "Successfully switched Tailscale to " & expectedTailscaleUser
    else
        display notification "Failed to switch Tailscale account"
    end if
else
    log "Tailscale already using correct account: " & currentTailscaleUser
end if
EOF

# Set executable permissions
chmod +x /usr/local/bin/tailscale_switcher.applescript

# Compile AppleScript
echo "Compiling AppleScript..."
osacompile -o /usr/local/bin/tailscale_switcher.scpt /usr/local/bin/tailscale_switcher.applescript

# Create LaunchAgent plist
echo "Creating LaunchAgent..."
cat > /tmp/com.local.tailscale.switcher.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.tailscale.switcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/osascript</string>
        <string>/usr/local/bin/tailscale_switcher.scpt</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

# Install for each user
for USER in "${USERS[@]}"; do
    echo "Setting up for user: $USER"
    
    # Create LaunchAgents directory if needed
    mkdir -p /Users/$USER/Library/LaunchAgents
    
    # Copy LaunchAgent plist
    cp /tmp/com.local.tailscale.switcher.plist /Users/$USER/Library/LaunchAgents/
    
    # Set correct ownership
    chown $USER:staff /Users/$USER/Library/LaunchAgents/com.local.tailscale.switcher.plist
    
    # Load the LaunchAgent (if user is currently logged in)
    if who | grep -q "^$USER "; then
        echo "User $USER is logged in. Loading LaunchAgent..."
        su - $USER -c "launchctl load -w /Users/$USER/Library/LaunchAgents/com.local.tailscale.switcher.plist" || echo "Could not load LaunchAgent for $USER now, but it will load on next login"
    fi
done

# Clean up temp file
rm /tmp/com.local.tailscale.switcher.plist

echo
echo "Setup complete! Tailscale will automatically switch profiles on login."
echo
echo "Configuration summary:"
for i in "${!USERS[@]}"; do
    echo "• macOS user '${USERS[$i]}' → Tailscale profile '${TAILSCALE_PROFILES[$i]}'"
done
echo
echo "For testing, you can run: sudo -u [username] /usr/bin/osascript /usr/local/bin/tailscale_switcher.scpt"

# Check jq dependency
if ! command -v jq &> /dev/null; then
    echo
    echo "WARNING: 'jq' command not found. Please install it:"
    echo "brew install jq"
    echo
fi
