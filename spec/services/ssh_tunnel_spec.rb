require 'spec_helper'

RSpec.describe Chaussettes::SSHTunnel do
  let(:tunnel) { Chaussettes::SSHTunnel.new }
  let(:server) do
    Chaussettes::Server.new(
      host: 'example.com',
      user: 'test',
      ssh_port: 22,
      socks_port: 7070,
      key_path: '~/.ssh/id_rsa'
    )
  end

  describe '#initialize' do
    it 'initializes with disconnected state' do
      expect(tunnel.connected?).to be false
      expect(tunnel.current_server).to be_nil
    end
  end

  describe '#connect' do
    context 'with valid server' do
      before do
        mock_ssh = double('ssh')
        mock_forward = double('forward')
        allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
        allow(mock_ssh).to receive(:forward).and_return(mock_forward)
        allow(mock_forward).to receive(:dynamic)
        allow(mock_ssh).to receive(:loop)
      end

      it 'returns true on successful connection' do
        allow_any_instance_of(Thread).to receive(:alive?).and_return(true)

        result = tunnel.connect(server)
        expect(result).to be true
      end

      it 'sets connected state' do
        allow_any_instance_of(Thread).to receive(:alive?).and_return(true)

        tunnel.connect(server)
        expect(tunnel.current_server).to eq(server)
      end
    end

    context 'with invalid server' do
      it 'returns false for invalid server' do
        invalid_server = Chaussettes::Server.new
        expect(tunnel.connect(invalid_server)).to be false
      end
    end

    context 'when already connected' do
      it 'returns false' do
        allow_any_instance_of(Thread).to receive(:alive?).and_return(true)
        allow(Net::SSH).to receive(:start)

        tunnel.connect(server)
        expect(tunnel.connect(server)).to be false
      end
    end
  end

  describe '#disconnect' do
    it 'returns false when not connected' do
      expect(tunnel.disconnect).to be false
    end

    context 'when connected' do
      before do
        mock_ssh = double('ssh')
        allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
        allow(mock_ssh).to receive(:forward).and_return(double(local: nil))
        allow(mock_ssh).to receive(:loop)
        allow_any_instance_of(Thread).to receive(:alive?).and_return(true)
        allow_any_instance_of(Thread).to receive(:kill)
        allow_any_instance_of(Thread).to receive(:join)

        tunnel.connect(server)
      end

      it 'returns true on disconnect' do
        expect(tunnel.disconnect).to be true
      end

      it 'sets disconnected state' do
        tunnel.disconnect
        expect(tunnel.connected?).to be false
        expect(tunnel.current_server).to be_nil
      end
    end
  end

  describe '#connected?' do
    it 'returns false initially' do
      expect(tunnel.connected?).to be false
    end
  end
end
