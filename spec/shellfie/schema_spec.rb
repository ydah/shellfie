# frozen_string_literal: true

require "json"
require "json_schemer"
require "yaml"

RSpec.describe "configuration schemas" do
  let(:v1) { JSONSchemer.schema(JSON.parse(File.read("schema/shellfie-v1.schema.json"))) }
  let(:v2) { JSONSchemer.schema(JSON.parse(File.read("schema/shellfie-v2.schema.json"))) }

  it "uses valid schemas that accept the shipped examples" do
    expect(v1.valid_schema?).to be true
    expect(v2.valid_schema?).to be true

    (Dir["examples/*.yml"] - ["examples/session.yml"]).each do |path|
      expect(v1.valid?(YAML.safe_load(File.read(path), aliases: true))).to be(true), path
    end
    expect(v2.valid?(YAML.safe_load(File.read("examples/session.yml"), aliases: true))).to be true
  end

  it "rejects structures rejected by runtime validation" do
    expect(v1.valid?({ "colors" => { "typo" => "#fff" }, "lines" => [{ "output" => "x" }] })).to be false
    expect(v1.valid?({ "window" => { "width" => 1 }, "lines" => [{ "output" => "x" }] })).to be false
    expect(v1.valid?({ "window" => { "width" => 120, "padding" => 100 }, "lines" => [{ "output" => "x" }] })).to be false
    expect(v1.valid?({ "window" => { "width" => 200, "padding" => 41 }, "lines" => [{ "output" => "x" }] })).to be false
    expect(v1.valid?({ "animation" => { "final_delay" => 86_400_001 }, "lines" => [{ "output" => "x" }] })).to be false
    expect(v1.valid?({ "frames" => [{ "output" => "x", "delay" => 86_400_001 }] })).to be false
    expect(v1.valid?({ "frames" => [{ "prompt" => "$ ", "delay" => 1 }] })).to be false
    expect(v2.valid?({ "version" => 2, "steps" => [{ "run" => "x", "sleep" => "1s", "typo" => true }] })).to be false
    expect(v2.valid?({ "version" => 2, "steps" => [], "render" => { "window" => { "width" => "nope" } } })).to be false
    expect(v2.valid?({ "version" => 2, "steps" => [], "render" => { "window" => { "width" => 120, "padding" => 100 } } })).to be false
    expect(v2.valid?({ "version" => 2, "steps" => [], "render" => { "window" => { "width" => 200, "padding" => 41 } } })).to be false
    expect(v2.valid?({ "version" => 2, "steps" => [], "render" => { "animation" => { "final_delay" => 86_400_001 } } })).to be false
    expect(v2.valid?({ "version" => 2, "steps" => [{ "sleep" => "86401s" }] })).to be false
    expect(v2.valid?({ "version" => 2, "steps" => [{ "type" => "x", "speed" => "1000.1cps" }] })).to be false
    expect(v2.valid?({ "version" => 2, "steps" => [{ "wait" => "x" * 513 }] })).to be false
  end

  it "accepts runtime boundary values" do
    expect(v1.valid?({
                       "window" => { "width" => 120, "padding" => 40 },
                       "animation" => { "final_delay" => 86_400_000 },
                       "frames" => [{ "output" => "x", "delay" => 86_400_000 }]
                     })).to be true
    expect(v2.valid?({
                       "version" => 2,
                       "steps" => [
                         { "sleep" => "86400s" },
                         { "type" => "x", "speed" => "1000.0cps" },
                         { "wait" => "x" * 512 }
                       ],
                       "render" => {
                         "window" => { "width" => 120, "padding" => 40 },
                         "animation" => { "final_delay" => 86_400_000 }
                       }
                     })).to be true
  end
end
