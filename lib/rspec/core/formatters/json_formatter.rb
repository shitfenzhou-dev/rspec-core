RSpec::Support.require_rspec_core "formatters/base_formatter"
require 'json'

module RSpec
  module Core
    module Formatters
      # @private
      class JsonFormatter < BaseFormatter
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
          compute_duplicate_rerun_locations(group_notification.notifications.map(&:example))
          @output_hash[:examples] = group_notification.notifications.map do |notification|
            format_example(notification.example).tap do |hash|
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
          unless @duplicate_rerun_locations
            compute_duplicate_rerun_locations(profile.examples)
          end
          @output_hash[:profile][:examples] = profile.slowest_examples.map do |example|
            format_example(example).tap do |hash|
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

        def format_example(example)
          {
            :id => example.id,
            :description => example.description,
            :full_description => example.full_description,
            :status => example.execution_result.status.to_s,
            :file_path => example.metadata[:file_path],
            :line_number  => example.metadata[:line_number],
            :run_time => example.execution_result.run_time,
            :pending_message => example.execution_result.pending_message,
            :rerun_argument => rerun_argument_for(example),
          }
        end

        def rerun_argument_for(example)
          location = example.location_rerun_argument
          return location if RSpec.configuration.force_line_number_for_spec_rerun
          return location unless @duplicate_rerun_locations.include?(location)
          example.id
        end

        def compute_duplicate_rerun_locations(examples)
          locations = examples.map(&:location_rerun_argument)
          @duplicate_rerun_locations = Set.new.tap do |s|
            locations.group_by { |l| l }.each do |l, ls|
              s << l if ls.count > 1
            end
          end
        end
      end
    end
  end
end
