require 'spec_helper'

RSpec.describe Chaussettes::ProxyManager do
  let(:manager) { Chaussettes::ProxyManager.new }

  before do
    allow(manager).to receive(:`).and_return('')
    allow(manager).to receive(:system).and_return(true)
  end

  describe '#initialize' do
    it 'detects primary network interface' do
      # Stub the backtick call BEFORE creating the instance
      allow_any_instance_of(Chaussettes::ProxyManager).to receive(:`).with('networksetup -listnetworkserviceorder 2>/dev/null').and_return("(1) Wi-Fi\n")
      allow_any_instance_of(Chaussettes::ProxyManager).to receive(:`).and_return('')
      allow_any_instance_of(Chaussettes::ProxyManager).to receive(:system).and_return(true)

      new_manager = Chaussettes::ProxyManager.new
      expect(new_manager.interface).to eq('Wi-Fi')
    end
  end

  describe '#enable_proxy' do
    it 'sets proxy server and enables it' do
      test_manager = Chaussettes::ProxyManager.new
      allow(test_manager).to receive(:`).and_return('')
      allow(test_manager).to receive(:system).and_return(true)
      interface = test_manager.interface

      expect(test_manager).to receive(:system).with("networksetup -setsocksfirewallproxy \"#{interface}\" 127.0.0.1 7070 >/dev/null 2>&1")
      expect(test_manager).to receive(:system).with("networksetup -setsocksfirewallproxystate \"#{interface}\" on >/dev/null 2>&1")

      test_manager.enable_proxy(7070)
    end
  end

  describe '#disable_proxy' do
    it 'disables proxy' do
      test_manager = Chaussettes::ProxyManager.new
      allow(test_manager).to receive(:`).and_return('')
      allow(test_manager).to receive(:system).and_return(true)
      interface = test_manager.interface

      expect(test_manager).to receive(:system).with("networksetup -setsocksfirewallproxystate \"#{interface}\" off >/dev/null 2>&1")

      test_manager.disable_proxy
    end
  end

  describe '#proxy_enabled?' do
    it 'returns true when proxy is enabled' do
      test_manager = Chaussettes::ProxyManager.new
      interface = test_manager.interface
      allow(test_manager).to receive(:`).with("networksetup -getsocksfirewallproxy \"#{interface}\" 2>/dev/null").and_return("Enabled: Yes\n")
      allow(test_manager).to receive(:system).and_return(true)

      expect(test_manager.proxy_enabled?).to be true
    end

    it 'returns false when proxy is disabled' do
      test_manager = Chaussettes::ProxyManager.new
      interface = test_manager.interface
      allow(test_manager).to receive(:`).with("networksetup -getsocksfirewallproxy \"#{interface}\" 2>/dev/null").and_return("Enabled: No\n")
      allow(test_manager).to receive(:system).and_return(true)

      expect(test_manager.proxy_enabled?).to be false
    end
  end

  describe '#proxy_settings' do
    it 'returns parsed proxy settings' do
      test_manager = Chaussettes::ProxyManager.new
      interface = test_manager.interface
      output = "Enabled: Yes\nServer: 127.0.0.1\nPort: 7070\n"
      allow(test_manager).to receive(:`).with("networksetup -getsocksfirewallproxy \"#{interface}\" 2>/dev/null").and_return(output)
      allow(test_manager).to receive(:system).and_return(true)

      settings = test_manager.proxy_settings

      expect(settings[:enabled]).to be true
      expect(settings[:server]).to eq('127.0.0.1')
      expect(settings[:port]).to eq(7070)
    end
  end
end
