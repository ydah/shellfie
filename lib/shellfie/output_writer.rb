# frozen_string_literal: true

require 'fileutils'
require 'tempfile'
require 'tmpdir'

module Shellfie
  module OutputWriter
    class << self
      def write(path, extension:, io: nil)
        FileUtils.mkdir_p(output_directory(path)) unless stdout?(path)
        temp = Tempfile.new(['shellfie', ".#{extension}"], output_directory(path), binmode: true)
        temp.close
        yield temp.path

        if stdout?(path)
          return File.binread(temp.path) unless io

          File.open(temp.path, 'rb') { |source| IO.copy_stream(source, io) }
          return path
        end

        FileUtils.mv(temp.path, path)
        path
      ensure
        if temp
          temp.close unless temp.closed?
          FileUtils.rm_f(temp.path)
        end
      end

      private

      def stdout?(path)
        path == '-'
      end

      def output_directory(path)
        return Dir.tmpdir if stdout?(path)

        directory = File.dirname(path)
        directory == '.' ? Dir.pwd : directory
      end
    end
  end
end
