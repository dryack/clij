require 'jenkins_api_client'
require 'yaml'
require 'net/https'
require 'optparse'
require 'cron2english'
require 'gli'

include GLI::App

##############################################################################
#
# clij [options] command [jobname]
# 
# (-a, --all): modifies the command to the all verison (poll_status, poll_off,
#              poll_revert)
# (
##############################################################################

program_desc 'Manage Jenkins polling via command line'
subcommand_option_handling :normal

desc 'List jobs in Jenkins'
long_desc <<EOS
List jobs in Jenkins matching the argument given.  Use 'all' to list all jobs being managed by Jenkins
EOS
arg_name 'job_name', :optional
command :list do |c|
  c.desc 'List all jobs managed by Jenkins'
  c.command :all do |all|
    all.action do |global_options,options,args|
     job_list_all()
    end
  end
  c.action do |global_options,options,args|
    job_search_name(args[0])
  end
end

desc 'Show or manipulate job polling status'
long_desc <<EOS
Show the existence of, detailed information on, or manipulate the polling status of jobs being
managed by Jenkins
EOS
arg_name 'job_name', :optional
command :poll do |c|
  c.command :status do |status|
    status.command :all do |all|
      all.action do |global_options,options,args|
        all_poll_status()
      end
    end
    status.switch [:d,:detailed], :default_value => false
    status.action do |global_options,options,args|
      unless options[:detailed] == true
        request_type = 'basic'
      else
        request_type = 'detailed'
      end
      p args
      p request_type
      job_poll_status(args[0], request_type)
    end
  end
end



def all_poll_status()
  j = 0
  @client.job.list_all.each do |x|
    begin
      if x == "BASE_JAVA_JOB" || x == "FAMC"
        next
      else
        print x, " => "
#       puts @client.job.get_config(x).include?('SCMTrigger')
        puts @client.job.get_config(x).include?('spec')
      end
    rescue => e
      print "..."
      puts e
      sleep(6)
      retry
    end
  end
end

def all_poll_off()
# will actually set all to poll once per month, spread out across the month
# unless overridden?  maybe?
# probably just call job_poll_change() with a hardcoded approach?
end

def all_poll_revert() # possibly needed counterpart to above?
end

def job_poll_status(job, request_type='basic')
# will check the poll status for a given job:
# basic:  yes or no
# detailed:  returns "no" or "yes, <details> <if there are old details that can be
# reverted to>"
  if request_type == 'detailed'
    if @client.job.get_config(job).include?('SCMTrigger')
      puts "Active Polling found: "
      puts "----------------------"
      @doc = get_trigger_spec(job)
      puts @doc.xpath("//spec").to_s.gsub!(/<\/?spec>/,'')
      puts ""
    else 
      puts "No polling found for job #{job}."
      puts ""
    end
  elsif request_type.nil? || request_type == 'basic'
    puts @client.job.get_config(job).include?('SCMTrigger')
  else 
    p "Error:  Unsupported option in job_poll_status"
  end
end

def job_poll_change(job, poll_details)
# will change the poll frequency to those selected by the user; will then use
# comments to store the old settings and warn off manual editors from
# changing/removing them
end

def job_poll_revert(job)
# will revert to the saved poll settings found in the comments, and then delete
# the programmed comments; returns an error if nothing is found
# error if none found
  doc = config_obtain(job)
  if doc.search('spec').empty?
    puts "#{job} is not set up for polling"
  elsif doc.search('spec').grep(/#{@CLIJ_MSG_HEADER}/).empty?
    puts "#{job} is not being managed by clij, or has already been reverted"
  else
    polling = doc.at_css "spec"
    polling.content = polling.content.gsub!(@CLIJ_MSG_HEADER, "").chomp
    polling.content = polling.content.gsub!(/\n#/, "\n")
    @client.job.update(job, doc.to_xml)
  end
rescue Timeout::Error => e
  retry
end

def parse_trigger_spec(job)
# will make sense of <hudson.triggers.SCMTrigger><spec>
  @doc = config_obtain(job)
  @doc = @doc.search('spec').to_s.gsub!(/<\/?spec>/,'')
  unless @doc.to_s.empty?
    puts "#{job} polling schedule:"
    @doc.each_line.to_a.each do |x|
      unless x.start_with?('#')
        puts x
        puts Cron2English.parse(x.gsub(/H/,'*').gsub(/,0-/,',00-'))
        puts ""
      end
    end
  else
    puts "#{job} has no polling schedule!"
  end
end

def get_trigger_spec(job)
  Nokogiri::XML(@client.job.get_config(job))
end

def write_trigger_spec(spec)
# will write a spec to <hudson.triggers.SCMTrigger><spec>
end

def backup_trigger_spec(job)
# will take the current trigger spec and comment it out in such a way as to
# warn manual editors away from it - and ensure the program can find it and
# uncomment it when required
  doc = config_obtain(job)
  if doc.search('spec').empty?
    puts "#{job} doesn't have polling set in its configuration."
  else
    polling = doc.at_css "spec"
    polling.content = "#{@CLIJ_MSG_HEADER}\n" + polling.content.split("\n").map {|y| "#" + y}.join("\n")
    @client.job.update(job, doc.to_xml)
  end
rescue Timeout::Error => e
  retry
end

def job_list_all()
  # obtain a list of every job on the jenkins server
  puts @client.job.list_all
end

def job_search_name(partial_name)
  # use regex to match partial_name and output to user
  to_filter = "#{partial_name}"
  filtered_list = @client.job.list(to_filter)
  if filtered_list.nil? || filtered_list == []
    puts "Nothing found matching '#{partial_name}'"
  else
    puts filtered_list
  end
rescue Timeout::Error => e
  puts "#{e} waiting on job.list(#{to_filter})"
  Basic_Retry_On_Error()
  #@client.job.list(to_filter)
  retry
end

def config_obtain(job)
  Nokogiri::XML.fragment(@client.job.get_config(job))
end

###########################
def main()
  exit run(ARGV)
rescue Cron2English::ParseException => e
  print e.inspect
#rescue Interrupt => e
#  print "\nclij:  user cancelled via Ctrl-C\n"
end

begin
  config_file = 'config.yml'
  verify_mode = OpenSSL::SSL::VERIFY_NONE
  #ssl_version = :TLSv1
  open_timeout = 2
  continue_timeout = 2
  client_opts = YAML.load_file(File.expand_path(config_file))
  unless client_opts.has_key?(:msg_header)
    @CLIJ_MSG_HEADER = "### WARNING: This field is being managed, in part, by clij.\n### Manual changes are discouraged.\n"
    else
      @CLIJ_MSG_HEADER = client_opts[:msg_header]
  end
  @client = JenkinsApi::Client.new(client_opts)
  main()
end
