require "helper"
require "socket"

module Neovim
  class Session
    RSpec.describe EventLoop do
      shared_context "socket behavior" do
        it "sends and receives data" do
          request = nil

          server_thread = Thread.new do
            client = server.accept
            request = client.readpartial(1024)

            client.write("res")
            client.close
            server.close
          end

          response = nil
          event_loop.write("req").run do |msg|
            response = msg
            event_loop.stop
          end

          server_thread.join
          event_loop.shutdown
          expect(request).to eq("req")
          expect(response).to eq("res")
        end
      end

      context "tcp" do
        let!(:server) { TCPServer.new("0.0.0.0", 0) }
        let!(:event_loop) { EventLoop.tcp("0.0.0.0", server.addr[1]) }

        include_context "socket behavior"
      end

      context "unix" do
        let!(:server) { UNIXServer.new(Support.socket_path) }
        let!(:event_loop) { EventLoop.unix(Support.socket_path) }

        include_context "socket behavior"
      end

      context "stdio" do
        it "sends and receives data" do
          old_stdout = STDOUT.dup
          old_stdin = STDIN.dup

          begin
            srv_stdout, cl_stdout = IO.pipe
            cl_stdin, srv_stdin = IO.pipe

            STDOUT.reopen(cl_stdout)
            STDIN.reopen(cl_stdin)

            event_loop = EventLoop.stdio
            request = nil

            server_thread = Thread.new do
              request = srv_stdout.readpartial(1024)
              srv_stdin.write("res")
            end

            response = nil
            event_loop.write("req").run do |msg|
              response = msg
              event_loop.stop
            end

            server_thread.join
            expect(request).to eq("req")
            expect(response).to eq("res")
          ensure
            STDOUT.reopen(old_stdout)
            STDIN.reopen(old_stdin)
          end
        end
      end

      context "child" do
        it "sends and receives data" do
          event_loop = EventLoop.child(Support.child_argv)
          input = MessagePack.pack([0, 0, :nvim_strwidth, ["hi"]])

          response = nil
          event_loop.write(input).run do |msg|
            response = msg
            event_loop.shutdown
          end

          expect(response).to eq(MessagePack.pack([1, 0, nil, 2]))
        end
      end

      describe "#run" do
        it "handles EOF" do
          rd, wr = IO.pipe
          wr.close
          event_loop = EventLoop.new(rd, wr)
          expect(event_loop).to receive(:info).with(/EOFError/)

          event_loop.run
        end

        it "handles other errors" do
          rd, wr = IO.pipe
          rd.close
          event_loop = EventLoop.new(rd, wr)
          expect(event_loop).to receive(:fatal).with(/IOError/)

          event_loop.run
        end
      end

      describe "#write" do
        it "retries when writes would block" do
          rd, wr = IO.pipe
          event_loop = EventLoop.new(rd, wr)
          err_class = Class.new(RuntimeError) { include IO::WaitWritable }

          expect(wr).to receive(:write_nonblock).and_raise(err_class)
          expect(wr).to receive(:write_nonblock).and_call_original

          event_loop.write("a")
          expect(rd.readpartial(1)).to eq("a")
        end
      end

      describe "#shutdown" do
        it "closes IO handles" do
          rd, wr = IO.pipe
          EventLoop.new(rd, wr).shutdown

          expect(rd).to be_closed
          expect(wr).to be_closed
        end

        it "kills spawned processes" do
          io = IO.popen("cat", "rb+")
          pid = io.pid
          expect(pid).to respond_to(:to_int)

          EventLoop.new(io).shutdown
          expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
        end
      end
    end
  end
end
