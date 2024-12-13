require 'base64'
require 'json'
require 'spec_helper'
require 'yaml'

describe 'kubecm::deploy' do
  let(:params) do
    {
      'release_build_dir' => '/build/myrelease-test',
    }
  end

  let(:pre_condition) do
    <<-PRE_CONDITION
      # Plan vars
      $release      = 'myrelease'
      $chart        = 'myapp'
      $chart_source = undef
      $namespace    = 'test'
      $parent       = undef
      $version      = undef

      # Test classes included by hiera data
      class myproject {
        $release = "myproject-${kubecm::deploy::release}"
        $app     = "myproject-${kubecm::deploy::chart}"

        $registry_auths = base64('encode', {
          'auths' => {
            'registry.example.com' => {
              'auth' => 'fake-token',
            },
          },
        }.stdlib::to_json)
      }

      class myproject::myapp {
        $app_name  = "${myproject::app}-${kubecm::deploy::release}"
        $app_label = 'Test'
      }
    PRE_CONDITION
  end

  # Values and patches is very much the same
  describe 'resources' do
    resources = [
      {
        'apiVersion' => 'v1',
        'kind'       => 'Secret',
        'metadata'   => {
          'name'      => 'myproject-myrelease-registry-auths',
          'namespace' => 'test',
        },
        'data' => {
          '.dockerconfigjson' => Base64.encode64(
            {
              'auths' => {
                'registry.example.com' => {
                  'auth' => 'fake-token',
                },
              },
            }.to_json,
          ),
        },
        'type'       => 'kubernetes.io/dockerconfigjson',
      },
      {
        'apiVersion' => 'v1',
        'kind'       => 'Deployment',
        'metadata'   => {
          'name'      => 'myproject-myapp-myrelease-deployment',
          'namespace' => 'test',
          'labels'    => {
            'app_name' => 'Test',
            'release'  => 'myproject-myrelease',
          },
        },
      },
      {
        'apiVersion' => 'v1',
        'kind'       => 'ConfigMap',
        'metadata'   => {
          'name'      => 'myproject-myrelease-config',
          'namespace' => 'test',
        },
        'data' => {
          'memory_example'  => '1Gi', # overridden by namespace config
          'threads_example' => '4',   # not overridden
        },
      },
    ].map(&:to_yaml).join

    it { is_expected.to contain_file('/build/myrelease-test/resources.yaml').with_content(resources) }
  end

  describe 'kustomization config' do
    describe 'resources' do
      context 'without subcharts' do
        resources = {
          'resources' => ['resources.yaml', 'helm.yaml']
        }.to_yaml.split("\n")[1..-1].join("\n")

        it { is_expected.to contain_file('/build/myrelease-test/kustomization.yaml').with_content(%r{#{Regexp.escape(resources)}}) }
      end

      context 'with subcharts' do
        let(:params) do
          super().merge(
            {
              'subchart_manifests' => ['subchart1.yaml', 'subchart2.yaml'],
            },
          )
        end

        resources = {
          'resources' => ['subchart1.yaml', 'subchart2.yaml', 'resources.yaml', 'helm.yaml']
        }.to_yaml.split("\n")[1..-1].join("\n")

        it { is_expected.to contain_file('/build/myrelease-test/kustomization.yaml').with_content(%r{#{Regexp.escape(resources)}}) }
      end
    end
  end
end
