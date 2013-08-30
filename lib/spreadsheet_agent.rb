# Author: Darin London
# The license of this source is "New BSD Licence"

require 'spreadsheet_agent/db'
require 'socket'
require 'open3'
require 'capture_io'
require 'mail'

# A Distributed Agent System using Google Spreadsheets
#
# Version 0.01
#
# SpreadsheetAgent is a framework for creating massively distributed pipelines
# across many different servers, each using the same google spreadsheet as a
# control panel.  It is extensible, and flexible.  It doesnt specify what
# goals any pipeline should be working towards, or which goals are prerequisites
# for other goals, but it does provide logic for easily defining these relationships
# based on your own needs.  It does this by providing a subsumption architecture,
# whereby many small, highly focused agents are written to perform specific goals,
# and also know what resources they require to perform them.  Agents can be coded to
# subsume other agents upon successful completion.  In addition, it is
# designed from the beginning to support the creation of simple human-computational
# workflows.
#
# SpreadsheetAgent requires GoogleDrive, and works with a Google Spreadsheet with some or all worksheets
# formatted according to the following:
# * The top row of a page to be processed has fields for all entry record in subsequent rows
# * You can define any fields necessary, but you must specify a 'ready' and a 'complete' field
# * You must define at least 1 key field, and the key field must be specified as required in the :config (see SpreadsheetAgent::Db)
# * You should then define fields named for agent_bin/#{ field_name }_agent.rb for each agent that you plan to deploy in your pipeline
#
module SpreadsheetAgent

# SpreadsheetAgent::Agent is designed to make it easy to create a single task which connects to
# a field within a record on a page within the configured SpreadsheetAgent compatible Google Spreadsheet,
# runs, and reports whether the job completed or ended in error.  An agent can be configured to only run
# when certain prerequisite fields have completed.  The data in these fields can be filled in by other
# SpreadsheetAgent::Agents, SpreadsheetAgent::Runners, or humans.  Compute node configuration is available
# to prevent the agent from running more than a certain number of instances of itself, or not run if certain
# other agents or processes are running on the node.  Finally, an agent can be configured to subsume another
# agent, and fill in the completion field for that agent in addition to its own when it completes successfully.
#
# extends SpreadsheetAgent::Db
  class Agent < SpreadsheetAgent::Db

# The name of the field in the page to which the agent should report status
    attr_accessor :agent_name

# The name of the Page on the Google Spreadsheet that contains the record to be worked on by the agent
    attr_accessor :page_name

# hash of key-value pairs.  The keys are defined in config/agent.conf.yml.  The values
# specify the values for those fields in the record on the page for which the agent is running.
# All keys configured as 'required: 1' in config/agent.conf.yml must be included in the keys hash
    attr_accessor :keys

# Boolean. When true, the agent code will print verbosely to STDERR.  When false, and the process!
# returns a failure status, the agent will email all stdout and stderr to the email specified in the
# :config send_to value
    attr_accessor :debug

# Optional array of prerequisite fields that must contain a 1 in them for the record on the page before
# the agent will attempt to run
    attr_accessor :prerequisites

# Optional integer.  This works on Linux with ps.  The agent will not attempt to run if there are
# max_selves instances running
    attr_accessor :max_selves

# Hash of process_name to number of max_instances.  This works on Linux with ps.  If the agent detects
# the specified number of max_instances of the given process (based on a line match), it will not
# attempt to run
    attr_accessor :conflicts_with

# Array of fields on the record which this agent subsumes.  If the agent completes successfully these
# fields will be updated with a 1 in addition to the field for the agent
    attr_accessor :subsumes

# Readonly access to the GoogleDrive::Worksheet that is being access by the agent.
    attr_reader :worksheet

# create a new SpreadsheetAgent::Agent with the following:
# == required configuration parameters:
# * agent_name
# * page_name
# * keys
#
# == optional parameters:
# * config_file: (see SpreadsheetAgent::DB)
# * debug
# * prerequisites
# * max_selves
# * conflicts_with
# * subsumes
#
    def initialize(attributes)
      @agent_name = attributes[:agent_name]
      @page_name = attributes[:page_name]
      @keys = attributes[:keys].clone
      unless @agent_name && @page_name && @keys
        raise SpreadsheetAgentError, "agent_name, page_name, and keys attributes are required!"
      end
      @config_file = attributes[:config_file]
      build_db()

      @worksheet = @db.worksheet_by_title(@page_name)
      @debug = attributes[:debug]
      if attributes[:prerequisites]
        @prerequisites = attributes[:prerequisites].clone
      end
    
      @max_selves = attributes[:max_selves]
      if attributes[:conflicts_with]
        @conflicts_with = attributes[:conflicts_with].clone
      end
      if attributes[:subsumes]
        @subsumes = attributes[:subsumes].clone
      end
    end

# If the agent does not have any conflicting processes (max_selves or conflicts_with)
# and if the entry is ready (field 'ready' has a 1), and all prerequisite fields have a 1,
# gets the GoogleDrive::List record, and passes it to the supplied agent_code PROC as argument.
# This PROC must return a required boolean field indicating success or failure, and an optional
# hash of key - value fields that will be updated on the GoogleDrive::List record.  Note, the updates
# are made regardless of the value of success.  In fact, the agent can be configured to update
# different fields based on success or failure.   Also, note that any value can be stored in the
# hash.  This allows the agent to communicate any useful information to the google spreadsheet for other
# agents (SpreadsheetAgent::Agent, SpreadsheetAgent::Runner, or human) to use. The PROC must try at all
# costs to avoid terminating. If an error is encountered, it should return false for the success field
# to signal that the process failed.  If no errors are encountered it should return true for the success
# field.
#
#   Exits successfully, enters a 1 in the agent_name field
#   $agent->process! do |entry|
#     true
#   end
#
#   Same, but also updates the 'notice' field in the record along with the 1 in the agent_name field
#   $agent->process! do |entry|
#     [true, {:notice => 'There were 30 files processed'}]
#   end
#
#   Fails, enters f:#{hostname} in the agent_name field
#   $agent->process! do |entry|
#     false
#
#   Same, but also updates the 'notice' field in the record along with the failure notice
#   $agent->process! do |entry|
#     [false, {:notice => 'There were 10 files left to process!' }]
#   end
#
#   This agent passes different parameters based on success or failure
#   $agent->process! do |entry|
#     if $success
#       true
#     else
#       [ false, {:notice => 'there were 10 remaining files'}]
#     end
#   end
#
    def process!(&agent_code)
      @worksheet.reload
      no_problems = true
      capture_output = nil
      unless @debug
        capture_output = CaptureIO.new
        capture_output.start
      end

      begin
        return true if has_conflicts()
        (runnable, entry) = run_entry()
        return false unless entry
        return true unless runnable
      
        success, update_entry = agent_code.call(entry)
        if success
          complete_entry(update_entry)
        else
          fail_entry(update_entry)
        end
      rescue
        $stderr.puts "#{ $! }"
        no_problems = false
      end
      unless capture_output.nil?
        if no_problems
          capture_output.stop
        else
          mail_error(capture_output.stop)
        end
      end
      return no_problems
    end

# Returns the GoogleDrive::List object for the specified keys
    def get_entry
      this_entry = nil
      if @worksheet
        @worksheet.list.each do |this_row|
          keep_row = true

          @config['key_fields'].keys.reject { |key_field|
            !(@config['key_fields'][key_field]["required"]) && !(@keys[key_field])
          }.each do |key|
            break unless keep_row
            keep_row = (this_row[key] == @keys[key])
          end
        
          if keep_row
            return this_row
          end
        end
      end
    end

    private

    def has_conflicts
      return unless (@max_selves || @conflicts_with) # nothing conflicts here

      running_conflicters = {}
      self_name = File.basename $0

      begin
        conflicting_in = Open3.popen3('ps','-eo','pid,command')[1]
        conflicting_in.lines.each do |line|
          unless(
                 (line.match(/emacs\s+|vim*\s+|pico\s+/)) ||
                 (line.match("#{ $$ }"))
                 )
            if @max_selves && line.match(self_name)
              if running_conflicters[@agent_name].nil?
                running_conflicters[@agent_name] = 1
              else
                running_conflicters[@agent_name] += 1
              end
            
              if running_conflicters[@agent_name] == @max_selves
                $stderr.puts "max_selves limit reached" if @debug
                conflicting_in.close
                return true
              end
            end

            if @conflicts_with
              @conflicts_with.keys.each do |conflicter|
                if line.match(conflicter)
                  if running_conflicters[conflicter].nil?
                    running_conflicters[conflicter] = 1
                  else
                    running_conflicters[conflicter] += 1
                  end
                  if running_conflicters[conflicter] >= @conflicts_with[conflicter]
                    $stderr.puts "conflicts with #{ conflicter }" if @debug
                    conflicting_in.close
                    return true
                  end
                end
              end
            end
          end
        end
        conflicting_in.close
        return false
      
      rescue
        $stderr.puts "Couldnt check conflicts #{ $! }" if @debug
        return true
      end

    end

    # this call initiates a race resistant attempt to make sure that there is only 1
    # clear 'winner' among N potential agents attempting to run the same goal on the
    # same spreadsheet agent's cell
    def run_entry
      entry = get_entry()
      output = '';
      @keys.keys.select { |k| @config['key_fields'][k] && @keys[k] }.each do |key|
        output += [ key, @keys[key] ].join(' ') + " "
      end

      unless entry
        $stderr.puts "#{ output } is not supported on #{ @page_name }" if @debug
        return
      end

      unless entry['ready'] == "1"
        $stderr.puts "#{ output } is not ready to run #{ @agent_name }" if @debug
        return false, entry
      end

      if entry['complete'] == "1"
        $stderr.puts "All goals are completed for #{ output }" if @debug
        return false, entry
      end

      if entry[@agent_name]
        (status, running_hostname) = entry[@agent_name].split(':')

        case status
        when 'r'
          $stderr.puts " #{ output } is already running #{ @agent_name } on #{ running_hostname }" if @debug
          return false, entry
        
        when "1"
          $stderr.puts " #{ output } has already run #{ @agent_name }" if @debug
          return false, entry

        when 'F'
          $stderr.puts " #{ output } has already Failed  #{ @agent_name }" if @debug
          return false, entry
        end
      end

      if @prerequisites
        @prerequisites.each do |prereq_field|
          unless entry[prereq_field] == "1"
            $stderr.puts " #{ output } has not finished #{ prereq_field }" if @debug
            return false, entry
          end
        end
      end

      # first attempt to set the hostname of the machine as the value of the agent
      hostname = Socket.gethostname;
      begin
        entry.update @agent_name => "r:#{ hostname }"
        @worksheet.save

      rescue GoogleDrive::Error
        # this is a collision, which is to be treated as if it is not runnable
        $stderr.puts " #{ output } lost #{ @agent_name } on #{hostname}" if @debug
        return false, entry
      end

      sleep 3
      begin
        @worksheet.reload
      rescue GoogleDrive::Error
        # this is a collision, which is to be treated as if it is not runnable
        $stderr.puts " #{ output } lost #{ @agent_name } on #{hostname}" if @debug
        return false, entry
      end

      check = entry[@agent_name]
      (status, running_hostname) = check.split(':')
      if hostname == running_hostname
        return true, entry
      end
      $stderr.puts " #{ output } lost #{ @agent_name } on #{hostname}" if @debug
      return false, entry
    end

    def complete_entry(update_entry)
      if update_entry.nil?
        update_entry = {}
      end
    
      if @subsumes && @subsumes.length > 0
        @subsumes.each do |subsumed_agent|
          update_entry[subsumed_agent] = 1
        end
      end

      update_entry[@agent_name] = 1
      entry = get_entry()
      entry.update update_entry
      @worksheet.save
    end

    def fail_entry(update_entry)
      if update_entry.nil?
        update_entry = { }
      end
      hostname = Socket.gethostname
      update_entry[@agent_name] = "F:#{ hostname }"
      entry = get_entry()
      entry.update update_entry
      @worksheet.save
    end

    def mail_error(error_message)
      output = ''
      @keys.keys.each do |key|
        output += [key, @keys[key] ].join(' ') + " "
      end

      prefix = [Socket.gethostname, output, @agent_name ].join(' ')
      begin
        Mail.defaults do
          delivery_method :smtp, {
            :address              => "smtp.gmail.com",
            :port                 => 587,
            :domain               => Socket.gethostname,
            :user_name            => @config['guser'],
            :password             => @config['gpass'],
            :authentication       => 'plain',
            :enable_starttls_auto => true  }
        end

        mail = Mail.new do
          from    @config['reply_email']
          to      @config['send_to']
          subject prefix
          body    error_message.to_s
        end

        mail.deliver!
      rescue
        #DO NOTHING
      end
    end
  end
end
