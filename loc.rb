# frozen_string_literal: true

require 'octokit'
require 'open3'
require 'cliver'
require 'fileutils'
require 'dotenv'

if ARGV.count != 1
  puts 'Usage: script/count [ORG NAME]'
  exit 1
end

Dotenv.load

def cloc(*args)
  cloc_path = Cliver.detect! 'cloc'
  Open3.capture2e(cloc_path, *args)
end

tmp_dir = File.expand_path './tmp', File.dirname(__FILE__)
FileUtils.rm_rf tmp_dir
FileUtils.mkdir_p tmp_dir

# Enabling support for GitHub Enterprise
unless ENV['GITHUB_ENTERPRISE_URL'].nil?
  Octokit.configure do |c|
    c.api_endpoint = ENV['GITHUB_ENTERPRISE_URL']
  end
end

client = Octokit::Client.new access_token: ENV['GITHUB_TOKEN']
client.auto_paginate = true

begin
  all_repos = client.organization_repositories(ARGV[0].strip, type: 'sources')
rescue StandardError
  all_repos = client.repositories(ARGV[0].strip, type: 'sources')
end

repos = all_repos.reject(&:archived)

puts "Found #{repos.count} repos. Counting..."

reports = []
repos.each do |repo|
  puts "Counting #{repo.name}..."

  destination = File.expand_path repo.name, tmp_dir
  report_file = File.expand_path "#{repo.name}.txt", tmp_dir

  clone_url = repo.clone_url
  clone_url = clone_url.sub '//', "//#{ENV['GITHUB_TOKEN']}:x-oauth-basic@" if ENV['GITHUB_TOKEN']
  _output, status = Open3.capture2e 'git', 'clone', '--depth', '1', '--quiet', clone_url, destination
  next unless status.exitstatus.zero?

  _output, _status = cloc destination, '--quiet', "--report-file=#{report_file}"
  reports.push(report_file) if File.exist?(report_file) && status.exitstatus.zero?
end

puts 'Done. Summing...'

output, _status = cloc '--sum-reports', *reports
puts output.gsub(%r{^#{Regexp.escape tmp_dir}/(.*)\.txt}) { Regexp.last_match(1) + ' ' * (tmp_dir.length + 5) }
