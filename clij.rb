#! /usr/local/opt/ruby193/bin/ruby
# *sigh*

require 'jenkins_api_client'
require 'yaml'
require 'net/https'
require 'optparse'
require 'cron2english'
require 'gli'
require './Logd'

include GLI::App

program_desc 'Manage Jenkins polling via command line'
subcommand_option_handling :normal
sort_help :manually

config_file '.clij.rc'
flag [:u, :username], :arg_name => 'user', :desc => 'Jenkins server username'
flag [:p, :password], :arg_name => 'password', :mask => true, :desc => 'Jenkins server password'
flag :i, :arg_name => 'ip_address', :desc => 'Jenkins server IP address', :must_match => /\d+\.\d+\.\d+\.\d+/
flag [:n, :port], :arg_name => 'port_number', :desc => 'Port number used by Jenkins', :default => '8080', :must_match => /\d+/
flag [:l, :logname], :arg_name => 'log-file-name', :desc => 'Log all output to log-file-name'
flag [:j, :path], :arg_name => 'path_to_jenkins', :desc => 'Path to Jenkins', :default => '/'
flag [:g, :log_level], :arg_name => 'level', :desc => 'Jenkins API Log Levels to view/log', :must_match => { "debug" => 1,
                                                                                                             "info"  => 2,
                                                                                                             "warn"  => 3,
                                                                                                             "error" => 4,
                                                                                                             "fatal" => 5}
flag :header, :arg_name => 'clij message header', :desc => 'Header used by clij to identify its management of a field in Jenkins'
switch :ssl, :desc => 'Use SSL to connect to Jenkins'
switch :o, :desc => 'Send output to STDOUT', :default_value => true, :negatable => true

desc 'List jobs in Jenkins'
long_desc <<EOS
List jobs in Jenkins matching the argument given.  Use 'all' to list all jobs being managed by Jenkins
EOS
arg_name 'job_name'
command :list do |c|
  c.desc 'List all jobs managed by Jenkins'
  c.command :all do |all|
    all.action do |global_options,options,args|
     job_list_all()
    end
  end
  c.desc 'List all jobs containing job_name'
  c.action do |global_options,options,args|
    if args[0].nil?
      help_now!("job_name is required, or try 'clij list all'")
    end
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
      job_poll_status(args[0], request_type)
    end
  end
  c.desc 'Manipulate the trigger of Jenkins managed jobs that use polling'
  c.command :spec do |spec|
    arg_name 'job_name spec'
    spec.desc 'Write a new spec, while backing up the old one'
    spec.command :write do |write|
      write.action do |gobal_options, options, args|
        job_name = args.shift
        spec = args.join(" ")
        write_trigger_spec(job_name, spec)
      nd
    end
    spec.desc 'Back up the current polling trigger spec of a job'
    spec.command :backup do |backup|
      backup.action do |global_options, options, args|
        backup_trigger_spec(args[0])
      end
    end
    spec.desc 'Print the current polling trigger spec in a readable format'
    spec.command :parse do |parse|
      parse.action do |global_options, options, args|
        parse_trigger_spec(args[0])
      end
    end
    spec.desc "Revert a job's polling trigger spec to its original state"
    spec.command :revert do |revert|
      revert.action do |global_options, options, args|
        job_poll_revert(args[0])
      end
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
      @log.info "Active Polling found: "
      @log.info "----------------------"
      @doc = get_trigger_spec(job)
      @log.info(@doc.xpath("//spec").to_s.gsub!(/<\/?spec>/,''))
      #puts ""
    else 
      @log.info "No polling found for job #{job}."
      #puts ""
    end
  elsif request_type.nil? || request_type == 'basic'
    @log.info(@client.job.get_config(job).include?('SCMTrigger'))
  else 
    @log.error "Unsupported option in job_poll_status"
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

def write_trigger_spec(job, spec)
# will write a spec to <hudson.triggers.SCMTrigger><spec>
  doc = config_obtain(job)
  if doc.search('spec').empty?
    puts "#{job} doesn't have polling set in its configuration."
  else
    polling = doc.at_css "spec"
    unless polling.content.include?(@CLIJ_MSG_HEADER)
      polling.content = "#{@CLIJ_MSG_HEADER}\n" + "#{spec}" + polling.content.split("\n").map {|y| "#" + y}.join("\n")
    else
      polling.content = "#{spec}" + polling.content.split("\n").map {|y| "#" +y}.join("\n")
    end
    @client.job.update(job, doc.to_xml)
  end
rescue Timeout::Error
  logger.error "Timeout while writing to #{job}"
  retry
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
rescue Timeout::Error
  logger.error "Timeout while backing up polling spec on #{job}"
  retry
end

def job_list_all()
  # obtain a list of every job on the jenkins server
  log.infoi(@client.job.list_all)
end

def job_search_name(partial_name)
  # use regex to match partial_name and output to user
  to_filter = "#{partial_name}"
  filtered_list = @client.job.list(to_filter)
  if filtered_list.nil? || filtered_list == []
    log.info "Nothing found matching '#{partial_name}'"
  else
    @log.info(filtered_list)
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

pre do |global,command,options,arg|
  #config_file = 'config.yml'


  verify_mode = OpenSSL::SSL::VERIFY_NONE
  #ssl_version = :TLSv1
  open_timeout = 2
  continue_timeout = 2
  @log = Logger.new(STDOUT)

  client_opts = YAML.load_file(File.expand_path(config_file))
  if global[:logname]
    @log.attach(global[:logname])
    client_opts[:log_location] = global[:logname]
  end
  unless client_opts.has_key?(:msg_header)
    @CLIJ_MSG_HEADER = "### WARNING: This field is being managed, in part, by clij.\n### Manual changes are discouraged.\n"
  else
      @CLIJ_MSG_HEADER = client_opts[:msg_header]
  end
  @Log.debug(client_opts)
  @client = JenkinsApi::Client.new(client_opts)
end

exit run(ARGV)
#rescue Cron2English::ParseException => e
#  print e.inspect
#rescue Interrupt => e
#  print "\nclij:  user cancelled via Ctrl-C\n"
