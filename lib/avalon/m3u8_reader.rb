require 'open-uri'
require 'uri'

module Avalon
  class M3U8Reader

    def self.read(io)
      $stderr.puts(io.inspect)
      if io.is_a?(IO)
        self.new(io.read)
      elsif io.is_a?(String)
        if io =~ /^https?:/
          open(io) { |resp| self.new(resp, URI.parse(io)) }
        elsif io =~ /\.m3u8?$/i
          self.new(File.read(io), io)
        else
          self.new(io)
        end
      end
    end

    def initialize(playlist, base='')
      @base = base
      @playlist = { files: [] }
      tags = {}
      playlist.lines.each { |l|
        line = l.chomp
        if line =~ /^#EXTM3U/
          # ignore
        elsif line =~ /^#EXT-X-(.+):(.+)$/
          value = $2
          tag = $1.downcase.gsub(/-/,"_")
          @playlist[tag] = value
        elsif line =~ /^#EXTINF:(.+),(.*)$/
          tags[:duration] = $1.to_f
          tags[:title] = $2
        elsif line =~ /^[^#]/
          tags[:filename] = line
          @playlist[:files] << tags
          tags = {}
        end
      }
    end

    def duration
      files.inject(0.0) { |v,f| v + f[:duration] }
    end

    def at(offset)
      offset = offset.to_i
      if offset < 0
        raise RangeError, "Offset out of range"
      end
      elapsed = 0.0
      files.each { |f|
        duration = f[:duration] * 1000
        if elapsed + duration > offset
          location = @base.is_a?(URI) ? @base.merge(f[:filename]).to_s : File.expand_path(f[:filename],@base.to_s)
          return { location: location, filename: f[:filename], offset: offset - elapsed }
        end
        elapsed += duration
      }
      raise RangeError, "Offset out of range"
    end

    def method_missing(sym, *args)
      if @playlist.has_key?(sym)
        @playlist[sym]
      else
        super
      end
    end
  end
end