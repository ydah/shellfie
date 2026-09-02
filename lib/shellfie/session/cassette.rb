# frozen_string_literal: true

require "json"
require_relative "../errors"
require_relative "../output_writer"
require_relative "../session"

module Shellfie
  class Cassette
    MAX_BYTES = 32 * 1_048_576
    MAX_EVENTS = 10_000
    TOP_LEVEL_KEYS = %i[version title columns rows events captures exit_status].freeze
    EVENT_KEYS = %i[text delay visible status screen].freeze

    def self.write(path, session)
      OutputWriter.write(path, extension: "json") do |temporary_path|
        json = JSON.pretty_generate(session.to_h)
        raise ResourceLimitError, "Cassette is too large (max #{MAX_BYTES} bytes)" if json.bytesize > MAX_BYTES

        File.write(temporary_path, json)
      end
    end

    def self.read(path)
      raise ParseError, "Cassette file not found: #{path}" unless File.file?(path)
      content = File.open(path, "rb") { |file| file.read(MAX_BYTES + 1) }
      raise ParseError, "Cassette is too large (max #{MAX_BYTES} bytes)" if content.bytesize > MAX_BYTES

      raw = JSON.parse(content, symbolize_names: true)
      validate!(raw)

      Session.new(
        columns: raw[:columns],
        rows: raw[:rows],
        title: raw[:title],
        events: raw[:events] || [],
        captures: raw[:captures] || {},
        exit_status: raw[:exit_status]
      )
    rescue JSON::ParserError => e
      raise ParseError, "Invalid cassette: #{e.message}"
    end

    def self.validate!(raw)
      raise ParseError, "Cassette must be a JSON object" unless raw.is_a?(Hash)
      raise ParseError, "Unsupported cassette version" unless raw[:version] == 1
      raise ParseError, "Unknown cassette key" unless (raw.keys - TOP_LEVEL_KEYS).empty?
      raise ParseError, "Cassette title must be a string" unless raw[:title].is_a?(String)
      unless raw[:columns].is_a?(Integer) && raw[:columns].between?(1, 500) &&
             raw[:rows].is_a?(Integer) && raw[:rows].between?(1, 200)
        raise ParseError, "Invalid cassette dimensions"
      end

      events = raw[:events] || []
      raise ParseError, "Cassette events must be an array" unless events.is_a?(Array)
      raise ParseError, "Cassette has too many events" if events.size > MAX_EVENTS
      events.each_with_index do |event, index|
        unless event.is_a?(Hash) && (event.keys - EVENT_KEYS).empty? && event[:text].is_a?(String) &&
               event[:delay].is_a?(Numeric) && event[:delay].finite? && event[:delay] >= 0 &&
               [true, false].include?(event.fetch(:visible, true)) &&
               (!event.key?(:screen) || event[:screen].is_a?(Array) && event[:screen].all?(String)) &&
               (event[:status].nil? || event[:status].is_a?(Integer) && event[:status].between?(0, 255))
          raise ParseError, "Invalid cassette event at index #{index}"
        end
      end

      captures = raw[:captures] || {}
      unless captures.is_a?(Hash) && captures.all? { |name, lines| name.is_a?(Symbol) && lines.is_a?(Array) && lines.all?(String) }
        raise ParseError, "Cassette captures must map names to arrays of strings"
      end
      unless raw[:exit_status].nil? || raw[:exit_status].is_a?(Integer) && raw[:exit_status].between?(0, 255)
        raise ParseError, "Invalid cassette exit status"
      end
    end
  end
end
