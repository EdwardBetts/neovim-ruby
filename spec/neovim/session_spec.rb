require "helper"
require "securerandom"
require "fileutils"

module Neovim
  RSpec.describe Session do
    shared_context "session behavior" do
      it "supports functions with async=false" do
        expect(session.request(:vim_strwidth, "foobar")).to be(6)
      end

      it "supports functions with async=true" do
        expect(session.request(:vim_input, "jk")).to be(2)
      end

      it "raises an exception when there are errors" do
        expect {
          session.request(:vim_strwidth, "too", "many")
        }.to raise_error(/wrong number of arguments/i)
      end

      it "handles large data" do
        large_str = Array.new(1024 * 16) { SecureRandom.hex(1) }.join
        session.request(:vim_set_current_line, large_str)
        expect(session.request(:vim_get_current_line)).to eq(large_str)
      end
    end

    context "tcp" do
      let!(:nvim_port) { Support.port }
      let!(:nvim_pid) do
        pid = Process.spawn(
          {"NVIM_LISTEN_ADDRESS" => "0.0.0.0:#{nvim_port}"},
          "#{ENV.fetch("NVIM_EXECUTABLE")} --headless -n -u NONE",
          [:out, :err] => "/dev/null"
        )

        begin
          TCPSocket.open("0.0.0.0", nvim_port).close
        rescue Errno::ECONNREFUSED
          retry
        end

        pid
      end

      after do
        Process.kill(:TERM, nvim_pid)
        Process.waitpid(nvim_pid)
      end

      let(:session) do
        event_loop = EventLoop.tcp("0.0.0.0", nvim_port)
        stream = MsgpackStream.new(event_loop)
        async = AsyncSession.new(stream)
        Session.new(async)
      end

      include_context "session behavior"
    end

    context "unix" do
      let!(:socket_path) { Support.socket_path }
      let!(:nvim_pid) do
        pid = Process.spawn(
          {"NVIM_LISTEN_ADDRESS" => socket_path},
          "#{ENV.fetch("NVIM_EXECUTABLE")} --headless -n -u NONE",
          [:out, :err] => "/dev/null"
        )

        begin
          UNIXSocket.new(socket_path).close
        rescue Errno::ENOENT, Errno::ECONNREFUSED
          retry
        end

        pid
      end

      after do
        Process.kill(:TERM, nvim_pid)
        Process.waitpid(nvim_pid)
      end

      let(:session) do
        event_loop = EventLoop.unix(socket_path)
        stream = MsgpackStream.new(event_loop)
        async = AsyncSession.new(stream)
        Session.new(async)
      end

      include_context "session behavior"
    end

    context "child" do
      let(:session) do
        event_loop = EventLoop.child(["-n", "-u", "NONE"])
        stream = MsgpackStream.new(event_loop)
        async = AsyncSession.new(stream)
        Session.new(async)
      end

      include_context "session behavior"
    end
  end
end
