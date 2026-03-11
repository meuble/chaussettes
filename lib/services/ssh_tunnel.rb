require_relative 'logger'

module Chaussettes
  class SSHTunnel
    attr_reader :server, :pid, :connected, :connected_at, :latency, :bytes_sent, :bytes_received, :active_connections

    def initialize
      @server = nil
      @pid = nil
      @connected = false
      @connected_at = nil
      @latency = nil
      @latency_thread = nil
      @stop_latency_check = false
      @bytes_sent = 0
      @bytes_received = 0
      @active_connections = 0
      @traffic_thread = nil
      @stop_traffic_check = false
      @baseline_bytes_sent = 0
      @baseline_bytes_received = 0
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

          # Start traffic monitoring
          start_traffic_monitoring

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

      # Stop traffic monitoring
      stop_traffic_monitoring

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
      @bytes_sent = 0
      @bytes_received = 0
      @active_connections = 0
      @baseline_bytes_sent = 0
      @baseline_bytes_received = 0
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

    def format_bytes(bytes)
      return '0 B' if bytes.nil? || bytes == 0

      units = %w[B KB MB GB]
      unit_index = 0
      size = bytes.to_f

      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end

      if unit_index == 0
        "#{size.to_i} #{units[unit_index]}"
      else
        "#{size.round(2)} #{units[unit_index]}"
      end
    end

    def format_traffic_stats
      sent = format_bytes(@bytes_sent)
      received = format_bytes(@bytes_received)
      "Sent: #{sent} | Received: #{received}"
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

    def start_traffic_monitoring
      @stop_traffic_check = false
      @traffic_thread = Thread.new do
        loop do
          break if @stop_traffic_check

          check_traffic
          sleep 3
        end
      end
    end

    def stop_traffic_monitoring
      @stop_traffic_check = true
      @traffic_thread&.join(1)
      @traffic_thread = nil
    end

    def check_traffic
      return unless @pid && process_alive?(@pid)

      begin
        # Use lsof to count active network connections for the SSH process
        output = `lsof -p #{@pid} -i TCP 2>/dev/null`
        if $?.success?
          # Count lines that contain network connections (skip header)
          lines = output.lines.reject { |l| l.start_with?('COMMAND') }
          @active_connections = lines.count { |l| l.include?('TCP') }
          Logger.debug("SSH process #{@pid} has #{@active_connections} active connections")
        end

        # Try to get network interface stats for loopback interface
        # This gives us system-wide lo0 stats which includes SOCKS traffic
        ifconfig_output = `netstat -ib 2>/dev/null | grep -E '^lo0' | head -1`
        if $?.success? && !ifconfig_output.empty?
          # Parse netstat output: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
          # We want Ibytes (received) and Obytes (sent)
          parts = ifconfig_output.split
          if parts.length >= 9
            current_received = parts[6].to_i
            current_sent = parts[8].to_i

            # On first check, set baseline
            if @baseline_bytes_received == 0 && @baseline_bytes_sent == 0
              @baseline_bytes_received = current_received
              @baseline_bytes_sent = current_sent
            else
              # Calculate delta from baseline
              @bytes_received = [current_received - @baseline_bytes_received, 0].max
              @bytes_sent = [current_sent - @baseline_bytes_sent, 0].max
            end

            Logger.debug("Traffic stats - Sent: #{format_bytes(@bytes_sent)}, Received: #{format_bytes(@bytes_received)}")
          end
        end
      rescue StandardError => e
        Logger.debug("Traffic check error: #{e.message}")
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
