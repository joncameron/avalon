# Copyright 2011-2015, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

require 'roo'

module Avalon
  module Batch
    class Manifest
      include Enumerable
      extend Forwardable

      EXTENSIONS = %w(csv xls xlsx ods).freeze
      FILE_FIELDS = [:file, :label, :offset, :skip_transcoding, :absolute_location, :date_digitized].freeze
      SKIP_FIELDS = [:collection].freeze

      def_delegators :@entries, :each
      attr_reader :spreadsheet, :file, :name, :email, :entries, :package

      class << self
        def locate(root)
          possibles = Dir[File.join(root, "**/*.{#{EXTENSIONS.join(',')}}")]
          possibles.reject do |file|
            File.basename(file) =~ /^~\$/ || error?(file) || processing?(file) || processed?(file)
          end
        end

        def error?(file)
          if File.file?("#{file}.error")
            if File.mtime(file) > File.mtime("#{file}.error")
              File.unlink("#{file}.error")
              return false
            else
              return true
            end
          end
          false
        end

        def processing?(file)
          File.file?("#{file}.processing")
        end

        def processed?(file)
          File.file?("#{file}.processed")
        end
      end

      def initialize(file, package)
        @file = file
        @package = package
        load!
      end

      def load!
        @entries = []
        begin
          @spreadsheet = Roo::Spreadsheet.open(file)
          @name = @spreadsheet.row(@spreadsheet.first_row)[0]
          @email = @spreadsheet.row(@spreadsheet.first_row)[1]

          header_row = @spreadsheet.row(@spreadsheet.first_row + 1)

          @field_names = header_row.collect do |field|
            field.to_s.downcase.gsub(/\s/, '_').strip.to_sym
          end
          create_entries!
        rescue Exception => err
          error! "Invalid manifest file: #{err.message}"
        end
      end

      def start!
        File.open("#{@file}.processing", 'w') { |f| f.puts Time.now.xmlschema }
      end

      def error!(msg = nil)
        File.open("#{@file}.error", 'a') do |f|
          if msg.nil?
            entries.each do |entry|
              if entry.errors.count > 0
                f.puts "Row #{entry.row}:"
                entry.errors.messages.each { |_k, m| f.puts %(  #{m.join("\n  ")}) }
              end
            end
          else
            f.puts msg
          end
        end
        rollback! if processing?
      end

      def rollback!
        File.unlink("#{@file}.processing")
      end

      def commit!
        File.open("#{@file}.processed", 'w') { |f| f.puts Time.now.xmlschema }
        rollback! if processing?
      end

      def error?
        result = self.class.error?(@file)
        load! unless result
        result
      end

      def processing?
        self.class.processing?(@file)
      end

      def processed?
        self.class.processed?(@file)
      end

      def errors
        @errors ||= []
      end

      private

      def true?(value)
        !(value.to_s =~ /^(y(es)?|t(rue)?)$/i).nil?
      end

      def create_entries!
        f = @spreadsheet.first_row + 2
        l = @spreadsheet.last_row
        f.upto(l) do |index|
          opts = {
            publish: false,
            hidden: false
          }

          values = @spreadsheet.row(index).collect do |val|
            (val.is_a?(Float) && (val == val.to_i)) ? val.to_i.to_s : val.to_s
          end
          content = []

          fields = Hash.new { |h, k| h[k] = [] }
          @field_names.each_with_index do |f, i|
            if f.blank? || SKIP_FIELDS.include?(f) || values[i].blank?
              fields[f] << values[i]
            else
              next unless FILE_FIELDS.include?(f)
              content << {} if f == :file
              content.last[f] = f == :skip_transcoding ? true?(values[i]) : values[i]
              end
          end

          opts.keys.each do |opt|
            val = Array(fields.delete(opt)).first.to_s
            opts[opt] = if opts[opt].is_a?(TrueClass) || opts[opt].is_a?(FalseClass)
                          true?(val)
                        else
                          val
                        end
          end
          entries << Entry.new(fields.select { |f| !FILE_FIELDS.include?(f) }, content, opts, index, self)
        end
      end
    end
  end
end
