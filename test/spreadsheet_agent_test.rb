require 'test/unit'
require 'shoulda/context'
require 'spreadsheet_agent'
require 'google_drive'
require 'psych'
require 'socket'

class TC_SpreadsheetAgentTest < Test::Unit::TestCase

  context 'Agent' do

    setup do
      @config_file = File.expand_path(File.dirname( $0 )) + '/../config/agent.conf.yml'

      unless File.exists? @config_file
        $stderr.puts "You must create a valid test Google Spreadsheet and a valid #{ @config_file } configuration file pointing to it to run the tests. See README.txt file for more information on how to run the tests."
        exit(1)
      end
    
      @config = Psych.load_file(@config_file)

      @testing_page_name = 'testing'
      @keys = { 'testentry' => 'test', 'testpage' => @testing_page_name }
      @testing_page = nil
    end

    teardown do
      unless @testing_page.nil?
        @testing_page.max_rows = 1
        colnum = 1
        while colnum <= @testing_page.num_cols
          @testing_page[1,colnum] = nil
          colnum += 1
        end
        @testing_page.save
      end
    end

    context 'instantiated' do

      should 'be a SpreadsheetAgent::Agent' do
        google_agent = SpreadsheetAgent::Agent.new(
                                            :agent_name => 'instantiate',
                                            :page_name => @testing_page_name,
                                            :keys => @keys
                                            )
        assert_not_nil google_agent, 'google_agent is nil!'
        assert_instance_of(SpreadsheetAgent::Agent, google_agent)
      end

    end #instantiated
  
    context 'that is not ready' do

      setup do
        @agent_name = 'donotrun'
        @google_agent = prepare_google_agent_for(@agent_name, false)
      end
    
      should 'return true from process! but not run the supplied code' do
        subroutine_ran = false
        process_ran = @google_agent.process! do |entry|
          # this should not run at all
          subroutine_ran = true
          true
        end
        assert process_ran, 'process! should return true'
        assert !subroutine_ran, 'The subref should not have run at all'
        entry = @google_agent.get_entry
        assert entry[@agent_name].empty?, "#{ @agent_name } field should still be empty"
      end
      
    end #that is not ready

    context 'that is ready' do

      setup do
        @agent_name = 'readytorun'
        @google_agent = prepare_google_agent_for(@agent_name, true)
      end
    
      should 'return true from process!, run passing code, and complete the agent_name field' do
        subroutine_ran = false
        process_ran = @google_agent.process! do |entry|
          subroutine_ran = true
          true
        end

        assert process_ran, 'process should return true'
        assert subroutine_ran, 'The subref should have run'
        entry = @google_agent.get_entry
        assert_equal "1", entry[@agent_name], "#{ @agent_name } field should have completed successfully"
      end

      should 'return true from process!, run failing code, and Fail the agent_name field' do
        subroutine_ran = false
        process_ran = @google_agent.process! do |entry|
          subroutine_ran = true
          false
        end

        assert process_ran, 'process should return true'
        assert subroutine_ran, 'The subref should have run'
        entry = @google_agent.get_entry
        expected_field_value = ['F', Socket.gethostname].join(':')
        assert_equal expected_field_value, entry[@agent_name], "#{ @agent_name } field should have failed with #{ expected_field_value}, was #{ entry[@agent_name] }"
      end

      should 'be able to update cell contents on success' do
        updated_cell_name = 'updatevalue'
        updated_cell_value = 'iamupdated';
        add_header_to_page(updated_cell_name, @testing_page)
        subroutine_ran = false

        process_ran = @google_agent.process! do |entry|
          subroutine_ran = true
          [true, { updated_cell_name => updated_cell_value }]
        end

        assert process_ran, 'process should return true'
        assert subroutine_ran, 'The subref should have run'
        entry = @google_agent.get_entry
        assert_equal "1", entry[@agent_name], "#{ @agent_name } field should have completed successfully"
        assert_equal updated_cell_value, entry[updated_cell_name]
      end

    end #that is ready

    context 'that requires a prerequisite' do

      setup do
        @agent_name = 'readyifprereq'
        @prerequisite_cell_name = 'prerequisitecell'
        @prerequisites = [ @prerequisite_cell_name ]
        @google_agent = prepare_google_agent_for(@agent_name, true, nil, { :prerequisites => @prerequisites } )
        add_header_to_page(@prerequisite_cell_name, @testing_page)
      end

      should 'set prerequisites on agent' do
        assert_not_nil @google_agent.prerequisites
        assert_equal @prerequisites.count, @google_agent.prerequisites.count
        @prerequisites.each do |prereq|
          assert @google_agent.prerequisites.include?(prereq), "#{ prereq } should be a prerequisite"
        end
      end
      
      should 'not run if prerequisite has not run' do
        entry = @google_agent.get_entry
        assert entry[@prerequisite_cell_name].empty?, "#{ @prerequisite_cell_name } is #{ entry[@prerequisite_cell_name] } but should be empty!"

        subroutine_ran = false
        process_ran = @google_agent.process! do |entry|
          # this should not run at all
          subroutine_ran = true
          true
        end

        assert process_ran, 'process! should return true'
        assert !subroutine_ran, 'The subref should not have run at all'
        entry = @google_agent.get_entry
        assert entry[@agent_name].empty?, "#{ @agent_name } field should still be empty"
      end

      should 'not run if prerequisite has failed' do
        failed_value = ['F', Socket.gethostname].join(':')
        entry = @google_agent.get_entry
        entry.update(@prerequisite_cell_name => failed_value)
        @testing_page.save

        subroutine_ran = false
        process_ran = @google_agent.process! do |entry|
          # this should not run at all
          subroutine_ran = true
          true
        end

        assert process_ran, 'process! should return true'
        assert !subroutine_ran, 'The subref should not have run at all'
        entry = @google_agent.get_entry
        assert_equal failed_value, entry[@prerequisite_cell_name]
        assert entry[@agent_name].empty?, "#{ @agent_name } field should still be empty"
      end

      should 'run if prerequisite has run successfully' do
        success_value = "1"
        entry = @google_agent.get_entry
        entry.update( @prerequisite_cell_name => success_value )
        @testing_page.save

        subroutine_ran = false
        process_ran = @google_agent.process! do |entry|
          subroutine_ran = true
          true
        end

        assert process_ran, 'process! should return true'
        assert subroutine_ran, 'The subref should have run'
        entry = @google_agent.get_entry
        assert_equal success_value, entry[@prerequisite_cell_name]
        assert_equal "1", entry[@agent_name]
      end
      
    end #that requires a prerequisite

    context 'max_selves' do
      setup do
        @agent_name = 'maxselftest'
        @allowed_selves = 3
        @google_agents = { }
        row = 2
        4.times do
          @keys['testentry'] = "test#{ row }"
          @google_agents[@keys['testentry']] = prepare_google_agent_for(@agent_name, true, row, { :max_selves => @allowed_selves } )
          row += 1
        end
        @command = 'ruby -e ' + "'" + '$0 = "%s"; sleep 120;' + "'"
        @command %= File.basename $0
      end

      should 'set max_selves on agent' do
        row = 2
        4.times do
          assert_not_nil @google_agents["test#{ row }"].max_selves
          assert_equal @allowed_selves, @google_agents["test#{ row }"].max_selves
          row += 1
        end
      end

      should 'not allow more than max_selves agents of the same name to run' do
        row = 2
        num_running = 0
        @allowed_selves.times do
          assert num_running < @google_agents[ "test#{ row }" ].max_selves, "#{ num_running } is greater than #{ @google_agents[ "test#{ row }" ].max_selves }!"
          
          subroutine_ran = false
          process_ran = @google_agents[ "test#{ row }" ].process! do |entry|
            subroutine_ran = true
            true
          end

          assert process_ran, 'process should return true'
          assert subroutine_ran, 'The subref should have run'
          entry = @google_agents[ "test#{ row }" ].get_entry
          assert_equal "1", entry[@agent_name], "#{ @agent_name } field should have completed successfully"

          system("#{ @command } &")
          row += 1
          num_running += 1 
        end
        assert_equal num_running, @google_agents[ "test#{ row }" ].max_selves

        subroutine_ran = false
        process_ran = @google_agents[ "test#{ row }" ].process! do |entry|
          subroutine_ran = true
          true
        end

        assert process_ran, 'process should return true'
        assert !subroutine_ran, 'The subref should not have run'
        entry = @google_agents[ "test#{ row }" ].get_entry
        assert entry[@agent_name].empty?, "#{ @agent_name } field should still be empty"
      end
      
    end #max_selves

    context 'conflicts_with' do

      setup do
        @agent_name = 'conflictswithtest'
        @max_conflicters = 2
        @conflicting_script = 'conflicting_agent.rb'
        @conflicts_with = { @conflicting_script => @max_conflicters }
        @google_agent = prepare_google_agent_for(@agent_name, true, nil, { :conflicts_with => @conflicts_with } )
        @command = 'ruby -e ' + "'" + '$0 = "%s"; sleep 60;' + "'"
        @command %= @conflicting_script
      end

      should 'set conflicts_with on agent' do
        assert_not_nil @google_agent.conflicts_with
        assert @google_agent.conflicts_with.has_key? @conflicting_script
        assert_equal @max_conflicters, @google_agent.conflicts_with[@conflicting_script]
      end

      should 'only run if a sufficiently low number of conflicting scripts are running' do
        num_running = 0
        @max_conflicters.times do
          system("#{ @command } &")
          num_running += 1
          
          subroutine_ran = false
          process_ran = @google_agent.process! do |entry|
            subroutine_ran = true
            true
          end
          assert process_ran, 'process should return true'
          entry = @google_agent.get_entry
          
          if num_running < @google_agent.conflicts_with[@conflicting_script]
            assert subroutine_ran, "The subref should have run on the #{ num_running }th time"
            assert_equal "1", entry[@agent_name], "#{ @agent_name } field should have completed successfully"
          else
            assert !subroutine_ran, 'The subref should not have run'
            assert entry[@agent_name].empty?, "#{ @agent_name } field should still be empty, got #{ entry[@agent_name ] }"
          end
          
          @testing_page[2,4] = nil
          @testing_page.save    
        end
        assert_equal num_running, @google_agent.conflicts_with[@conflicting_script]
      end
      
    end #conflicts_with

    context 'subsumes' do
      setup do
        @agent_name = 'subsumingagent'
        @subsumed_cell_name = 'subsumedcell'
        @subsumes = [ @subsumed_cell_name ]
        @google_agent = prepare_google_agent_for(@agent_name, true, nil, { :subsumes => @subsumes } )
        add_header_to_page(@subsumed_cell_name, @testing_page)
      end

      should 'set subsumes on agent' do
        assert_not_nil @google_agent.subsumes
        assert_equal @subsumes.count, @google_agent.subsumes.count
        @subsumes.each do |subsumed|
          assert @google_agent.subsumes.include?(subsumed), "#{ subsumed } should be a a subsumed field"
        end
      end

      should 'update subsumed cell if run completes successfully' do
        entry = @google_agent.get_entry
        assert entry[@agent_name].empty?, "#{ @agent_name } field should be empty"
        assert entry[@subsumed_cell_name].empty?, "#{ @subsumed_cell_name } field should be empty"
        
        success_value = "1"
        subroutine_ran = false
        process_ran = @google_agent.process! do |entry|
          # this should not run at all
          subroutine_ran = true
          true
        end

        assert process_ran, 'process! should return true'
        assert subroutine_ran, 'The subref should have run'
        entry = @google_agent.get_entry
        assert_equal success_value, entry[@agent_name]
        assert_equal success_value, entry[@subsumed_cell_name]
      end

    end #subsumes

    context 'config_file' do

      setup do
        @agent_name = 'configagent'
        @test_config_file = File.expand_path( File.dirname(__FILE__) + '/../config/test.config.yml' )
      end

      should 'be overridable' do
        assert File.exists?(@test_config_file), "#{ @test_config_file } does not exist!"
        test_config = Psych.load_file(@test_config_file)
        @google_agent = prepare_google_agent_for(@agent_name, true, nil, { :config_file => @test_config_file } )
        assert_equal @test_config_file, @google_agent.config_file
        test_config.keys.each do |tkey|
          assert @google_agent.config.has_key? tkey
          assert_equal test_config[tkey], @google_agent.config[tkey]
        end
      end
      
   end #config_file
    
  end #Agent

  def prepare_google_agent_for(agent, ready, agent_row = nil, extra_params = nil)
    init_params = {
      :agent_name => agent,
      :page_name => @testing_page_name,
      :keys => @keys,
      :debug => true
    }
    unless extra_params.nil?
      init_params.merge!(extra_params)
    end

    google_agent = SpreadsheetAgent::Agent.new(init_params)
    @testing_page = google_agent.worksheet

    colnum = 1
    ['testentry','testpage','ready', agent, 'complete'].each do |field|
      @testing_page[1,colnum] = field
      colnum += 1
    end
    if agent_row.nil?
      agent_row = 2
    end

    @testing_page[agent_row,1] = @keys['testentry']
    @testing_page[agent_row,2] = @keys['testpage']
    @testing_page[agent_row,3] = "1" if ready
    @testing_page.save
    google_agent
  end

  def add_header_to_page(header, page)
    page[1, page.num_cols + 1] = header
    page.save
  end

end #TC_SpreadsheetAgentTest
