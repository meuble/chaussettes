require 'securerandom'
require_relative 'models/server'
require_relative 'services/config_store'
require_relative 'services/proxy_manager'
require_relative 'services/ssh_tunnel'
require_relative 'ui/tui_app'

module Chaussettes
  class App
    def self.launch
      TUIApp.new.launch
    end
  end
end
