require_relative 'logger'

module Chaussettes
  class ProxyManager
    def initialize
      @interface = detect_primary_interface
      Logger.info("Detected primary network interface: #{@interface}")
    end

    attr_reader :interface

    def enable_proxy(port)
      Logger.info("Enabling SOCKS proxy on interface #{@interface} at port #{port}")
      return false unless @interface

      set_proxy_server(port)
      set_proxy_state('on')
      Logger.info('SOCKS proxy enabled successfully')
      true
    end

    def disable_proxy
      Logger.info("Disabling SOCKS proxy on interface #{@interface}")
      return false unless @interface

      set_proxy_state('off')
      Logger.info('SOCKS proxy disabled successfully')
      true
    end

    def proxy_enabled?
      return false unless @interface

      output = `networksetup -getsocksfirewallproxy "#{@interface}" 2>/dev/null`
      enabled = output.include?('Enabled: Yes')
      Logger.debug("Proxy enabled check: #{enabled}")
      enabled
    end

    def proxy_settings
      return nil unless @interface

      output = `networksetup -getsocksfirewallproxy "#{@interface}" 2>/dev/null`
      settings = parse_proxy_settings(output)
      Logger.debug("Current proxy settings: #{settings.inspect}")
      settings
    end

    private

    def detect_primary_interface
      Logger.debug('Detecting primary network interface')

      # Method 1: Try to get the interface used for the default route
      default_interface = nil
      begin
        route_output = `route -n get default 2>/dev/null`
        if route_output =~ /interface:\s*(\w+)/
          default_interface = ::Regexp.last_match(1).strip
          Logger.debug("Default route interface: #{default_interface}")
        end
      rescue StandardError => e
        Logger.debug("Could not get default route: #{e.message}")
      end

      # Method 2: Map the hardware interface to a network service name
      if default_interface
        service = find_service_for_device(default_interface)
        if service
          Logger.info("Detected primary interface from default route: #{service} (#{default_interface})")
          return service
        end
      end

      # Method 3: Find the first active (non-VPN, non-virtual) interface
      service = find_first_active_interface
      if service
        Logger.info("Detected primary interface (first active): #{service}")
        return service
      end

      # Fallback to Wi-Fi
      Logger.warn('Could not detect primary interface, falling back to Wi-Fi')
      'Wi-Fi'
    end

    def find_service_for_device(device_name)
      # Get hardware port info and find which service uses this device
      output = `networksetup -listallhardwareports 2>/dev/null`

      # Parse the output to find service name for the device
      current_service = nil
      output.each_line do |line|
        if line =~ /^Hardware Port:\s*(.+)$/
          current_service = ::Regexp.last_match(1).strip
        elsif line =~ /^Device:\s*(\w+)/ && ::Regexp.last_match(1).strip == device_name
          return current_service if current_service
        end
      end

      nil
    end

    def find_first_active_interface
      # Get all services and check which ones are enabled and have IP addresses
      services_output = `networksetup -listallnetworkservices 2>/dev/null`

      services_output.each_line do |line|
        next if line.start_with?('An asterisk')

        service = line.strip
        next if service.empty?
        next if service.include?('*') # Disabled service

        # Skip VPN and virtual interfaces
        next if service.downcase.include?('vpn')
        next if service.downcase.include?('virtual')
        next if service.downcase.include?('thunderbolt bridge')

        # Check if this service has an IP address (is active)
        info = `networksetup -getinfo "#{service}" 2>/dev/null`
        next unless info =~ /IP address:\s*(\d+\.\d+\.\d+\.\d+)/

        ip = ::Regexp.last_match(1).strip
        return service unless ip.empty? || ip == '0.0.0.0'
      end

      nil
    end

    def set_proxy_server(port)
      Logger.debug("Setting proxy server to 127.0.0.1:#{port}")
      result = system("networksetup -setsocksfirewallproxy \"#{@interface}\" 127.0.0.1 #{port} >/dev/null 2>&1")
      Logger.error('Failed to set proxy server') unless result
      result
    end

    def set_proxy_state(state)
      Logger.debug("Setting proxy state to: #{state}")
      result = system("networksetup -setsocksfirewallproxystate \"#{@interface}\" #{state} >/dev/null 2>&1")
      Logger.error('Failed to set proxy state') unless result
      result
    end

    def parse_proxy_settings(output)
      settings = {}
      output.each_line do |line|
        if line =~ /^Enabled:\s*(.+)$/
          settings[:enabled] = ::Regexp.last_match(1).strip == 'Yes'
        elsif line =~ /^Server:\s*(.+)$/
          settings[:server] = ::Regexp.last_match(1).strip
        elsif line =~ /^Port:\s*(.+)$/
          settings[:port] = ::Regexp.last_match(1).strip.to_i
        end
      end
      settings
    end
  end
end
