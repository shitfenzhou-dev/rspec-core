require 'rspec/core/formatters/json_formatter'
require 'json'
require 'rspec/core/reporter'

# todo, someday:
# it "lists the groups (describe and context) separately"
# it "includes full 'execution_result'"
# it "relativizes backtrace paths"
# it "includes profile information (implements dump_profile)"
# it "shows the pending message if one was given"
# it "shows the seed if run was randomized"
# it "lists pending specs that were fixed"
RSpec.describe RSpec::Core::Formatters::JsonFormatter do
  include FormatterSupport

  it "can be loaded via `--format json`" do
    output = run_example_specs_with_formatter("json", :normalize_output => false, :seed => 42)
    parsed = JSON.parse(output)
    expect(parsed.keys).to include("examples", "summary", "summary_line", "seed")
  end

  it "outputs expected json (brittle high level functional test)" do
    its = []
    group = RSpec.describe("one apiece") do
      its.push it("succeeds") { expect(1).to eq 1 }
      its.push it("fails") { fail "eek" }
      its.push it("pends") { pending "world peace"; fail "eek" }
    end
    succeeding_line = __LINE__ - 4
    failing_line = __LINE__ - 4
    pending_line = __LINE__ - 4

    now = Time.now
    allow(Time).to receive(:now).and_return(now)
    reporter.report(2) do |r|
      group.run(r)
    end

    # grab the actual backtrace -- kind of a cheat
    examples = formatter.output_hash[:examples]
    failing_backtrace = examples[1][:exception][:backtrace]
    this_file = relative_path(__FILE__)

    expected = {
      :version => RSpec::Core::Version::STRING,
      :examples => [
        {
          :id => its[0].id,
          :description => "succeeds",
          :full_description => "one apiece succeeds",
          :status => "passed",
          :file_path => this_file,
          :line_number => succeeding_line,
          :run_time => formatter.output_hash[:examples][0][:run_time],
          :pending_message => nil,
          :rerun_argument => formatter.output_hash[:examples][0][:rerun_argument],
        },
        {
          :id => its[1].id,
          :description => "fails",
          :full_description => "one apiece fails",
          :status => "failed",
          :file_path => this_file,
          :line_number => failing_line,
          :run_time => formatter.output_hash[:examples][1][:run_time],
          :pending_message => nil,
          :exception => {
            :class     => "RuntimeError",
            :message   => "eek",
            :backtrace => failing_backtrace
          },
          :rerun_argument => formatter.output_hash[:examples][1][:rerun_argument],
        },
        {
          :id => its[2].id,
          :description => "pends",
          :full_description => "one apiece pends",
          :status => "pending",
          :file_path => this_file,
          :line_number => pending_line,
          :run_time => formatter.output_hash[:examples][2][:run_time],
          :pending_message => "world peace",
          :rerun_argument => formatter.output_hash[:examples][2][:rerun_argument],
        },
      ],
      :summary => {
        :duration => formatter.output_hash[:summary][:duration],
        :example_count => 3,
        :failure_count => 1,
        :pending_count => 1,
        :errors_outside_of_examples_count => 0,
      },
      :summary_line => "3 examples, 1 failure, 1 pending"
    }
    expect(formatter.output_hash).to eq expected
    expect(formatter_output.string).to eq expected.to_json
  end

  context "when full backtrace is enabled" do
    around do |example|
      original_value = RSpec.configuration.full_backtrace?
      RSpec.configuration.full_backtrace = true
      example.run
      RSpec.configuration.full_backtrace = original_value
    end

    it "outputs the full backtrace" do
      group = RSpec.describe do
        it("fails") { fail "eek" }
      end

      reporter.report(1) { |r| group.run(r) }

      formatted_backtrace = formatter.output_hash[:examples][0][:exception][:backtrace]
      exception_backtrace = group.examples[0].exception.backtrace.map { |l| l.gsub(Dir.pwd, ".") }

      expect(formatted_backtrace).to eq(exception_backtrace)
    end
  end

  context "when full backtrace is disabled" do
    around do |example|
      original_value = RSpec.configuration.full_backtrace?
      RSpec.configuration.full_backtrace = false
      example.run
      RSpec.configuration.full_backtrace = original_value
    end

    it "outputs a strict subset of the full backtrace" do
      group = RSpec.describe do
        it("fails") { fail "eek" }
      end

      reporter.report(1) { |r| group.run(r) }

      formatted_backtrace = formatter.output_hash[:examples][0][:exception][:backtrace]
      exception_backtrace = group.examples[0].exception.backtrace.map { |l| l.gsub(Dir.pwd, ".") }

      expect(formatted_backtrace).not_to be_empty

      # Every line in the formatted backtrace is also in the original backtrace
      expect(formatted_backtrace - exception_backtrace).to be_empty
      # The original backtrace contains lines not in the formatted backtrace
      expect(exception_backtrace - formatted_backtrace).not_to be_empty
    end
  end

  describe "#stop" do
    it "adds all examples to the output hash" do
      send_notification :stop, stop_notification
      expect(formatter.output_hash[:examples]).not_to be_nil
    end
  end

  describe "#seed" do
    context "use random seed" do
      it "adds random seed" do
        send_notification :seed, seed_notification(42)
        expect(formatter.output_hash[:seed]).to eq(42)
      end
    end

    context "don't use random seed" do
      it "don't add random seed" do
        send_notification :seed, seed_notification(42, false)
        expect(formatter.output_hash[:seed]).to be_nil
      end
    end
  end

  describe "#close" do
    it "outputs the results as a JSON string" do
      expect(formatter_output.string).to eq ""
      send_notification :close, null_notification
      expect(formatter_output.string).to eq({
        :version => RSpec::Core::Version::STRING
      }.to_json)
    end

    it "does not close the stream so that it can be reused within a process" do
      formatter.close(RSpec::Core::Notifications::NullNotification)
      expect(formatter_output.closed?).to be(false)
    end
  end

  describe "#message" do
    it "adds a message to the messages list" do
      send_notification :message, message_notification("good job")
      expect(formatter.output_hash[:messages]).to eq ["good job"]
    end
  end

  describe "#dump_summary" do
    it "adds summary info to the output hash" do
      send_notification :dump_summary, summary_notification(1.0, examples(10), examples(3), examples(4), 0, 1)
      expect(formatter.output_hash[:summary]).to include(
        :duration => 1.0, :example_count => 10, :failure_count => 3,
        :pending_count => 4, :errors_outside_of_examples_count => 1
      )
      summary_line = formatter.output_hash[:summary_line]
      expect(summary_line).to eq "10 examples, 3 failures, 4 pending, 1 error occurred outside of examples"
    end
  end

  describe "#dump_profile", :slow do

    def profile *groups
      groups.each { |group| group.run(reporter) }
      examples = groups.map(&:examples).flatten
      send_notification :dump_profile, profile_notification(0.5, examples, 10)
    end

    before do
      setup_profiler
      formatter
    end

    context "with one example group" do
      before do
        profile( RSpec.describe("group") do
          example("example") { }
        end)
      end

      it "names the example" do
        expect(formatter.output_hash[:profile][:examples].first[:full_description]).to eq("group example")
      end

      it "provides example execution time" do
        expect(formatter.output_hash[:profile][:examples].first[:run_time]).not_to be_nil
      end

      it "doesn't profile a single example group" do
        expect(formatter.output_hash[:profile][:groups]).to be_empty
      end

      it "has the summary of profile information" do
        expect(formatter.output_hash[:profile].keys).to match_array([:examples, :groups, :slowest, :total])
      end
    end

    context "with multiple example groups", :slow do
      before do
        start = Time.utc(2015, 6, 10, 12, 30)
        now = start

        allow(RSpec::Core::Time).to receive(:now) { now }

        group1 = RSpec.describe("slow group") do
          example("example") { }
          after { now += 100 }
        end
        group2 = RSpec.describe("fast group") do
          example("example 1") { }
          example("example 2") { }
          after { now += 1 }
        end
        profile group1, group2
      end

      it "provides the slowest example groups" do
        expect(formatter.output_hash).not_to be_empty
      end

      it "provides information" do
        expect(formatter.output_hash[:profile][:groups].first.keys).to match_array([:total_time, :count, :description, :average, :location, :start])
      end

      it "ranks the example groups by average time" do |ex|
        expect(formatter.output_hash[:profile][:groups].first[:description]).to eq("slow group")
      end
    end
  end

  describe ":rerun_argument field" do
    def build_example(overrides = {})
      result = RSpec::Core::Example::ExecutionResult.new
      result.started_at = ::Time.now
      status = overrides.fetch(:status, :passed)
      result.record_finished(status, ::Time.now)
      result.exception = Exception.new if status == :failed
      if overrides.delete(:pending_fixed)
        result.pending_fixed = true
      end

      defaults = {
        :description => "Example",
        :full_description => "Example",
        :example_group => group,
        :execution_result => result,
        :location => "",
        :location_rerun_argument => "./spec/test_spec.rb:1",
        :id => "./spec/test_spec.rb:1:1",
        :exception => (status == :failed ? Exception.new : nil),
        :metadata => {
          :shared_group_inclusion_backtrace => [],
          :file_path => "./spec/test_spec.rb",
          :line_number => 1
        }
      }

      instance_double(RSpec::Core::Example, defaults.merge(overrides))
    end

    def build_stop_notification_from(*examples)
      notifications = examples.map do |ex|
        double(:example => ex, :formatted_backtrace => [])
      end
      double(:notifications => notifications)
    end

    context "when all examples have unique location_rerun_argument" do
      it "uses location_rerun_argument as rerun_argument" do
        ex1 = build_example(:location_rerun_argument => "./spec/a_spec.rb:1", :id => "./spec/a_spec.rb:1:1")
        ex2 = build_example(:location_rerun_argument => "./spec/a_spec.rb:2", :id => "./spec/a_spec.rb:2:1")

        formatter.stop(build_stop_notification_from(ex1, ex2))

        examples = formatter.output_hash[:examples]
        expect(examples[0][:rerun_argument]).to eq("./spec/a_spec.rb:1")
        expect(examples[1][:rerun_argument]).to eq("./spec/a_spec.rb:2")
      end
    end

    context "when multiple examples share the same location_rerun_argument" do
      it "falls back to example.id for all duplicates" do
        ex1 = build_example(:location_rerun_argument => "./spec/a_spec.rb:1", :id => "./spec/a_spec.rb:1:1")
        ex2 = build_example(:location_rerun_argument => "./spec/a_spec.rb:1", :id => "./spec/a_spec.rb:1:2")
        ex3 = build_example(:location_rerun_argument => "./spec/a_spec.rb:2", :id => "./spec/a_spec.rb:2:1")

        formatter.stop(build_stop_notification_from(ex1, ex2, ex3))

        examples = formatter.output_hash[:examples]
        expect(examples[0][:rerun_argument]).to eq("./spec/a_spec.rb:1:1")
        expect(examples[1][:rerun_argument]).to eq("./spec/a_spec.rb:1:2")
        expect(examples[2][:rerun_argument]).to eq("./spec/a_spec.rb:2")
      end
    end

    context "when force_line_number_for_spec_rerun is true" do
      around do |ex|
        original = RSpec.configuration.force_line_number_for_spec_rerun
        RSpec.configuration.force_line_number_for_spec_rerun = true
        ex.run
        RSpec.configuration.force_line_number_for_spec_rerun = original
      end

      it "uses location_rerun_argument even for duplicates" do
        ex1 = build_example(:location_rerun_argument => "./spec/a_spec.rb:1", :id => "./spec/a_spec.rb:1:1")
        ex2 = build_example(:location_rerun_argument => "./spec/a_spec.rb:1", :id => "./spec/a_spec.rb:1:2")

        formatter.stop(build_stop_notification_from(ex1, ex2))

        examples = formatter.output_hash[:examples]
        expect(examples[0][:rerun_argument]).to eq("./spec/a_spec.rb:1")
        expect(examples[1][:rerun_argument]).to eq("./spec/a_spec.rb:1")
      end
    end

    context "for different example statuses" do
      it "includes rerun_argument for passed examples" do
        ex = build_example(:status => :passed, :location_rerun_argument => "./spec/a_spec.rb:5", :id => "./spec/a_spec.rb:5:1")
        formatter.stop(build_stop_notification_from(ex))
        expect(formatter.output_hash[:examples][0][:rerun_argument]).to eq("./spec/a_spec.rb:5")
      end

      it "includes rerun_argument for failed examples" do
        ex = build_example(:status => :failed, :location_rerun_argument => "./spec/a_spec.rb:5", :id => "./spec/a_spec.rb:5:1")
        formatter.stop(build_stop_notification_from(ex))
        expect(formatter.output_hash[:examples][0][:rerun_argument]).to eq("./spec/a_spec.rb:5")
      end

      it "includes rerun_argument for pending examples" do
        result = RSpec::Core::Example::ExecutionResult.new
        result.started_at = ::Time.now
        result.record_finished(:pending, ::Time.now)
        result.pending_message = "not ready"

        ex = instance_double(RSpec::Core::Example,
          :description => "Example",
          :full_description => "Example",
          :example_group => group,
          :execution_result => result,
          :location => "",
          :location_rerun_argument => "./spec/a_spec.rb:5",
          :id => "./spec/a_spec.rb:5:1",
          :exception => nil,
          :metadata => { :shared_group_inclusion_backtrace => [], :file_path => "./spec/a_spec.rb", :line_number => 5 }
        )

        formatter.stop(build_stop_notification_from(ex))
        expect(formatter.output_hash[:examples][0][:rerun_argument]).to eq("./spec/a_spec.rb:5")
      end

      it "includes rerun_argument for pending fixed examples" do
        result = RSpec::Core::Example::ExecutionResult.new
        result.started_at = ::Time.now
        result.record_finished(:pending, ::Time.now)
        result.pending_fixed = true
        result.pending_message = "was pending but passed"

        ex = instance_double(RSpec::Core::Example,
          :description => "Example",
          :full_description => "Example",
          :example_group => group,
          :execution_result => result,
          :location => "",
          :location_rerun_argument => "./spec/a_spec.rb:5",
          :id => "./spec/a_spec.rb:5:1",
          :exception => nil,
          :metadata => { :shared_group_inclusion_backtrace => [], :file_path => "./spec/a_spec.rb", :line_number => 5 }
        )

        formatter.stop(build_stop_notification_from(ex))
        expect(formatter.output_hash[:examples][0][:rerun_argument]).to eq("./spec/a_spec.rb:5")
      end
    end

    context "in profile output" do
      it "includes rerun_argument for profile slowest examples" do
        setup_profiler
        grp = RSpec.describe("profile group") do
          example("example") { }
        end
        grp.run(reporter)
        examples = grp.examples
        send_notification :dump_profile, profile_notification(0.5, examples, 10)

        profile_examples = formatter.output_hash[:profile][:examples]
        expect(profile_examples.first).to have_key(:rerun_argument)
      end

      it "uses duplicate detection from the full run when stop was called first" do
        ex1 = build_example(:location_rerun_argument => "./spec/a_spec.rb:1", :id => "./spec/a_spec.rb:1:1")
        ex2 = build_example(:location_rerun_argument => "./spec/a_spec.rb:1", :id => "./spec/a_spec.rb:1:2")
        ex3 = build_example(:location_rerun_argument => "./spec/a_spec.rb:2", :id => "./spec/a_spec.rb:2:1")

        formatter.stop(build_stop_notification_from(ex1, ex2, ex3))

        profile = double(:slowest_examples => [ex1], :slow_duration => 0.5, :duration => 1.0)
        formatter.dump_profile_slowest_examples(profile)

        profile_example = formatter.output_hash[:profile][:examples][0]
        expect(profile_example[:rerun_argument]).to eq("./spec/a_spec.rb:1:1")
      end
    end

    context "when dump_profile is called without stop" do
      it "does not raise an error and computes rerun_argument from profile examples" do
        ex1 = build_example(:location_rerun_argument => "./spec/a_spec.rb:1", :id => "./spec/a_spec.rb:1:1")

        profile = double(:slowest_examples => [ex1], :slow_duration => 0.5, :duration => 1.0)
        expect { formatter.dump_profile_slowest_examples(profile) }.not_to raise_error

        profile_example = formatter.output_hash[:profile][:examples][0]
        expect(profile_example[:rerun_argument]).to eq("./spec/a_spec.rb:1")
      end

      it "detects duplicates within profile examples as a fallback" do
        ex1 = build_example(:location_rerun_argument => "./spec/a_spec.rb:1", :id => "./spec/a_spec.rb:1:1")
        ex2 = build_example(:location_rerun_argument => "./spec/a_spec.rb:1", :id => "./spec/a_spec.rb:1:2")

        profile = double(:slowest_examples => [ex1, ex2], :slow_duration => 0.5, :duration => 1.0)
        formatter.dump_profile_slowest_examples(profile)

        profile_examples = formatter.output_hash[:profile][:examples]
        expect(profile_examples[0][:rerun_argument]).to eq("./spec/a_spec.rb:1:1")
        expect(profile_examples[1][:rerun_argument]).to eq("./spec/a_spec.rb:1:2")
      end
    end
  end
end
