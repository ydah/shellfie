# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "shellfie/output_writer"

RSpec.describe Shellfie::OutputWriter do
  it "keeps an existing output intact when generation fails" do
    Dir.mktmpdir("shellfie-output-writer-spec") do |dir|
      output = File.join(dir, "output.txt")
      File.write(output, "original")

      expect do
        described_class.write(output, extension: "txt") do |temporary_path|
          File.write(temporary_path, "partial")
          raise "injected failure"
        end
      end.to raise_error("injected failure")

      expect(File.read(output)).to eq("original")
      expect(Dir.children(dir)).to eq(["output.txt"])
    end
  end
end
