require 'jenkins_api_client'
require 'net/https'
require 'cron2english'
require './Logd'

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
  @doc = get_trigger_spec(job)
  if request_type == 'detailed'
    if @doc.to_s.include?('spec')
      @log.info "Active Polling found: "
      @log.info "----------------------"
      @log.info(@doc.xpath("//spec").to_s.gsub!(/<\/?[[:alpha:]]+>/,''))
    else 
      @log.info "No polling found for job #{job}."
    end
  elsif request_type.nil? || request_type == 'basic'
    @log.info(@doc.to_s.include?('spec'))
  else 
    @log.error "Unsupported option in job_poll_status"
  end
end

def job_build_status(job)
# will check to see if 'Discard Old Builds' is checked
# and if so, the details of the setting(s)
  @doc = get_trigger_spec(job)
  @log.debug(@doc)
  if @doc.to_s.include?('logRotator')
    @log.info("days to keep: #{@doc.xpath("//daysToKeep").to_s.gsub!(/<\/?[[:alpha:]]+>/,'')}")
    @log.info("num to keep: #{@doc.xpath("//numToKeep").to_s.gsub!(/<\/?[[:alpha:]]+>/,'')}")
    @log.info("artifacts days to keep: #{@doc.xpath("//artifactDaysToKeep").to_s.gsub!(/<\/?[[:alpha:]]+>/,'')}")
    @log.info("artifacts num to keep: #{@doc.xpath("//artifactNumToKeep").to_s.gsub!(/<\/?[[:alpha:]]+>/,'')}")
  else
    @log.info "'Discard Old Builds' is not checked for #{job}"
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

def job_discard_off(job)
  @log.debug("entering job_discard_off()")
  doc = Nokogiri::XML(@client.job.get_config(job))
  @log.debug("got config as doc")
  if doc.search('logRotator').empty?
   job_discard_create(job, -1, -1, -1, -1) 
  else
    job_discard_change(job, -1, -1, -1, -1)
  end
end

def job_discard_on(job, daystokeep, numtokeep, adaystokeep, anumtokeep)
  doc = Nokogiri::XML.parse(@client.job.get_config(job))
  if doc.search('logRotator').empty?
    job_discard_create(job, daystokeep, numtokeep, adaystokeep, anumtokeep)
  else
    job_discard_change(job, daystokeep, numtokeep, adaystokeep, anumtokeep)
  end
end

def job_discard_change(job, daystokeep, numtokeep, artifactdaystokeep, artifactnumtokeep)
  doc = Nokogiri::XML.parse(@client.job.get_config(job))
  days = doc.at_css "daysToKeep"
  num = doc.at_css "numToKeep"
  artday = doc.at_css "artifactDaysToKeep"
  artnum = doc.at_css "artifactNumToKeep"
  days.content = daystokeep
  num.content = numtokeep
  artday.content = artifactdaystokeep
  artnum.content = artifactnumtokeep
  @client.job.update(job, doc.to_xml)
end

def all_discard_off()
  @client.job.list_all.each { |job| job_discard_off(job) }
end

def job_discard_create(job, daystokeep="-1", numtokeep="5", artifactdaystokeep="-1", artifactnumtokeep="-1")
  doc = Nokogiri::XML.parse(@client.job.get_config(job))
  root = doc.root
  @log.debug("config obtained")
  node = Nokogiri::XML::Node.new('logRotator', root)
  @log.debug("node logRotator created")
  node_days_to_keep = Nokogiri::XML::Node.new('daysToKeep', root)
  @log.debug("node logRotator child daysToKeep created")
  node_num_to_keep = Nokogiri::XML::Node.new('numToKeep', root)
  @log.debug("node logRotator child numToKeep created")
  a_node_days_to_keep = Nokogiri::XML::Node.new('artifactDaysToKeep', root)
  @log.debug("node logRotator child artifactDaysToKeep created")
  a_node_num_to_keep = Nokogiri::XML::Node.new('artifactNumToKeep', root)
  @log.debug("node logRotator child artifactNumToKeep created")
  node['class'] = 'hudson.tasks.LogRotator'
  @log.debug("node keys written")
  node_days_to_keep.content = daystokeep
  node_num_to_keep.content = numtokeep
  a_node_days_to_keep.content = artifactdaystokeep
  a_node_num_to_keep.content = artifactnumtokeep
  @log.debug("child nodes created and populated")
  node.add_child(node_days_to_keep)
  node.add_child(node_num_to_keep)
  node.add_child(a_node_days_to_keep)
  node.add_child(a_node_num_to_keep)
  node.parent = root
  @client.job.update(job, doc.to_xml)
end

def all_discard_on(daystokeep = "-1", numtokeep = "-1", artifactdaystokeep = "-1", artifactnumtokeep = "-1")
  @client.job.list_all.each { |job| job_discard_on(daystokeep, numtokeep, artifactdaystokeep, artifactnumtokeep) }
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
  @log.info(@client.job.list_all)
end

def job_search_name(partial_name)
  # use regex to match partial_name and output to user
  to_filter = "#{partial_name}"
  filtered_list = @client.job.list(to_filter)
  if filtered_list.nil? || filtered_list == []
    @log.info "Nothing found matching '#{partial_name}'"
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
