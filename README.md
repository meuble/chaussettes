# Chaussettes

A minimal macOS TUI (Terminal User Interface) application for managing SSH SOCKS proxy tunnels.

## Features

- **Terminal-based UI** - Clean, keyboard-driven interface using Ratatui
- List configured remote servers in a scrollable table
- Add, edit, and delete server configurations
- Connect/disconnect from servers with keyboard shortcuts
- Automatic SOCKS proxy configuration via macOS network settings
- SSH agent and key-based authentication support
- Comprehensive logging for debugging

## Installation

Clone or download this repository to something like `~/Code/chaussettes`

Install dependencies:

   ```bash
   cd ~/Code/chaussettes
   bundle install
   ```

## Usage

### Running the Application

```bash
./bin/chaussettes
```

You can add the executable to your `PATH` to run it from anywhere.

### First-Time Setup

1. Ensure you have SSH keys set up in `~/.ssh/` or use SSH agent
2. The app will create `~/.config/chaussettes/` for storing server configurations
3. Logs are written to `~/.local/share/chaussettes/logs/chaussettes.log`

### Adding a Server

1. Press **`a`** to open the add server form
2. Fill in the details:
   - **Alias** (optional): A friendly name for the server
   - **Host***: The server hostname or IP address
   - **User***: Your SSH username
   - **SSH Port***: Usually 22 (can be customized)
   - **SOCKS Port***: The local port for the proxy (default: 1080)
   - **Key Path** (optional): Path to your SSH private key (uses SSH agent if not specified)

### Connecting

1. Select a server using `↑/↓` arrow keys
2. Press **`c`** to connect
3. The app will:
   - Establish an SSH tunnel with dynamic port forwarding (`ssh -D`)
   - Enable the SOCKS proxy in macOS network settings
4. Status will show as "● Connected" when successful

### Disconnecting

1. Press **`x`** to disconnect
2. The app will:
   - Close the SSH tunnel
   - Disable the SOCKS proxy in macOS network settings

## Configuration

### Server Configurations

Stored in:

```
~/.config/chaussettes/servers.yml
```

This file is automatically managed by the application.

### Logs

Application logs are stored in:

```
~/.local/share/chaussettes/logs/chaussettes.log
```

Logs include:
- Connection attempts and results
- SSH authentication details
- Proxy configuration changes
- Error messages with stack traces

View logs in real-time:

```bash
tail -f ~/.local/share/chaussettes/logs/chaussettes.log
```

## Requirements

- macOS (uses `networksetup` and `ssh` commands)
- Ruby 3.4+
- SSH client (system `ssh` command)
- SSH keys configured on remote servers or SSH agent running
- Admin privileges may be required for changing network proxy settings

## Testing

Run the test suite:

```bash
bundle exec rspec
```

## Project Structure

```
chaussettes/
├── bin/chaussettes          # Executable entry point
├── lib/
│   ├── chaussettes.rb       # Main module
│   ├── models/
│   │   └── server.rb        # Server configuration model
│   ├── services/
│   │   ├── config_store.rb  # YAML persistence
│   │   ├── logger.rb        # Logging service
│   │   ├── proxy_manager.rb # macOS proxy settings
│   │   └── ssh_tunnel.rb    # SSH connection management
│   └── ui/
│       └── tui_app.rb       # Ratatui TUI application
└── spec/                    # Test suite
```

## Troubleshooting

### SSH Connection Issues

Check the logs for detailed error messages:

```bash
cat ~/.local/share/chaussettes/logs/chaussettes.log
```

Common issues:

 - **Authentication failed**: Ensure your SSH key is loaded in the agent or specify the correct key path
 - **Host key mismatch**: The app automatically accepts new host keys. If a host key changes, restart the app
 - **DNS resolution failed**: Check that the hostname is correct and reachable

### Proxy Not Working

 - Check that the SOCKS proxy is enabled in System Preferences > Network
 - Verify the proxy port matches what you configured (default: 1080)
 - Check logs for proxy configuration errors

### Interface Detection Issues

The app automatically detects your primary network interface by:

 - Checking the default route interface
 - Finding the first active (non-VPN) interface with an IP address
 - Falling back to "Wi-Fi" if detection fails

If proxy settings aren't applying, check that the detected interface in the logs matches your active connection.

## License

MIT
