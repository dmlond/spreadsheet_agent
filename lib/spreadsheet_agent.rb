# Author: Darin London
# The license of this source is "New BSD Licence"

require 'spreadsheet_agent/db'
require 'socket'
require 'open3'
require 'capture_io'
require 'mail'

module SpreadsheetAgent

  class Agent < SpreadsheetAgent::Db

    attr_accessor :agent_name, :page_name, :keys, :debug, :prerequisites, :debug, :max_selves, :conflicts_with,  :subsumes
    attr_reader :worksheet

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
