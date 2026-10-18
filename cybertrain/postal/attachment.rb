require "cybertrain/postal/errors"
require "cybertrain/postal/mime"

module Cybertrain
  module Postal
    # A file attached to a Message. content_id is empty for an ordinary
    # attachment; a non-empty one makes it an inline part that the HTML body
    # can reference as <img src="cid:...">.
    class Attachment
      MAX_FILENAME = 255

      attr_reader :filename, :content_type, :data, :content_id

      def initialize(filename, content_type, data, content_id)
        @filename = filename
        @content_type = content_type
        @data = data
        @content_id = content_id
      end

      def self.build(filename, content_type, data, content_id = "")
        Attachment.check_filename(filename)
        Attachment.check_content_type(content_type)
        Attachment.check_content_id(content_id)
        Attachment.new(filename, content_type, data, content_id)
      end

      def inline?
        @content_id.bytesize > 0
      end

      # Control characters and path separators are refused: a name such as
      # "a/../b" or one with a newline would mislead the recipient's client.
      def self.check_filename(name)
        n = name.bytesize
        raise InvalidMessage, "attachment filename is empty or too long" if n == 0 || n > MAX_FILENAME
        raw = name.bytes
        i = 0
        while i < n
          b = raw[i]
          if b < 32 || b == 127 || b == 47 || b == 92
            raise InvalidMessage, "attachment filename has a control character or path separator"
          end
          i += 1
        end
        name
      end

      # type/subtype made of letters, digits and . + - _ only.
      def self.check_content_type(type)
        raw = type.bytes
        slash = -1
        i = 0
        while i < raw.length
          b = raw[i]
          if b == 47
            raise InvalidMessage, "attachment content type has two slashes" if slash >= 0
            slash = i
          else
            ok = (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) ||
                 b == 46 || b == 43 || b == 45 || b == 95
            raise InvalidMessage, "attachment content type has a forbidden character" unless ok
          end
          i += 1
        end
        raise InvalidMessage, "attachment content type needs type/subtype" if slash < 1 || slash == raw.length - 1
        type
      end

      # Empty, or a token without whitespace, angle brackets or controls.
      def self.check_content_id(cid)
        return cid if cid.bytesize == 0
        raw = cid.bytes
        i = 0
        while i < raw.length
          b = raw[i]
          if b <= 32 || b >= 127 || b == 60 || b == 62
            raise InvalidMessage, "attachment content id has a forbidden character"
          end
          i += 1
        end
        cid
      end
    end
  end
end
