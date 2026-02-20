require 'yaml'
require 'fileutils'
require_relative 'logger'

module Chaussettes
  class ConfigStore
    CONFIG_DIR = File.expand_path('~/.config/chaussettes')
    CONFIG_FILE = File.join(CONFIG_DIR, 'servers.yml')

    def initialize
      ensure_config_dir
      Logger.debug("ConfigStore initialized. Config file: #{CONFIG_FILE}")
    end

    def all
      unless File.exist?(CONFIG_FILE)
        Logger.debug('Config file does not exist, returning empty array')
        return []
      end

      Logger.debug('Loading servers from config file')
      data = YAML.load_file(CONFIG_FILE) || []
      servers = data.map { |attrs| Server.new(attrs) }
      Logger.info("Loaded #{servers.length} server(s) from config")
      servers
    rescue StandardError => e
      Logger.error("Error loading config file: #{e.message}")
      []
    end

    def find(id)
      Logger.debug("Looking for server with ID: #{id}")
      server = all.find { |server| server.id == id }
      Logger.debug(server ? "Found server: #{server.display_name}" : 'Server not found')
      server
    end

    def save(server)
      Logger.info("Saving server: #{server.display_name} (ID: #{server.id})")
      servers = all
      existing_index = servers.find_index { |s| s.id == server.id }

      if existing_index
        Logger.debug("Updating existing server at index #{existing_index}")
        servers[existing_index] = server
      else
        Logger.debug('Adding new server')
        servers << server
      end

      write_to_file(servers)
      Logger.info('Server saved successfully')
      server
    rescue StandardError => e
      Logger.error("Error saving server: #{e.message}")
      raise
    end

    def delete(id)
      Logger.info("Deleting server with ID: #{id}")
      servers = all.reject { |server| server.id == id }
      write_to_file(servers)
      Logger.info('Server deleted successfully')
      true
    rescue StandardError => e
      Logger.error("Error deleting server: #{e.message}")
      false
    end

    def clear
      Logger.warn('Clearing all servers from config')
      write_to_file([])
    end

    private

    def ensure_config_dir
      FileUtils.mkdir_p(CONFIG_DIR)
    rescue StandardError => e
      Logger.error("Failed to create config directory: #{e.message}")
      raise
    end

    def write_to_file(servers)
      ensure_config_dir
      data = servers.map(&:to_h)
      File.write(CONFIG_FILE, YAML.dump(data))
      Logger.debug("Wrote #{servers.length} server(s) to config file")
    rescue StandardError => e
      Logger.error("Failed to write config file: #{e.message}")
      raise
    end
  end
end
