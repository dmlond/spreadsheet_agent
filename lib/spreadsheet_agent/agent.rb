require 'spreadsheet_agent/db'

module SpreadsheetAgent

# @note The license of this source is "MIT Licence"
# SpreadsheetAgent::Agent is designed to make it easy to create a single task which connects to
# a field within a record on a page within the configured SpreadsheetAgent compatible Google Spreadsheet,
# runs supplied code, and reports whether the job completed or ended in error.  An agent can be configured
# to only run when certain prerequisite fields have completed.  The data in these fields can be filled in by
# other SpreadsheetAgent::Agents, SpreadsheetAgent::Runners, or humans.  Compute node configuration is available
# to prevent the agent from running more than a certain number of instances of itself, or not run if certain
# other agents or processes are running on the node.  Finally, an agent can be configured to subsume another
# agent, and fill in the completion field for that agent in addition to its own when it completes successfully.
# @author Darin London Copyright 2013
  class Agent < SpreadsheetAgent::Db

# The name of the field in the page to which the agent should report status
# @return [String]
    attr_accessor :agent_name

# The name of the Page on the Google Spreadsheet that contains the record to be worked on by the agent
# @return [String]
    attr_accessor :page_name

# Hash used to find the entry on the Google Spreadsheet Worksheet
# Keys are defined in config/agent.conf.yml.
# All keys configured as 'required: 1' must be included in the keys hash.
# Values specify values for those fields in the record on the page for which the agent is running.
# @return [Hash]
    attr_accessor :keys

# Specify whether to print debug information (default false).
# When true, the agent code will print verbosely to STDERR.  When false, and the process!
# returns a failure status, the agent will email all stdout and stderr to the email specified in the
# :config send_to value
# @return [Boolean]
    attr_accessor :debug

# Optional array of prerequisites.
# If supplied, each entry is treated as a field name on the Google Worksheet which must contain a 1 in it for the record on the page before
# this agent will attempt to run.
# @return [Array]
    attr_accessor :prerequisites

# @note This works on Linux with ps.
# Maximum number of instances of this agent to run on any particular server.
# If specified, newly instantiated agents will not attempt to run process! if
# there are max_selves instances already running on the same server.  If not
# specified, all instances will attempt to run.
# @return [Integer]
    attr_accessor :max_selves

# @note This works on Linux with ps.
# List of other processes, and the maximum number of running instances of the process that are allowed before this agent should avoid running on the given server.
# Hash of process_name => number of max_instances. If specified, each key is treated as a process name in ps.  If the agent detects the specified number of
# max_instances of the given process (based on a line match), it will not attempt to run.  If not specified, it will run regardless of the other processes
# already running on a server. 
# @return [Hash]
    attr_accessor :conflicts_with

# List of fields (agent or otherwise) that this agent should also complete when it completes successfully.
# Each entry is treated as a fields on the record which this agent subsumes.  If the agent completes successfully these
# fields will be updated with a 1 in addition to the field for the agent.
# @return [Array]
    attr_accessor :subsumes

# The GoogleDrive::Worksheet[http://rubydoc.info/gems/google_drive/0.3.6/GoogleDrive/Worksheet] that is being access by the agent.
# @return [GoogleDrive::Worksheet]
    attr_reader :worksheet

# create a new SpreadsheetAgent::Agent
# @param [String] agent_name REQUIRED
# @param [String] page_name REQUIRED
# @param [Hash] keys REQUIRED
# @param [String] config_file (see SpreadsheetAgent::DB)
# @param [Boolean] debug
# @param [Array] prerequisites
# @param [Integer] max_selves
# @param [Hash] conflicts_with
# @param [Array] subsumes
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
# and if the entry is ready (field 'ready' has a 1), and any supplied prerequisite fields have a 1,
# gets the GoogleDrive::List[http://rubydoc.info/gems/google_drive/0.3.6/GoogleDrive/List] record, and
# passes it to the supplied Proc. This PROC must return a required boolean field indicating success or failure,
# and an optional hash of key - value fields that will be updated on the GoogleDrive::List record.  Note, the updates
# are made regardless of the value of success.  In fact, the agent can be configured to update
# different fields based on success or failure.   Also, note that any value can be stored in the
# hash.  This allows the agent to communicate any useful information to the google spreadsheet for other
# agents (SpreadsheetAgent::Agent, SpreadsheetAgent::Runner, or human) to use. The Proc must try at all
# costs to avoid terminating. If an error is encountered, it should return false for the success field
# to signal that the process failed.  If no errors are encountered it should return true for the success
# field.
#
# @example Exit successfully, enters a 1 in the agent_name field
#   $agent->process! do |entry|
#     true
#   end
#
# @example Same, but also updates the 'notice' field in the record along with the 1 in the agent_name field
#   $agent->process! do |entry|
#     [true, {:notice => 'There were 30 files processed'}]
#   end
#
# @example Fails, enters f:#{hostname} in the agent_name field
#   $agent->process! do |entry|
#     false
#
# @example Same, but also updates the 'notice' field in the record along with the failure notice
#   $agent->process! do |entry|
#     [false, {:notice => 'There were 10 files left to process!' }]
#   end
#
# @example This agent passes different parameters based on success or failure
#   $agent->process! do |entry|
#     if $success
#       true
#     else
#       [ false, {:notice => 'there were 10 remaining files'}]
#     end
#   end
#
# @param [Proc] Code to process entry
# @yieldparam [GoogleDrive::List] entry
# @yieldreturn [Boolean, Hash] success, (optional) hash of fields to update and values to update on the fields
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

# The GoogleDrive::List[http://rubydoc.info/gems/google_drive/0.3.6/GoogleDrive/List] for the specified keys
# @return [GoogleDrive::List]
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

  end #SpreadsheetAgent::Agent
end #SpreadsheetAgent
