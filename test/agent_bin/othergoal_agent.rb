#!/usr/bin/env ruby
$:.unshift( File.expand_path( File.dirname(__FILE__) + '/../../lib' ) )
require 'spreadsheet_agent'

page, entry = ARGV

google_agent = SpreadsheetAgent::Agent.new({
                                      :agent_name => File.basename($0).sub('_agent.rb',''),
                                      :config_file => File.expand_path( File.dirname(__FILE__) + '/../../config/agent.conf.yml' ),
                                      :page_name => page,
                                      :keys => { 'testentry' => entry, 'testpage' => page }
                                    })

google_agent.process! do |entry|
  true
end
exit
