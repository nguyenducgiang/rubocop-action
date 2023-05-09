require 'httparty'
require 'net/http'
require 'json'
require 'time'

@GITHUB_SHA = ENV["GITHUB_SHA"]

@event = JSON.parse(File.read(ENV['GITHUB_EVENT_PATH']))
@repository = @event["repository"]
@owner = @repository["owner"]["login"]
@repo = @repository["name"]

@check_name = "Rubocop"

@headers = {
  "Content-Type": 'application/json',
  "Accept": 'application/vnd.github+json',
  "Authorization": "Bearer #{ENV['GITHUB_TOKEN']}",
  "X-GitHub-Api-Version": "2022-11-28",
  "User-Agent": 'rubocop'
}

def create_check
  body = {
    "name" => @check_name,
    "head_sha" => @GITHUB_SHA,
    "status" => "in_progress"
  }.to_json
  
  url = "https://api.github.com/repos/#{@owner}/#{@repo}/check-runs"
  res = HTTParty.post(url, body: body, headers: @headers)
  
  puts url
  puts res.code
  puts res.body

  #   if resp.code.to_i >= 300
  #     raise resp.message
  #   end
  
  res.body["id"]
end

def update_check(id, conclusion, output)
  body = {
    "name" => @check_name,
    "head_sha" => @GITHUB_SHA,
    "status" => 'completed',
    "completed_at" => Time.now.iso8601,
    "conclusion" => conclusion,
    "output" => output
  }

  http = Net::HTTP.new('api.github.com', 443)
  http.use_ssl = true
  path = "/repos/#{@owner}/#{@repo}/check-runs/#{id}"

  resp = http.patch(path, body.to_json, @headers)

  if resp.code.to_i >= 300
    raise resp.message
  end
end

@annotation_levels = {
  "refactor" => 'failure',
  "convention" => 'failure',
  "warning" => 'warning',
  "error" => 'failure',
  "fatal" => 'failure'
}

def run_rubocop
  annotations = []
  errors = nil
  
  Dir.chdir(ENV['GITHUB_WORKSPACE']) {
    files = ENV['CHANGED_FILES'].split
    puts "rubocop #{files.join(' ')} --format json"
    
    return if files.empty?
    
    errors = JSON.parse(`rubocop #{files.join(' ')} --format json`)
  }
  conclusion = "success"
  count = 0
  
  puts errors

  errors["files"].each do |file|
    path = file["path"]
    offenses = file["offenses"]

    offenses.each do |offense|
      severity = offense["severity"]
      message = offense["message"]
      location = offense["location"]
      annotation_level = @annotation_levels[severity]
      count = count + 1

      if annotation_level == "failure"
        conclusion = "failure"
      end

      annotations.push({
                         "path" => path,
                         "start_line" => location["start_line"],
                         "end_line" => location["start_line"],
                         "annotation_level": annotation_level,
                         "message" => message
                       })
    end
  end

  output = {
    "title": @check_name,
    "summary": "#{count} offense(s) found",
    "annotations" => annotations
  }

  return { "output" => output, "conclusion" => conclusion }
end

def run
  id = create_check()
  begin
    results = run_rubocop()
    conclusion = results["conclusion"]
    output = results["output"]

    update_check(id, conclusion, output)

    fail if conclusion == "failure"
  rescue
    update_check(id, "failure", nil)
    fail
  end
end

run()
