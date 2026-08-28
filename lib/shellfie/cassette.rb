# frozen_string_literal: true

require "json"
require_relative "errors"
require_relative "session"

module Shellfie
  class Cassette
    def self.write(path, session)
      File.write(path, JSON.pretty_generate(session.to_h))
      path
    end

    def self.read(path)
      raw = JSON.parse(File.read(path), symbolize_names: true)
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
