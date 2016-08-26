require "helper"

RSpec.describe "ruby_provider" do
  let!(:nvim) do
    Neovim.attach_child(["nvim", "-i", "NONE", "-u", "NONE", "-n"])
  end

  around do |spec|
    provider_path = Support.file_path("provider.rb")
    File.write(provider_path, "require 'neovim/ruby_provider'")
    host_exe = File.expand_path("../../../bin/neovim-ruby-host", __FILE__)
    nvim.current.buffer.lines = ["line1", "line2"]
    nvim.command("let host = rpcstart('#{host_exe}', ['#{provider_path}'])")

    begin
      spec.run
    ensure
      nvim.session.shutdown
    end
  end

  describe "ruby_execute" do
    it "runs ruby directly" do
      ruby = "VIM.command('let myvar = [1, 2]')".inspect
      nvim.eval("rpcrequest(host, 'ruby_execute', #{ruby})")
      expect(nvim.eval("g:myvar")).to eq([1, 2])
    end

    it "exposes the $curwin variable" do
      nvim.command("vsplit")

      expect {
        ruby = "$curwin.width -= 1".inspect
        nvim.eval("rpcrequest(host, 'ruby_execute', #{ruby})")
      }.to change { nvim.current.window.width }.by(-1)
    end

    it "exposes the $curbuf variable" do
      expect {
        ruby = "$curbuf.lines = ['line']".inspect
        nvim.eval("rpcrequest(host, 'ruby_execute', #{ruby})")
      }.to change { nvim.current.buffer.lines.to_a }.to(["line"])
    end

    it "persists state between requests" do
      nvim.eval("rpcrequest(host, 'ruby_execute', 'def foo; VIM.command(\"let g:called = 1\"); end')")
      expect { nvim.get_var("called") }.to raise_error(/key not found/i)

      nvim.eval("rpcrequest(host, 'ruby_execute', 'foo')")
      expect(nvim.get_var("called")).to be(1)
    end

    it "persists instance state in globals" do
      nvim.eval("rpcrequest(host, 'ruby_execute', '$curbuf.instance_variable_set(:@foo, 123)')")
      nvim.eval("rpcrequest(host, 'ruby_execute', 'VIM.command(\"let g:foo = \#{$curbuf.instance_variable_get(:@foo)}\")')")

      expect(nvim.get_var("foo")).to be(123)

      nvim.eval("rpcrequest(host, 'ruby_execute', '$curwin.instance_variable_set(:@bar, 456)')")
      nvim.eval("rpcrequest(host, 'ruby_execute', 'VIM.command(\"let g:bar = \#{$curwin.instance_variable_get(:@bar)}\")')")

      expect(nvim.get_var("bar")).to be(456)
    end
  end

  describe "ruby_execute_file" do
    let(:script_path) { Support.file_path("script.rb") }

    it "runs ruby from a file" do
      File.write(script_path, "VIM.command('let myvar = [1, 2]')")
      nvim.eval("rpcrequest(host, 'ruby_execute_file', '#{script_path}')")
      expect(nvim.eval("g:myvar")).to eq([1, 2])
    end

    it "exposes the $curwin variable" do
      File.write(script_path, "$curwin.width -= 1")
      nvim.command("vsplit")

      expect {
        nvim.eval("rpcrequest(host, 'ruby_execute_file', '#{script_path}')")
      }.to change { nvim.current.window.width }.by(-1)
    end

    it "exposes the $curbuf variable" do
      File.write(script_path, "$curbuf.lines = ['line']")

      expect {
        nvim.eval("rpcrequest(host, 'ruby_execute_file', '#{script_path}')")
      }.to change { nvim.current.buffer.lines.to_a }.to(["line"])
    end

    it "persists state between requests" do
      File.write(script_path, "def foo; VIM.command(\"let g:called = 1\"); end")
      nvim.eval("rpcrequest(host, 'ruby_execute_file', '#{script_path}')")
      expect { nvim.get_var("called") }.to raise_error(/key not found/i)

      nvim.eval("rpcrequest(host, 'ruby_execute', 'foo')")
      expect(nvim.get_var("called")).to be(1)
    end

    it "can run the same file multiple times" do
      nvim.set_var("called", 0)
      File.write(script_path, "VIM.command(\"let g:called += 1\")")

      nvim.eval("rpcrequest(host, 'ruby_execute_file', '#{script_path}')")
      expect(nvim.get_var("called")).to be(1)

      nvim.eval("rpcrequest(host, 'ruby_execute_file', '#{script_path}')")
      expect(nvim.get_var("called")).to be(2)
    end

    it "persists instance state in globals" do
      File.write(script_path, <<-RUBY)
        def $curbuf.foo
          @foo ||= 0
          @foo += 1
        end

        VIM.command("let g:foo = \#{$curbuf.foo}")
      RUBY

      nvim.eval("rpcrequest(host, 'ruby_execute_file', '#{script_path}')")
      expect(nvim.get_var("foo")).to be(1)

      nvim.eval("rpcrequest(host, 'ruby_execute_file', '#{script_path}')")
      expect(nvim.get_var("foo")).to be(2)

      File.write(script_path, <<-RUBY)
        def $curwin.bar
          @bar ||= 0
          @bar += 1
        end

        VIM.command("let g:bar = \#{$curwin.bar}")
      RUBY

      nvim.eval("rpcrequest(host, 'ruby_execute_file', '#{script_path}')")
      expect(nvim.get_var("bar")).to be(1)

      nvim.eval("rpcrequest(host, 'ruby_execute_file', '#{script_path}')")
      expect(nvim.get_var("bar")).to be(2)
    end
  end

  describe "ruby_do_range" do
    it "mutates lines via the $_ variable" do
      nvim.current.buffer.lines = ["a", "b", "c", "d"]

      expect {
        nvim.eval("rpcrequest(host, 'ruby_do_range', 2, 3, '$_.upcase!; 42')")
      }.to change { nvim.current.buffer.lines.to_a }.to(["a", "B", "C", "d"])
    end

    it "handles large amounts of lines" do
      xs = Array.new(6000, "x")
      ys = Array.new(6000, "y")
      nvim.current.buffer.lines = xs

      expect {
        nvim.eval("rpcrequest(host, 'ruby_do_range', 1, 6000, '$_.succ!')")
      }.to change { nvim.current.buffer.lines.to_a }.to(ys)
    end
  end
end
