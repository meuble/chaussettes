require 'spec_helper'
require 'fileutils'
require 'tempfile'

RSpec.describe Chaussettes::ConfigStore do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_file) { File.join(temp_dir, 'servers.yml') }

  before do
    stub_const('Chaussettes::ConfigStore::CONFIG_DIR', temp_dir)
    stub_const('Chaussettes::ConfigStore::CONFIG_FILE', config_file)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#all' do
    it 'returns empty array when no config exists' do
      store = Chaussettes::ConfigStore.new
      expect(store.all).to eq([])
    end

    it 'returns servers from config file' do
      server_data = [
        { id: '1', host: 'example.com', user: 'test', ssh_port: 22, socks_port: 7070, key_path: '~/.ssh/id_rsa',
          alias: 'Test' }
      ]
      File.write(config_file, YAML.dump(server_data))

      store = Chaussettes::ConfigStore.new
      servers = store.all

      expect(servers.length).to eq(1)
      expect(servers.first.host).to eq('example.com')
    end
  end

  describe '#find' do
    it 'finds server by id' do
      server_data = [
        { id: 'abc123', host: 'example.com', user: 'test', ssh_port: 22, socks_port: 7070, key_path: '~/.ssh/id_rsa',
          alias: 'Test' }
      ]
      File.write(config_file, YAML.dump(server_data))

      store = Chaussettes::ConfigStore.new
      server = store.find('abc123')

      expect(server).not_to be_nil
      expect(server.host).to eq('example.com')
    end

    it 'returns nil for non-existent id' do
      store = Chaussettes::ConfigStore.new
      expect(store.find('nonexistent')).to be_nil
    end
  end

  describe '#save' do
    it 'saves new server' do
      store = Chaussettes::ConfigStore.new
      server = Chaussettes::Server.new(host: 'example.com', user: 'test')

      store.save(server)

      expect(File.exist?(config_file)).to be true
      data = YAML.load_file(config_file)
      expect(data.first[:host]).to eq('example.com')
    end

    it 'updates existing server' do
      store = Chaussettes::ConfigStore.new
      server = Chaussettes::Server.new(host: 'example.com', user: 'test')
      store.save(server)

      server.host = 'updated.com'
      store.save(server)

      data = YAML.load_file(config_file)
      expect(data.first[:host]).to eq('updated.com')
    end
  end

  describe '#delete' do
    it 'removes server by id' do
      store = Chaussettes::ConfigStore.new
      server = Chaussettes::Server.new(host: 'example.com', user: 'test')
      store.save(server)

      store.delete(server.id)

      data = YAML.load_file(config_file)
      expect(data).to be_empty
    end
  end

  describe '#clear' do
    it 'removes all servers' do
      store = Chaussettes::ConfigStore.new
      server = Chaussettes::Server.new(host: 'example.com', user: 'test')
      store.save(server)

      store.clear

      data = YAML.load_file(config_file)
      expect(data).to be_empty
    end
  end
end
