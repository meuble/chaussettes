require 'spec_helper'

RSpec.describe Chaussettes::Server do
  describe '#initialize' do
    it 'creates a server with default values' do
      server = Chaussettes::Server.new(host: 'example.com', user: 'test')

      expect(server.host).to eq('example.com')
      expect(server.user).to eq('test')
      expect(server.ssh_port).to eq(22)
      expect(server.socks_port).to eq(7070)
      expect(server.key_path).to eq(File.expand_path('~/.ssh/id_rsa'))
      expect(server.id).not_to be_nil
    end

    it 'accepts custom values' do
      server = Chaussettes::Server.new(
        host: 'example.com',
        user: 'admin',
        ssh_port: 2222,
        socks_port: 1080,
        key_path: '~/.ssh/custom_key',
        alias: 'My Server'
      )

      expect(server.ssh_port).to eq(2222)
      expect(server.socks_port).to eq(1080)
      expect(server.key_path).to eq('~/.ssh/custom_key')
      expect(server.alias_name).to eq('My Server')
    end
  end

  describe '#valid?' do
    it 'returns true with valid attributes' do
      server = Chaussettes::Server.new(host: 'example.com', user: 'test')
      expect(server.valid?).to be true
    end

    it 'returns false without host' do
      server = Chaussettes::Server.new(user: 'test')
      expect(server.valid?).to be false
    end

    it 'returns false without user' do
      server = Chaussettes::Server.new(host: 'example.com')
      expect(server.valid?).to be false
    end

    it 'returns false with invalid SSH port' do
      server = Chaussettes::Server.new(host: 'example.com', user: 'test', ssh_port: 99_999)
      expect(server.valid?).to be false
    end

    it 'returns false with invalid SOCKS port' do
      server = Chaussettes::Server.new(host: 'example.com', user: 'test', socks_port: 0)
      expect(server.valid?).to be false
    end
  end

  describe '#errors' do
    it 'returns empty array for valid server' do
      server = Chaussettes::Server.new(host: 'example.com', user: 'test')
      expect(server.errors).to be_empty
    end

    it 'returns errors for invalid server' do
      server = Chaussettes::Server.new
      errors = server.errors

      expect(errors).to include('Host is required')
      expect(errors).to include('User is required')
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      server = Chaussettes::Server.new(
        host: 'example.com',
        user: 'test',
        alias: 'Test Server'
      )

      hash = server.to_h
      expect(hash[:host]).to eq('example.com')
      expect(hash[:user]).to eq('test')
      expect(hash[:alias_name]).to eq('Test Server')
      expect(hash[:id]).not_to be_nil
    end
  end

  describe '#display_name' do
    it 'returns alias when present' do
      server = Chaussettes::Server.new(
        host: 'example.com',
        user: 'test',
        alias: 'My Server'
      )
      expect(server.display_name).to eq('My Server')
    end

    it 'returns user@host when alias is empty' do
      server = Chaussettes::Server.new(host: 'example.com', user: 'test')
      expect(server.display_name).to eq('test@example.com')
    end
  end
end
