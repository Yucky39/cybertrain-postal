# A minimal test harness, so the library does not depend on the framework
# just to run its tests. Same shape as cybertrain/test: register cases with
# `test "name" do ... end`, assert, end the file with PostalTest.run!.
# Output is deterministic; `spin test` diffs it with test/<name>.rb.expected.
module PostalTest
  class Failed < StandardError
  end

  @@names = [""]
  @@blocks = [-> { nil }]
  @@names.clear
  @@blocks.clear
  @@failures = 0
  @@assertions = 0

  def self.register(name, block)
    @@names << name
    @@blocks << block
  end

  def self.count
    @@assertions += 1
  end

  def self.run!
    i = 0
    while i < @@names.length
      name = @@names[i]
      begin
        @@blocks[i].call
        puts "ok   #{name}"
      rescue Failed => e
        @@failures += 1
        puts "FAIL #{name}: #{e.message}"
      rescue StandardError => e
        @@failures += 1
        puts "ERR  #{name}: #{e.class.name}"
      end
      i += 1
    end
    puts "#{@@names.length} tests, #{@@assertions} assertions, #{@@failures} failures"
    exit(1) if @@failures > 0
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
