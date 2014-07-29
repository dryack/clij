#! /usr/local/opt/ruby193/bin/ruby
# *sigh*

require 'jenkins_api_client'
require 'yaml'
require 'net/https'
require 'optparse'
require 'cron2english'
require 'gli'
require './Logd'
require './clij-lib'

include GLI::App

program_desc 'Manage Jenkins via command line'
subcommand_option_handling :normal
sort_help :manually

config_file './.clij.rc'
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

def check_args(args,help_msg="job_name is required")
  @log.debug(args)
  if args.nil? || args.empty?
    help_now!(help_msg)
    return false
  else
    return true
  end
end

desc 'Work with jobs'
long_desc 'View information on or manipulate settings of jobs'
command :job do |c|
  c.desc 'List/find jobs managed by Jenkins'
  c.command :list do |list|
    list.desc 'List all jobs on the server'
    list.command :all do |all|
      all.action do |global_options, options, args|
        job_list_all()
      end
    end  # list all
    list.arg_name 'job_name'
    list.desc 'List all jobs containing job_name'
    list.action do |global_options, options, args|
      if check_args(args, "job_name is required, or try 'clij job list all'")
        job_search_name(args[0])
      end
    end  # list <search>
  end  # list
  c.desc 'View details about or manipulate job polling'
  c.command :poll do |poll|
    poll.arg_name 'job_name'
    poll.desc 'Examine the polling status of jobs'
    poll.command :status do |status|
      status.desc 'Print whether polling is enabled for each job on the server -- WARNING:  This is likely to fail on overburdened servers.'
      status.command :all do |all|
        all.action do |global_options, options, args|
          all_poll_status()
        end
      end  #  poll status all
      status.arg_name 'job_name'
      status.desc 'Show (detailed) infomations regarding the polling used by a job'
      status.switch [:d,:detailed], :desc => 'Provide detailed information on the polling', :default_value => false
      status.switch [:r,:parse], :desc => 'Attempt to provide english description of chrontab format', :defualt_value => false
      status.action do |global_options, options, args|
        if check_args(args, "job_name is required, or try 'clij job status all'")
          unless options[:detailed]
            request_type = 'basic'
            @log.debug("request_type 'basic'")
          else
            request_type = 'detailed'
            @log.debug("request_type 'detailed'")
          end
          job_poll_status(args[0], request_type)
          if options[:parse]
            parse_trigger_spec(args[0])  
          end
        end
      end  # poll status job_name
    end #  poll status 
    poll.arg_name 'job_name'
    poll.desc 'Backup the current polling information for job_name'
    poll.command :backup do |backup|
      backup.action do |global_options, options, args|
        if check_args(args)
          backup_trigger_spec(arg[0])
        end
      end
    end  # poll backup
    poll.desc "Revert the most recent clij-caused change to a job's polling data"
    poll.command :revert do |revert|
      revert.action do |global_options, options, args|
        if check_args(args)
          job_poll_revert(args[0])
        end
      end
    end  # poll revert
    poll.arg_name 'job_name "spec"'
    poll.desc 'Write a spec and/or comments to a job.  Old information is backed up automatically.'
    poll.command :write do |write|
      write.action do |global_options, options, args|
        if check_args(args)
          job_name = args.shift
          spec = args.join(" ")
          write_trigger_spec(job_name, spec)
        end
      end
    end  # poll write
  end  # poll
end  # job

pre do |global,command,options,arg|
  config_file = 'config.yml'
  #config_file '.clij.rc'
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
  @log.debug("Global options; #{global}")
  @log.debug("Options:  #{options}")
  @log.debug("Client options: #{client_opts}")
  @client = JenkinsApi::Client.new(client_opts)
end
exit run(ARGV)
#rescue Cron2English::ParseException => e
#  print e.inspect
#rescue Interrupt => e
#  print "\nclij:  user cancelled via Ctrl-C\n"
#
