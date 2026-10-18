# A minimal test harness, so the library does not depend on the framework
# just to run its tests. Same shape as cybertrain/test: register cases with
# `test "name" do ... end`, assert, end the file with PostalTest.run!.
# Output is deterministic; `spin test` diffs it with test/<name>.rb.expected.
# State lives in one object held by a constant, not in class variables: under
# Spinel a class-variable array can turn into another array after a garbage
# collection (see ../cybertrain-kaisatsu/docs/m2-notes.md).
module PostalTest
  class Failed < StandardError
  end

  class Registry
    attr_reader :names, :blocks
    attr_accessor :failures, :assertions

    def initialize
      @names = [""]
      @blocks = [-> { nil }]
      @names.clear
      @blocks.clear
      @failures = 0
      @assertions = 0
    end
  end

  STATE = Registry.new

  def self.register(name, block)
    STATE.names << name
    STATE.blocks << block
  end

  def self.count
    STATE.assertions = STATE.assertions + 1
  end

  def self.run!
    i = 0
    while i < STATE.names.length
      name = STATE.names[i]
      begin
        STATE.blocks[i].call
        puts "ok   #{name}"
      rescue Failed => e
        STATE.failures = STATE.failures + 1
        puts "FAIL #{name}: #{e.message}"
      rescue StandardError => e
        STATE.failures = STATE.failures + 1
        puts "ERR  #{name}: #{e.class.name}"
      end
      i += 1
    end
    puts "#{STATE.names.length} tests, #{STATE.assertions} assertions, #{STATE.failures} failures"
    exit(1) if STATE.failures > 0
  end
end

def test(name, &block)
  PostalTest.register(name, block)
end

def assert(condition, message = "expected condition to be truthy")
  PostalTest.count
  raise PostalTest::Failed, message unless condition
end

def assert_equal(expected, actual)
  PostalTest.count
  raise PostalTest::Failed, "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
end
