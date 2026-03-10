require_relative 'logger'

module Chaussettes
  class SSHTunnel
    attr_reader :server, :pid, :connected, :connected_at, :latency

    def initialize
      @server = nil
      @pid = nil
      @connected = false
      @connected_at = nil
      @latency = nil
      @latency_thread = nil
      @stop_latency_check = false
    end

    def connect(server)
      Logger.info("Attempting to connect to server: #{server.display_name} (#{server.host}:#{server.ssh_port})")

      return false if @connected
      return false unless server.valid?

      @server = server

      begin
        # Build SSH command with SOCKS proxy (-D option)
        # Equivalent to: ssh -N -D <socks_port> -p <ssh_port> -i <key> user@host
        cmd = build_ssh_command(server)

        Logger.debug("Executing SSH command: #{cmd}")

        # Spawn SSH process
        @pid = spawn(cmd, out: '/dev/null', err: '/dev/null')

        Logger.debug("SSH process started with PID: #{@pid}")

        # Wait a moment for the connection to establish
        sleep 2

        # Check if process is still running
        if process_alive?(@pid)
          @connected = true
          @connected_at = Time.now
          Logger.info("SSH tunnel successfully started for #{server.display_name}")
          Logger.info("SOCKS proxy available at 127.0.0.1:#{server.socks_port}")

          # Start latency monitoring
          start_latency_monitoring

          true
        else
          Logger.error('SSH process died immediately')
          false
        end
      rescue StandardError => e
        Logger.error("SSH connection error for #{server.host}: #{e.class} - #{e.message}")
        Logger.debug("Error backtrace: #{e.backtrace&.first(5)&.join("\n")}")
        false
      end
    end

    def disconnect
      return false unless @connected

      Logger.info("Disconnecting from server: #{@server&.display_name}")

      # Stop latency monitoring
      stop_latency_monitoring

      @connected = false

      if @pid && process_alive?(@pid)
        # Kill the SSH process
        Process.kill('TERM', @pid)

        # Wait for process to exit
        begin
          Timeout.timeout(5) { Process.wait(@pid) }
        rescue Timeout::Error
          Logger.warn('SSH process did not exit gracefully, forcing kill')
          begin
            Process.kill('KILL', @pid)
          rescue StandardError
            nil
          end
        end
      end

      Logger.info('SSH tunnel disconnected successfully')

      @server = nil
      @pid = nil
      @connected_at = nil
      @latency = nil
      true
    end

    def connected?
      @connected && @pid && process_alive?(@pid)
    end

    def current_server
      @server
    end

    def connection_duration
      return nil unless @connected_at

      Time.now - @connected_at
    end

    def format_duration(seconds)
      return '00:00:00' unless seconds

      hours = seconds.to_i / 3600
      minutes = (seconds.to_i % 3600) / 60
      secs = seconds.to_i % 60
      format('%02d:%02d:%02d', hours, minutes, secs)
    end

    def format_latency
      @latency ? "#{@latency}ms" : '--'
    end

    private

    def start_latency_monitoring
      @stop_latency_check = false
      @latency_thread = Thread.new do
        loop do
          break if @stop_latency_check

          check_latency
          sleep 5
        end
      end
    end

    def stop_latency_monitoring
      @stop_latency_check = true
      @latency_thread&.join(1)
      @latency_thread = nil
    end

    def check_latency
      return unless @server

      begin
        start_time = Time.now
        # Ping the remote host (1 packet, 2 second timeout)
        `ping -c 1 -W 2 #{@server.host} 2>/dev/null`
        if $?.success?
          @latency = ((Time.now - start_time) * 1000).round(2)
          Logger.debug("Latency to #{@server.host}: #{@latency}ms")
        else
          @latency = nil
          Logger.debug("Ping failed to #{@server.host}")
        end
      rescue StandardError => e
        Logger.debug("Latency check error: #{e.message}")
        @latency = nil
      end
    end

    def build_ssh_command(server)
      cmd_parts = ['ssh']

      # -N: Don't execute remote commands (just port forwarding)
      cmd_parts << '-N'

      # -D: Dynamic port forwarding (SOCKS proxy)
      cmd_parts << '-D' << "127.0.0.1:#{server.socks_port}"

      # -p: SSH port
      cmd_parts << '-p' << server.ssh_port.to_s

      # -o: SSH options
      cmd_parts << '-o' << 'StrictHostKeyChecking=no'
      cmd_parts << '-o' << 'UserKnownHostsFile=/dev/null'
      cmd_parts << '-o' << 'ServerAliveInterval=30'
      cmd_parts << '-o' << 'ServerAliveCountMax=3'

      # -i: Identity file (key) - only if specified and exists
      cmd_parts << '-i' << server.key_path if server.key_path && !server.key_path.empty? && File.exist?(server.key_path)

      # User@Host
      cmd_parts << "#{server.user}@#{server.host}"

      cmd_parts.join(' ')
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end
  end
end
