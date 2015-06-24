require 'spec_helper'

describe 'migrating to cloud config', type: :integration do
  with_reset_sandbox_before_each

  before do
    target_and_login
    create_and_upload_test_release
    upload_stemcell
  end

  let(:cloud_config_hash) do
    cloud_config_hash = Bosh::Spec::Deployments.simple_cloud_config
    # remove size from resource pools due to bug #94220432
    # where resource pools with specified size reserve extra IPs
    cloud_config_hash['resource_pools'].first.delete('size')

    cloud_config_hash['networks'].first['subnets'].first['static'] =  ['192.168.1.10', '192.168.1.11']
    cloud_config_hash
  end

  let(:simple_manifest) do
    manifest_hash = Bosh::Spec::Deployments.simple_manifest
    manifest_hash['jobs'].first['instances'] = 1
    manifest_hash
  end

  let(:second_deployment_manifest) do
    manifest_hash = Bosh::Spec::Deployments.simple_manifest
    manifest_hash['jobs'].first['instances'] = 1
    manifest_hash['name'] = 'second_deployment'
    manifest_hash
  end

  def deploy_with_ip(manifest, ip, options={})
    manifest['jobs'].first['networks'].first['static_ips'] = [ip]
    manifest['jobs'].first['instances'] = 1
    options.merge!(manifest_hash: manifest)
    deploy_simple_manifest(options)
  end

  context 'when we have legacy deployments deployed' do
    let(:legacy_manifest) do
      legacy_manifest = Bosh::Spec::Deployments.legacy_manifest
      legacy_manifest['jobs'].first['instances'] = 1
      legacy_manifest['resource_pools'].first.delete('size')
      legacy_manifest
    end

    it 'deployment after cloud config gets IP outside of range reserved by first deployment' do
      legacy_manifest['networks'].first['subnets'].first['range'] = '192.168.1.0/28'
      deploy_simple_manifest(manifest_hash: legacy_manifest)
      vms = director.vms
      expect(vms.size).to eq(1)
      expect(vms.first.ips).to eq('192.168.1.2')

      upload_cloud_config(cloud_config_hash: cloud_config_hash)

      deploy_simple_manifest(manifest_hash: second_deployment_manifest)
      vms = director.vms
      expect(vms.size).to eq(1)
      expect(vms.first.ips).to eq('192.168.1.16')
    end

    it 'deployment after cloud config fails to get static IP in the range reserved by first deployment' do
        legacy_manifest['networks'].first['subnets'].first['range'] = '192.168.1.0/28'
        deploy_simple_manifest(manifest_hash: legacy_manifest)
        vms = director.vms
        expect(vms.size).to eq(1)
        expect(vms.first.ips).to eq('192.168.1.2')

        upload_cloud_config(cloud_config_hash: cloud_config_hash)

        _, exit_code = deploy_with_ip(
          second_deployment_manifest,
          '192.168.1.2',
          { failure_expected: true, return_exit_code: true }
        )
        expect(exit_code).to_not eq(0)
      end
  end
end
