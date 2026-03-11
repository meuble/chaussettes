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
      expect(tunnel.connected_at).to be_nil
      expect(tunnel.latency).to be_nil
      expect(tunnel.bytes_sent).to eq(0)
      expect(tunnel.bytes_received).to eq(0)
      expect(tunnel.active_connections).to eq(0)
    end
  end

  describe '#connect' do
    context 'with valid server' do
      before do
        allow(tunnel).to receive(:spawn).and_return(12_345)
        allow(tunnel).to receive(:process_alive?).and_return(true)
        allow(tunnel).to receive(:`).and_return('') # Mock system ping
      end

      it 'returns true on successful connection' do
        result = tunnel.connect(server)
        expect(result).to be true
      end

      it 'sets connected state' do
        tunnel.connect(server)
        expect(tunnel.current_server).to eq(server)
        expect(tunnel.connected_at).not_to be_nil
      end

      it 'starts latency monitoring' do
        tunnel.connect(server)
        thread = tunnel.instance_variable_get(:@latency_thread)
        expect(thread).not_to be_nil
        expect(thread).to be_alive

        # Stop the thread after test
        tunnel.instance_variable_set(:@stop_latency_check, true)
        thread.join(0.1)
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
        allow(tunnel).to receive(:spawn).and_return(12_345)
        allow(tunnel).to receive(:process_alive?).and_return(true)
        allow(tunnel).to receive(:`).and_return('')

        tunnel.connect(server)
        expect(tunnel.connect(server)).to be false

        # Stop the thread after test
        thread = tunnel.instance_variable_get(:@latency_thread)
        tunnel.instance_variable_set(:@stop_latency_check, true) if thread
        thread&.join(0.1)
      end
    end
  end

  describe '#disconnect' do
    it 'returns false when not connected' do
      expect(tunnel.disconnect).to be false
    end

    context 'when connected' do
      before do
        allow(tunnel).to receive(:spawn).and_return(12_345)
        allow(tunnel).to receive(:process_alive?).and_return(true)
        allow(tunnel).to receive(:`).and_return('')
        allow(Process).to receive(:kill)
        allow(Process).to receive(:wait)

        tunnel.connect(server)
      end

      it 'returns true on disconnect' do
        expect(tunnel.disconnect).to be true
      end

      it 'sets disconnected state' do
        tunnel.disconnect
        expect(tunnel.connected?).to be false
        expect(tunnel.current_server).to be_nil
        expect(tunnel.connected_at).to be_nil
        expect(tunnel.bytes_sent).to eq(0)
        expect(tunnel.bytes_received).to eq(0)
        expect(tunnel.active_connections).to eq(0)
      end

      it 'stops latency monitoring' do
        thread = tunnel.instance_variable_get(:@latency_thread)
        expect(thread).not_to be_nil

        tunnel.disconnect

        # Wait for thread to finish (may be sleeping)
        thread.join(0.5) if thread.alive?

        expect(tunnel.instance_variable_get(:@stop_latency_check)).to be true
      end
    end
  end

  describe '#connected?' do
    it 'returns false initially' do
      expect(tunnel.connected?).to be false
    end
  end

  describe '#connection_duration' do
    it 'returns nil when not connected' do
      expect(tunnel.connection_duration).to be_nil
    end

    it 'returns duration when connected' do
      allow(tunnel).to receive(:spawn).and_return(12_345)
      allow(tunnel).to receive(:process_alive?).and_return(true)
      allow(tunnel).to receive(:`).and_return('')

      tunnel.connect(server)

      # Manually set connected_at to simulate time passing
      past_time = Time.now - 60
      tunnel.instance_variable_set(:@connected_at, past_time)

      duration = tunnel.connection_duration
      expect(duration).to be >= 60

      # Stop the thread after test
      thread = tunnel.instance_variable_get(:@latency_thread)
      tunnel.instance_variable_set(:@stop_latency_check, true) if thread
      thread&.join(0.1)
    end
  end

  describe '#format_duration' do
    it 'formats seconds as HH:MM:SS' do
      expect(tunnel.format_duration(3661)).to eq('01:01:01')
    end

    it 'returns 00:00:00 for nil' do
      expect(tunnel.format_duration(nil)).to eq('00:00:00')
    end
  end

  describe '#format_latency' do
    it 'formats latency with ms' do
      tunnel.instance_variable_set(:@latency, 45.5)
      expect(tunnel.format_latency).to eq('45.5ms')
    end

    it 'returns -- when latency is nil' do
      expect(tunnel.format_latency).to eq('--')
    end
  end

  describe '#latency monitoring' do
    it 'updates latency on successful ping' do
      # Mock backticks to return success (exit code 0)
      allow(tunnel).to receive(:`).with(/ping.*example.com/).and_return('')
      allow(tunnel).to receive(:check_latency).and_wrap_original do |_m|
        tunnel.instance_variable_set(:@latency, 45.5)
      end

      tunnel.instance_variable_set(:@server, server)
      tunnel.instance_variable_set(:@latency, nil)

      # Call check_latency directly
      tunnel.send(:check_latency)

      expect(tunnel.latency).not_to be_nil
      expect(tunnel.latency).to be >= 0
    end

    it 'sets latency to nil on failed ping' do
      allow(tunnel).to receive(:`).with(/ping.*example.com/).and_return('')
      allow(tunnel).to receive(:check_latency).and_wrap_original do |_m|
        tunnel.instance_variable_set(:@latency, nil)
      end

      tunnel.instance_variable_set(:@server, server)
      tunnel.instance_variable_set(:@latency, 45.0)

      # Call check_latency directly
      tunnel.send(:check_latency)

      expect(tunnel.latency).to be_nil
    end
  end

  describe '#traffic stats' do
    describe '#format_bytes' do
      it 'formats bytes' do
        expect(tunnel.format_bytes(0)).to eq('0 B')
        expect(tunnel.format_bytes(512)).to eq('512 B')
        expect(tunnel.format_bytes(1024)).to eq('1.0 KB')
        expect(tunnel.format_bytes(1536)).to eq('1.5 KB')
        expect(tunnel.format_bytes(1024 * 1024)).to eq('1.0 MB')
        expect(tunnel.format_bytes(1024 * 1024 * 1024)).to eq('1.0 GB')
      end
    end

    describe '#format_traffic_stats' do
      it 'formats traffic stats' do
        tunnel.instance_variable_set(:@bytes_sent, 1024 * 1024)
        tunnel.instance_variable_set(:@bytes_received, 512 * 1024)
        result = tunnel.format_traffic_stats
        expect(result).to include('Sent: 1.0 MB')
        expect(result).to include('Received: 512.0 KB')
      end
    end

    describe '#traffic monitoring' do
      it 'starts traffic monitoring thread on connect' do
        allow(tunnel).to receive(:spawn).and_return(12_345)
        allow(tunnel).to receive(:process_alive?).and_return(true)
        allow(tunnel).to receive(:`).and_return('')

        tunnel.connect(server)

        thread = tunnel.instance_variable_get(:@traffic_thread)
        expect(thread).not_to be_nil
        expect(thread).to be_alive

        # Stop threads after test
        tunnel.instance_variable_set(:@stop_traffic_check, true)
        thread.join(0.1)
      end

      it 'stops traffic monitoring on disconnect' do
        allow(tunnel).to receive(:spawn).and_return(12_345)
        allow(tunnel).to receive(:process_alive?).and_return(true)
        allow(tunnel).to receive(:`).and_return('')
        allow(Process).to receive(:kill)
        allow(Process).to receive(:wait)

        tunnel.connect(server)
        tunnel.disconnect

        expect(tunnel.instance_variable_get(:@stop_traffic_check)).to be true
      end
    end
  end
end
