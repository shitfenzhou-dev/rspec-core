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

  describe "rerun_argument" do
    let(:example_with_unique_location) do
      example = new_example
      allow(example).to receive(:location_rerun_argument) { "unique_spec.rb:1" }
      allow(example).to receive(:id) { "unique_id" }
      example
    end

    let(:example_with_duplicate_location_1) do
      example = new_example
      allow(example).to receive(:location_rerun_argument) { "duplicate_spec.rb:2" }
      allow(example).to receive(:id) { "duplicate_id_1" }
      example
    end

    let(:example_with_duplicate_location_2) do
      example = new_example
      allow(example).to receive(:location_rerun_argument) { "duplicate_spec.rb:2" }
      allow(example).to receive(:id) { "duplicate_id_2" }
      example
    end

    let(:examples_notification) do
      lambda do |examples|
        reporter = instance_double(RSpec::Core::Reporter)
        allow(reporter).to receive(:examples) { examples }
        allow(reporter).to receive(:notifications) { examples.map { |e| RSpec::Core::Notifications::ExampleNotification.for(e) } }
        RSpec::Core::Notifications::ExamplesNotification.new(reporter)
      end
    end

    context "when no duplicate locations" do
      it "uses location_rerun_argument for each example" do
        examples = [example_with_unique_location]
        send_notification :stop, examples_notification.call(examples)

        expect(formatter.output_hash[:examples][0][:rerun_argument]).to eq("unique_spec.rb:1")
      end
    end

    context "when there are duplicate locations" do
      it "uses example.id for duplicates" do
        examples = [example_with_duplicate_location_1, example_with_duplicate_location_2]
        send_notification :stop, examples_notification.call(examples)

        expect(formatter.output_hash[:examples][0][:rerun_argument]).to eq("duplicate_id_1")
        expect(formatter.output_hash[:examples][1][:rerun_argument]).to eq("duplicate_id_2")
      end
    end

    context "when force_line_number_for_spec_rerun is true" do
      before { allow(RSpec.configuration).to receive(:force_line_number_for_spec_rerun) { true } }

      it "still uses location_rerun_argument even if there are duplicates" do
        examples = [example_with_duplicate_location_1, example_with_duplicate_location_2]
        send_notification :stop, examples_notification.call(examples)

        expect(formatter.output_hash[:examples][0][:rerun_argument]).to eq("duplicate_spec.rb:2")
        expect(formatter.output_hash[:examples][1][:rerun_argument]).to eq("duplicate_spec.rb:2")
      end
    end

    context "for different example statuses" do
      it "includes rerun_argument for passed, failed, pending, and pending fixed examples" do
        passed_example = new_example(:status => :passed)
        failed_example = new_example(:status => :failed)
        pending_example = new_example(:status => :pending)

        allow(passed_example).to receive(:location_rerun_argument) { "passed_spec.rb:1" }
        allow(passed_example).to receive(:id) { "passed_id" }
        allow(failed_example).to receive(:location_rerun_argument) { "failed_spec.rb:2" }
        allow(failed_example).to receive(:id) { "failed_id" }
        allow(pending_example).to receive(:location_rerun_argument) { "pending_spec.rb:3" }
        allow(pending_example).to receive(:id) { "pending_id" }

        examples = [passed_example, failed_example, pending_example]
        send_notification :stop, examples_notification.call(examples)

        formatter.output_hash[:examples].each do |example_hash|
          expect(example_hash).to have_key(:rerun_argument)
        end
      end
    end

    context "in dump_profile" do
      it "uses the same rerun_argument logic for slowest examples" do
        slow_example = new_example
        fast_example = new_example
        allow(slow_example).to receive(:location_rerun_argument) { "slow_spec.rb:1" }
        allow(slow_example).to receive(:id) { "slow_id" }
        allow(slow_example.execution_result).to receive(:run_time) { 2.0 }
        allow(fast_example).to receive(:location_rerun_argument) { "fast_spec.rb:2" }
        allow(fast_example).to receive(:id) { "fast_id" }
        allow(fast_example.execution_result).to receive(:run_time) { 1.0 }

        examples = [slow_example, fast_example]
        send_notification :dump_profile, profile_notification(3.0, examples, 10)

        expect(formatter.output_hash[:profile][:examples][0]).to have_key(:rerun_argument)
      end

      it "handles direct dump_profile without prior stop gracefully" do
        examples = [example_with_duplicate_location_1, example_with_duplicate_location_2]

        expect {
          send_notification :dump_profile, profile_notification(0.5, examples, 10)
        }.not_to raise_error

        expect(formatter.output_hash[:profile][:examples][0]).to have_key(:rerun_argument)
      end
    end
  end
end