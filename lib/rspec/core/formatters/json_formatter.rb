RSpec::Support.require_rspec_core "formatters/base_formatter"
RSpec::Support.require_rspec_core "shell_escape"
require 'json'

module RSpec
  module Core
    module Formatters
      # @private
      class JsonFormatter < BaseFormatter
        include RSpec::Core::ShellEscape

        Formatters.register self, :message, :dump_summary, :dump_profile, :stop, :seed, :close

        attr_reader :output_hash

        def initialize(output)
          super
          @output_hash = {
            :version => RSpec::Core::Version::STRING
          }
        end

        def message(notification)
          (@output_hash[:messages] ||= []) << notification.message
        end

        def dump_summary(summary)
          @output_hash[:summary] = {
            :duration => summary.duration,
            :example_count => summary.example_count,
            :failure_count => summary.failure_count,
            :pending_count => summary.pending_count,
            :errors_outside_of_examples_count => summary.errors_outside_of_examples_count
          }
          @output_hash[:summary_line] = summary.totals_line
        end

        def stop(group_notification)
          notifications = group_notification.notifications
          duplicate_rerun_locations = duplicate_rerun_locations_for(notifications.map(&:example))

          @output_hash[:examples] = notifications.map do |notification|
            format_example(notification.example, duplicate_rerun_locations).tap do |hash|
              e = notification.example.exception

              if e
                hash[:exception] = {
                  :class => e.class.name,
                  :message => e.message,
                  :backtrace => notification.formatted_backtrace,
                }
              end
            end
          end
        end

        def seed(notification)
          return unless notification.seed_used?
          @output_hash[:seed] = notification.seed
        end

        def close(_notification)
          output.write @output_hash.to_json
        end

        def dump_profile(profile)
          @output_hash[:profile] = {}
          dump_profile_slowest_examples(profile)
          dump_profile_slowest_example_groups(profile)
        end

        # @api private
        def dump_profile_slowest_examples(profile)
          @output_hash[:profile] = {}
          duplicate_rerun_locations = duplicate_rerun_locations_for(profile.examples)

          @output_hash[:profile][:examples] = profile.slowest_examples.map do |example|
            format_example(example, duplicate_rerun_locations).tap do |hash|
              hash[:run_time] = example.execution_result.run_time
            end
          end
          @output_hash[:profile][:slowest] = profile.slow_duration
          @output_hash[:profile][:total] = profile.duration
        end

        # @api private
        def dump_profile_slowest_example_groups(profile)
          @output_hash[:profile] ||= {}
          @output_hash[:profile][:groups] = profile.slowest_groups.map do |loc, hash|
            hash.update(:location => loc)
          end
        end

      private

        def format_example(example, duplicate_rerun_locations = {})
          {
            :id => example.id,
            :description => example.description,
            :full_description => example.full_description,
            :status => example.execution_result.status.to_s,
            :file_path => example.metadata[:file_path],
            :line_number  => example.metadata[:line_number],
            :rerun_argument => rerun_argument_for(example, duplicate_rerun_locations),
            :run_time => example.execution_result.run_time,
            :pending_message => example.execution_result.pending_message,
          }
        end

        def rerun_argument_for(example, duplicate_rerun_locations)
          location = example.location_rerun_argument

          return location unless duplicate_rerun_locations.key?(location)
          return location if RSpec.configuration.force_line_number_for_spec_rerun
          conditionally_quote(example.id)
        end

        def duplicate_rerun_locations_for(examples)
          examples.each_with_object(Hash.new(0)) do |example, counts|
            counts[example.location_rerun_argument] += 1
          end.select { |_, count| count > 1 }
        end
      end
    end
  end
end
