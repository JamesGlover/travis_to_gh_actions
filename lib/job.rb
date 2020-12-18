# Jobs are initialized from the travis file, and converted to gh action jobs
# Some
class Job
  def initialize(base_config, job_config)
    @base_config = base_config
    @job_config = job_config
  end

  def name
    @job_config['name']
  end

  def gh_hash
    {
      'runs-on' => 'ubuntu-latest',
      'steps' => steps
    }
  end

  def steps
    [

    ]
  end
end
