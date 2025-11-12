# openWRT-ssh-tg-bot

## Requirements

- `curl` package
- `jshn` library (included by default in OpenWRT)

## Setup

1. Edit the script and set your credentials:
   - `TELEGRAM_TOKEN` - your bot token
   - `ALLOWED_USER_ID` - your Telegram user ID

2. Save script to `/tmp/tg_bot.sh` and make executable:
```sh
chmod +x /tmp/tg_bot.sh
```

3. Run the bot:
```sh
/tmp/tg_bot.sh &
```

## Features

- **Hot-reload**: Send any `.sh` file to update the bot on-the-fly
- **Remote command execution**: `/exec <command>`
- **View current script**: `/viewscript` (sends as file)
- **Persistent offset**: Survives restarts without duplicate message processing
