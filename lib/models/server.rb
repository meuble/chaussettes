module Chaussettes
  class Server
    attr_accessor :id, :alias_name, :host, :user, :ssh_port, :socks_port, :key_path

    DEFAULT_SSH_PORT = 22
    DEFAULT_SOCKS_PORT = 7070
    DEFAULT_KEY_PATH = File.expand_path('~/.ssh/id_rsa')

    def initialize(attributes = {})
      @id = attributes[:id] || generate_id
      @alias_name = attributes[:alias_name] || attributes[:alias] || ''
      @host = attributes[:host] || ''
      @user = attributes[:user] || ''
      @ssh_port = attributes[:ssh_port] || attributes[:port] || DEFAULT_SSH_PORT
      @socks_port = attributes[:socks_port] || DEFAULT_SOCKS_PORT
      @key_path = attributes[:key_path] || DEFAULT_KEY_PATH
    end

    def valid?
      !@host.empty? && !@user.empty? && valid_ports?
    end

    def errors
      errors = []
      errors << 'Host is required' if @host.empty?
      errors << 'User is required' if @user.empty?
      errors << 'SSH port must be between 1 and 65535' unless valid_port?(@ssh_port)
      errors << 'SOCKS port must be between 1 and 65535' unless valid_port?(@socks_port)
      errors
    end

    def to_h
      {
        id: @id,
        alias_name: @alias_name,
        host: @host,
        user: @user,
        ssh_port: @ssh_port,
        socks_port: @socks_port,
        key_path: @key_path
      }
    end

    def display_name
      @alias_name.empty? ? "#{@user}@#{@host}" : @alias_name
    end

    private

    def generate_id
      SecureRandom.uuid
    end

    def valid_ports?
      valid_port?(@ssh_port) && valid_port?(@socks_port)
    end

    def valid_port?(port)
      port.is_a?(Integer) && port >= 1 && port <= 65_535
    end
  end
end
