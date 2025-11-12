#!/bin/sh

# Load jshn library
. /usr/share/libubox/jshn.sh

# Configuration
TELEGRAM_TOKEN=""
ALLOWED_USER_ID=""
SCRIPT_PATH="/tmp/tg_bot.sh"
OFFSET_FILE="/tmp/tg_bot_offset"

# Load offset from file or start from 0
if [ -f "$OFFSET_FILE" ]; then
    OFFSET=$(cat "$OFFSET_FILE")
else
    OFFSET=0
fi

# Function to send message
send_msg() {
    local chat_id="$1"
    local text="$2"
    
    json_init
    json_add_int chat_id "$chat_id"
    json_add_string text "$text"
    local json_data=$(json_dump)
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$json_data" > /dev/null
}

# Command handlers
cmd_hello() {
    local chat_id="$1"
    send_msg "$chat_id" "Hello World!"
}

cmd_viewscript() {
    local chat_id="$1"
    
    # Send as document
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
        -F "chat_id=$chat_id" \
        -F "document=@${SCRIPT_PATH}" \
        -F "caption=Current bot script" > /dev/null
}

cmd_exec() {
    local chat_id="$1"
    local command="$2"
    
    echo "Executing: $command"
    local output=$(eval "$command" 2>&1)
    
    if [ -z "$output" ]; then
        send_msg "$chat_id" "Command executed (no output)"
    else
        send_msg "$chat_id" "$output"
    fi
}

# Main message handler
handle_message() {
    local chat_id="$1"
    local user_id="$2"
    local message="$3"
    
    # Check authorization
    if [ "$user_id" != "$ALLOWED_USER_ID" ]; then
        send_msg "$chat_id" "Access denied"
        return
    fi
    
    # Route commands
    case "$message" in
        /hello)
            cmd_hello "$chat_id"
            ;;
        /viewscript)
            cmd_viewscript "$chat_id"
            ;;
        /exec*)
            local command=$(echo "$message" | sed 's/^\/exec //')
            cmd_exec "$chat_id" "$command"
            ;;
        *)
            send_msg "$chat_id" "Unknown command. Available: /hello /exec /viewscript"
            ;;
    esac
}

# Handle file update
handle_file() {
    local chat_id="$1"
    local user_id="$2"
    local file_id="$3"
    local file_name="$4"
    
    # Check authorization
    if [ "$user_id" != "$ALLOWED_USER_ID" ]; then
        send_msg "$chat_id" "Access denied"
        return
    fi
    
    # Check file extension
    case "$file_name" in
        *.sh)
            send_msg "$chat_id" "Updating script..."
            
            # Get file path
            local file_info=$(curl -s "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getFile?file_id=${file_id}")
            local file_path=$(echo "$file_info" | jsonfilter -e '@.result.file_path')
            
            if [ -z "$file_path" ]; then
                send_msg "$chat_id" "Error: Could not get file"
                return
            fi
            
            # Download and replace directly
            curl -s "https://api.telegram.org/file/bot${TELEGRAM_TOKEN}/${file_path}" -o "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            
            send_msg "$chat_id" "Updated! Restarting..."
            sleep 2
            exec "$SCRIPT_PATH"
            ;;
        *)
            send_msg "$chat_id" "Only .sh files accepted"
            ;;
    esac
}

# Parse updates from Telegram
parse_updates() {
    local updates="$1"
    
    echo "$updates" | grep -q '"update_id"' || return 1
    
    CHAT_ID=$(echo "$updates" | jsonfilter -e '@.result[*].message.chat.id' | tail -1)
    USER_ID=$(echo "$updates" | jsonfilter -e '@.result[*].message.from.id' | tail -1)
    USER_MESSAGE=$(echo "$updates" | jsonfilter -e '@.result[*].message.text' | tail -1)
    NEW_OFFSET=$(echo "$updates" | jsonfilter -e '@.result[*].update_id' | tail -1)
    FILE_ID=$(echo "$updates" | jsonfilter -e '@.result[*].message.document.file_id' | tail -1)
    FILE_NAME=$(echo "$updates" | jsonfilter -e '@.result[*].message.document.file_name' | tail -1)
    
    [ -n "$NEW_OFFSET" ] || return 1
    
    return 0
}

# Main loop
main() {
    echo "Bot started (PID: $$, OFFSET: $OFFSET)"
    
    while true; do
        local updates=$(curl -s "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getUpdates?offset=${OFFSET}&timeout=30")
        
        if parse_updates "$updates"; then
            # Update and save offset FIRST
            OFFSET=$((NEW_OFFSET + 1))
            echo "$OFFSET" > "$OFFSET_FILE"
            
            # Handle file or message
            if [ -n "$FILE_ID" ] && [ -n "$FILE_NAME" ]; then
                echo "File received: $FILE_NAME (offset: $OFFSET)"
                handle_file "$CHAT_ID" "$USER_ID" "$FILE_ID" "$FILE_NAME"
            elif [ -n "$USER_MESSAGE" ] && [ -n "$CHAT_ID" ]; then
                echo "Message: $USER_MESSAGE (offset: $OFFSET)"
                handle_message "$CHAT_ID" "$USER_ID" "$USER_MESSAGE"
            fi
        fi
        
        sleep 1
    done
}

# Start bot
main
