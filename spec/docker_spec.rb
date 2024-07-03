require 'open3'
require 'base64'
require 'json'
require 'fileutils'
require_relative '../tasks/run_cd4pe_job.rb'

describe 'run_cd4pe_job' do
  before(:all) do
    @logger = Logger.new
  end

  before(:each) do
    @working_dir = File.join(Dir.getwd, "test_working_dir")
    Dir.mkdir(@working_dir)

    # Ensure tests don't write to /etc/containers/certs.d
    @certs_dir = File.join(@working_dir, "certs.d")
    CD4PEJobRunner.send(:remove_const, :DOCKER_CERTS)
    CD4PEJobRunner.const_set(:DOCKER_CERTS, @certs_dir)

    @web_ui_endpoint = 'https://testtest.com'
    @job_token = 'alksjdbhfnadhsbf'
    @job_owner = 'carls cool carl'
    @job_instance_id = '17'
    @secrets = {
      secret1: "hello",
      secret2: "friend",
    }
    @windows_job = ENV['RUN_WINDOWS_UNIT_TESTS']
  end

  after(:each) do
    FileUtils.remove_dir(@working_dir)
    $stdout = STDOUT
  end

  describe 'cd4pe_job_helper::get_runtime' do
    it 'Detects docker as the available runtime.' do
      test_container_image = 'puppetlabs/test:10.0.1'
      job_helper = CD4PEJobRunner.new(windows_job: @windows_job, working_dir: @working_dir, container_image: test_container_image, job_token: @job_token, web_ui_endpoint: @web_ui_endpoint, job_owner: @job_owner, job_instance_id: @job_instance_id, logger: @logger, secrets: @secrets)
      expect(job_helper.get_runtime).to eq('docker')
    end
  end

  describe 'cd4pe_job_helper::update_container_image' do
    let(:test_container_image) { 'puppetlabs/test:10.0.1' }
    it 'Generates a docker pull command.' do
      job_helper = CD4PEJobRunner.new(windows_job: @windows_job, working_dir: @working_dir, container_image: test_container_image, job_token: @job_token, web_ui_endpoint: @web_ui_endpoint, job_owner: @job_owner, job_instance_id: @job_instance_id, logger: @logger, secrets: @secrets)
      docker_pull_command = job_helper.get_image_pull_cmd
      expect(docker_pull_command).to eq("docker pull #{test_container_image}")
    end

    context 'with config' do
      let(:hostname) { 'host1' }
      let(:creds_json) { {auths: {hostname => {}}}.to_json }
      let(:creds_b64) { Base64.encode64(creds_json) }
      let(:cert_txt) { 'junk' }
      let(:cert_b64) { Base64.encode64(cert_txt) }

      it 'Uses config when present for docker.' do
        job_helper = CD4PEJobRunner.new(windows_job: @windows_job, working_dir: @working_dir, container_image: test_container_image, image_pull_creds: creds_b64, job_token: @job_token, web_ui_endpoint: @web_ui_endpoint, job_owner: @job_owner, job_instance_id: @job_instance_id, logger: @logger, secrets: @secrets)
        config_json = File.join(@working_dir, '.docker', 'config.json')
        expect(File.exist?(config_json)).to be(true)
        expect(File.read(config_json)).to eq(creds_json)

        docker_pull_command = job_helper.get_image_pull_cmd
        expect(docker_pull_command).to eq("docker --config #{File.join(@working_dir, '.docker')} pull #{test_container_image}")
      end

      it 'Registers the CA cert when provided.' do
        job_helper = CD4PEJobRunner.new(windows_job: @windows_job, working_dir: @working_dir, container_image: test_container_image, image_pull_creds: creds_b64, base_64_ca_cert: cert_b64, job_token: @job_token, web_ui_endpoint: @web_ui_endpoint, job_owner: @job_owner, job_instance_id: @job_instance_id, logger: @logger, secrets: @secrets)

        cert_file = File.join(@certs_dir, hostname, 'ca.crt')
        expect(File.exist?(cert_file)).to be(true)
        expect(File.read(cert_file)).to eq(cert_txt)
      end
    end
  end

  describe 'cd4pe_job_helper::get_container_run_cmd' do
    it 'Generates the correct docker run command.' do
      test_manifest_type = "AFTER_JOB_SUCCESS"
      test_container_image = 'puppetlabs/test:10.0.1'
      arg1 = '--testarg=woot'
      arg2 = '--otherarg=hello'
      arg3 = '--whatever=doesntmatter'
      user_specified_container_run_args = [arg1, arg2, arg3]
      job_type = 'unix'

      job_helper = CD4PEJobRunner.new(windows_job: @windows_job, working_dir: @working_dir, container_image: test_container_image, container_run_args: user_specified_container_run_args, job_token: @job_token, web_ui_endpoint: @web_ui_endpoint, job_owner: @job_owner, job_instance_id: @job_instance_id, logger: @logger, secrets: @secrets)

      docker_run_command = job_helper.get_container_run_cmd(test_manifest_type)
      cmd_parts = docker_run_command.split(' ')

      expect(cmd_parts[0]).to eq('docker')
      expect(cmd_parts[1]).to eq('run')
      expect(cmd_parts[2]).to eq('--rm')
      expect(cmd_parts[3]).to eq(arg1)
      expect(cmd_parts[4]).to eq(arg2)
      expect(cmd_parts[5]).to eq(arg3)
      expect(cmd_parts[6]).to eq('-e')
      expect(cmd_parts[7]).to eq('secret1')
      expect(cmd_parts[8]).to eq('-e')
      expect(cmd_parts[9]).to eq('secret2')
      expect(cmd_parts[10]).to eq('-v')
      expect(cmd_parts[11].end_with?("/#{File.basename(@working_dir)}/cd4pe_job/repo:/repo\"")).to be(true)
      expect(cmd_parts[12]).to eq('-v')
      expect(cmd_parts[13].end_with?("/#{File.basename(@working_dir)}/cd4pe_job/jobs/#{job_type}:/cd4pe_job\"")).to be(true)
      expect(cmd_parts[14]).to eq(test_container_image)
      expect(cmd_parts[15]).to eq('"/cd4pe_job/AFTER_JOB_SUCCESS"')
    end
  end
end