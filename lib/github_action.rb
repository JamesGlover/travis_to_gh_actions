
class GithubAction
  attr_reader :name, :directory

  def initialize(directory, name)
    @name = name
    @directory = directory
    @jobs = {}
  end

  def save
    raise StandardError, "#{action_file} already exists!" if action_file.exist?
    action_file.open('w') do |file|
      YAML.dump(hash,file)
    end
  end

  def add_job(job)
    @jobs[job.name] = job.gh_hash
  end

  def hash
    {
      name: name,
      on: {
        push: { branches: [ 'master' ] },
        pull_request: { branches: [ 'master' ] }
      },
      jobs: @jobs
    }
  end

  private

  def action_file
    directory.join("#{name}.yml")
  end
end
