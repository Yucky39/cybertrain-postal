require "cybertrain/postal/errors"
require "cybertrain/postal/address"
require "cybertrain/postal/message"
require "cybertrain/postal/result"
require "cybertrain/postal/delivery"
require "cybertrain/postal/retry"

module Cybertrain
  module Postal
    # A message read back from the spool: already rendered, so it is sent
    # exactly as it was accepted (Bcc recipients are in the envelope only).
    class RawMessage < Message
      def initialize(sender, recipients, data)
        super(Address.build(sender, ""))
        @data = data
        recipients.each { |addr| add_to(Address.build(addr, "")) }
      end

      def render
        @data
      end
    end

    # One spooled message: the envelope, the retry state and the rendered data.
    # File format: "Key: value" lines, a blank line, then the data verbatim.
    class SpoolItem
      attr_reader :id, :sender, :recipients, :attempts, :next_at, :data, :created, :expires_at
      attr_accessor :last_error

      # expires_at is Unix seconds, 0 for none.
      def initialize(id, sender, recipients, attempts, next_at, created, expires_at, data)
        @id = id
        @expires_at = expires_at
        @sender = sender
        @recipients = recipients
        @attempts = attempts
        @next_at = next_at
        @created = created
        @data = data
        @valid = true
        @last_error = ""
      end

      # A placeholder for "nothing there" (a lost claim, a damaged file).
      def self.none(id)
        item = SpoolItem.new(id, "", [""].clear, 0, 0, 0, 0, "")
        item.invalidate
        item
      end

      def invalidate
        @valid = false
        nil
      end

      def valid?
        @valid
      end

      def reschedule(attempts, next_at, error)
        item = SpoolItem.new(@id, @sender, @recipients, attempts, next_at, @created, @expires_at, @data)
        item.last_error = error
        item
      end

      def to_text
        head = +""
        head << "From: " << @sender << "\n"
        @recipients.each { |r| head << "Rcpt: " << r << "\n" }
        head << "Attempts: " << @attempts.to_s << "\n"
        head << "Next-At: " << @next_at.to_s << "\n"
        head << "Created: " << @created.to_s << "\n"
        head << "Expires-At: " << @expires_at.to_s << "\n"
        head << "Last-Error: " << @last_error << "\n"
        head << "\n"
        head << @data
        head
      end

      def self.parse(id, text)
        cut = text.byteindex("\n\n")
        return SpoolItem.none(id) if cut.nil?
        head = text.byteslice(0, cut)
        data = text.byteslice(cut + 2, text.bytesize - cut - 2)
        sender = ""
        recipients = [""]
        recipients.clear
        attempts = 0
        next_at = 0
        created = 0
        expires_at = 0
        last_error = ""
        head.split("\n").each do |line|
          colon = line.index(": ")
          next if colon.nil?
          key = line[0, colon]
          value = line[colon + 2, line.length - colon - 2]
          if key == "From"
            sender = value
          elsif key == "Rcpt"
            recipients << value
          elsif key == "Attempts"
            attempts = value.to_i
          elsif key == "Next-At"
            next_at = value.to_i
          elsif key == "Created"
            created = value.to_i
          elsif key == "Expires-At"
            expires_at = value.to_i
          elsif key == "Last-Error"
            last_error = value
          end
        end
        return SpoolItem.none(id) if sender.empty? || recipients.empty?
        item = SpoolItem.new(id, sender, recipients, attempts, next_at, created, expires_at, data)
        item.last_error = last_error
        item
      end

      def to_message
        RawMessage.new(@sender, @recipients, @data)
      end
    end

    # A directory spool in the style of Maildir. One file per message; a state
    # change is a rename, so a crash never leaves a half-written message:
    #   tmp/     being written          new/     waiting (or waiting to retry)
    #   active/  claimed by a worker    failed/  gave up (kept for inspection)
    class Spool
      # Directories this creates are owner-only (0700) and every message file
      # is 0600: a spooled message can hold a secret such as a reset link. A
      # directory that already exists is left as it is, so the web application
      # and the worker must run as the same user (or the operator prepares the
      # directory and its permissions).
      def initialize(dir)
        @dir = dir
        make_private_dir(dir)
        ["tmp", "new", "active", "failed"].each { |sub| make_private_dir(dir + "/" + sub) }
      end

      # Stores the rendered message; the id is returned. now is Unix seconds.
      def enqueue(message, now)
        data = message.render
        id = now.to_s + "-" + Message.fresh_token
        expires_at = message.valid_for > 0 ? now + message.valid_for : 0
        item = SpoolItem.new(id, message.from.addr, message.recipient_addrs, 0, now, now, expires_at, data)
        store(item, "new")
        id
      end

      # Ids waiting and due at `now`, oldest first.
      def due_ids(now)
        ids = [""]
        ids.clear
        Dir.children(@dir + "/new").sort.each do |name|
          next unless name.end_with?(".mail")
          id = name.byteslice(0, name.bytesize - 5)
          item = read_item(id, "new")
          next unless item.valid?
          # an expired message is due at once, so the runner can retire it
          ids << id if item.next_at <= now || (item.expires_at > 0 && item.expires_at <= now)
        end
        ids
      end

      # Takes the message for this worker. The item is not valid? when another
      # worker took it first or the file is damaged.
      def claim(id)
        from = path_of("new", id)
        to = path_of("active", id)
        begin
          File.rename(from, to)
        rescue SystemCallError
          return SpoolItem.none(id)
        end
        read_item(id, "active")
      end

      def complete(item)
        File.delete(path_of("active", item.id))
        nil
      end

      def reschedule(item, attempts, next_at, error)
        later = item.reschedule(attempts, next_at, error)
        store(later, "new")
        File.delete(path_of("active", item.id))
        nil
      end

      def fail(item, attempts, error)
        failed = item.reschedule(attempts, item.next_at, error)
        store(failed, "failed")
        File.delete(path_of("active", item.id))
        nil
      end

      # Puts claimed messages that nobody finished (a crashed worker) back in
      # new/ once they are older than max_age seconds. Returns how many.
      def recover_stale(now, max_age)
        moved = 0
        Dir.children(@dir + "/active").each do |name|
          next unless name.end_with?(".mail")
          path = @dir + "/active/" + name
          next if now - File.mtime(path).to_i < max_age
          begin
            File.rename(path, @dir + "/new/" + name)
            moved += 1
          rescue SystemCallError
            # finished or taken by someone else meanwhile
          end
        end
        moved
      end

      # Deletes failed messages older than max_age seconds (by file time).
      # Failed messages are kept for inspection but can hold secrets: call this
      # now and then. Returns how many were removed.
      def purge_failed(now, max_age)
        removed = 0
        Dir.children(@dir + "/failed").each do |name|
          next unless name.end_with?(".mail")
          path = @dir + "/failed/" + name
          next if now - File.mtime(path).to_i < max_age
          begin
            File.delete(path)
            removed += 1
          rescue SystemCallError
            # already gone
          end
        end
        removed
      end

      def count(state)
        n = 0
        Dir.children(@dir + "/" + state).each { |name| n += 1 if name.end_with?(".mail") }
        n
      end

      def peek(state, id)
        read_item(id, state)
      end

      private

      # Spinel 2026.09.12 ignores the mode argument of Dir.mkdir (the directory
      # comes out 0755), so the mode is set explicitly after creating it.
      def make_private_dir(path)
        return if Dir.exist?(path)
        Dir.mkdir(path)
        File.chmod(0700, path)
        nil
      end

      def path_of(state, id)
        @dir + "/" + state + "/" + id + ".mail"
      end

      def read_item(id, state)
        begin
          SpoolItem.parse(id, File.binread(path_of(state, id)))
        rescue SystemCallError
          SpoolItem.none(id)
        end
      end

      def store(item, state)
        tmp = @dir + "/tmp/" + item.id + ".mail"
        File.binwrite(tmp, item.to_text)
        File.chmod(0600, tmp)
        File.rename(tmp, path_of(state, item.id))
        nil
      end
    end

    # Delivery that only queues: deliver answers 250 "queued <id>" as soon as
    # the message is safely on disk.
    class QueueDelivery < Delivery
      def initialize(spool)
        @spool = spool
      end

      def perform(message)
        id = @spool.enqueue(message, Time.now.to_i)
        Result.new(true, 250, "queued " + id, message.recipient_addrs, [""].clear)
      end
    end

    # What one SpoolRunner pass did.
    class RunReport
      attr_reader :delivered, :deferred, :failed

      def initialize(delivered, deferred, failed)
        @delivered = delivered
        @deferred = deferred
        @failed = failed
      end
    end

    # Works through the due messages: one delivery attempt each. Success
    # removes the message; a temporary failure schedules the next attempt with
    # the policy's backoff (the message moves to failed/ after max_attempts);
    # a permanent failure moves it to failed/ at once.
    class SpoolRunner
      def initialize(spool, factory, policy)
        @spool = spool
        @factory = factory
        @policy = policy
      end

      def run_once(now)
        delivered = 0
        deferred = 0
        failed = 0
        @spool.due_ids(now).each do |id|
          item = @spool.claim(id)
          next unless item.valid?
          outcome = process(item, now)
          if outcome == 1
            delivered += 1
          elsif outcome == 2
            deferred += 1
          else
            failed += 1
          end
        end
        RunReport.new(delivered, deferred, failed)
      end

      private

      # 1 delivered, 2 deferred, 3 failed
      def process(item, now)
        if item.expires_at > 0 && now >= item.expires_at
          @spool.fail(item, item.attempts, "expired before it could be sent")
          return 3
        end
        result = attempt(item)
        if result.ok?
          @spool.complete(item)
          return 1
        end
        attempts = item.attempts + 1
        error = result.code.to_s + " " + result.text
        if @policy.retry?(result) && attempts < @policy.max_attempts
          later = now + @policy.delay_after(attempts).ceil
          if item.expires_at > 0 && later >= item.expires_at
            @spool.fail(item, attempts, error + " (expired before the next attempt)")
            return 3
          end
          @spool.reschedule(item, attempts, later, error)
          return 2
        end
        @spool.fail(item, attempts, error)
        3
      end

      def attempt(item)
        begin
          @factory.new_delivery.deliver(item.to_message)
        rescue ConnectionLost
          Result.new(false, 421, "connection lost", [""].clear, [""].clear)
        rescue PostalError
          Result.new(false, 550, "not deliverable", [""].clear, [""].clear)
        end
      end
    end
  end
end
