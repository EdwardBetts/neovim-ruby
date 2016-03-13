require "helper"

module Neovim
  RSpec.describe AsyncSession do
    shared_context "async session behavior" do
      it "receives requests" do
        stream = MsgpackStream.new(event_loop)
        async = AsyncSession.new(stream)

        server_thread = Thread.new do
          client = server.accept
          IO.select(nil, [client])
          client.write(MessagePack.pack(
            [0, 123, "func", [1, 2, 3]]
          ))
        end

        fiber = Fiber.new do
          async.run do |message|
            Fiber.yield(message)
          end
        end

        request = fiber.resume

        server_thread.join

        expect(request).to be_a(Request)
        expect(request.method_name).to eq("func")
        expect(request.arguments).to eq([1, 2, 3])
      end

      it "receives notifications" do
        stream = MsgpackStream.new(event_loop)
        async = AsyncSession.new(stream)

        server_thread = Thread.new do
          client = server.accept
          IO.select(nil, [client])
          client.write(MessagePack.pack(
            [2, "func", [1, 2, 3]]
          ))
        end

        fiber = Fiber.new do
          async.run do |message|
            Fiber.yield(message)
          end
        end

        notification = fiber.resume

        server_thread.join

        expect(notification).to be_a(Notification)
        expect(notification.method_name).to eq("func")
        expect(notification.arguments).to eq([1, 2, 3])
      end

      it "receives responses to requests" do
        stream = MsgpackStream.new(event_loop)
        async = AsyncSession.new(stream)
        messages = []

        server_thread = Thread.new do
          client = server.accept
          messages << client.readpartial(1024)

          client.write(MessagePack.pack(
            [1, 0, [0, "error"], "result"]
          ))
        end

        fiber = Fiber.new do
          async.request("func", 1, 2, 3) do |error, result|
            Fiber.yield(error, result)
          end.run
        end

        expect(fiber.resume).to eq(["error", "result"])

        server_thread.join

        expect(messages).to eq(
          [MessagePack.pack([0, 0, "func", [1, 2, 3]])]
        )
      end
    end

    context "tcp" do
      let!(:server) { TCPServer.new("0.0.0.0", 0) }
      let!(:event_loop) { EventLoop.tcp("0.0.0.0", server.addr[1]) }

      include_context "async session behavior"
    end

    context "unix" do
      let!(:server) { UNIXServer.new(Support.socket_path) }
      let!(:event_loop) { EventLoop.unix(Support.socket_path) }

      include_context "async session behavior"
    end
  end
end
