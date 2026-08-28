# frozen_string_literal: true

require "json"
require_relative "errors"
require_relative "output_writer"
require_relative "session"

module Shellfie
  class Cassette
    MAX_BYTES = 10 * 1_048_576

    def self.write(path, session)
      OutputWriter.write(path, extension: "json") { |temporary_path| File.write(temporary_path, JSON.pretty_generate(session.to_h)) }
    end

    def self.read(path)
      raise ParseError, "Cassette file not found: #{path}" unless File.file?(path)
      raise ParseError, "Cassette is too large (max #{MAX_BYTES} bytes)" if File.size(path) > MAX_BYTES

      raw = JSON.parse(File.read(path), symbolize_names: true)
      raise ParseError, "Cassette must be a JSON object" unless raw.is_a?(Hash)
      raise ParseError, "Unsupported cassette version" unless raw[:version] == 1

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
  end
end
