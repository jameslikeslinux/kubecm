require 'spec_helper'
require 'bolt_spec/plans'

describe 'kubecm::deploy' do
  include BoltSpec::Plans

  before(:each) do
    BoltSpec::Plans.init
    allow_command('pwd').always_return({ 'stdout' => '/fakedir' })
    allow_apply
  end

  it 'uses the specified build_dir' do
    expect_command('pwd').not_be_called
    expect_command('helm upgrade --install test /mybuilddir/chart --post-renderer /mybuilddir/kustomize.sh --post-renderer-args /mybuilddir --values /mybuilddir/values.yaml')
    run_plan('kubecm::deploy',
      {
        'release'      => 'test',
        'build_dir'    => '/mybuilddir',
      })
  end

  it 'deploys an empty chart when chart_source is undef' do
    expect_command('helm upgrade --install test /fakedir/build/chart --post-renderer build/kustomize.sh --post-renderer-args build --values build/values.yaml')
    run_plan('kubecm::deploy',
      {
        'release' => 'test',
      })
  end

  it 'deploys a local chart when chart_source is an absolute path' do
    expect_command('helm upgrade --install test /fakedir/build/chart --post-renderer build/kustomize.sh --post-renderer-args build --values build/values.yaml')
    run_plan('kubecm::deploy',
      {
        'release'      => 'test',
        'chart_source' => '/mychart', # gets copied to /fakedir/build/chart
      })
  end

  it 'deploys a chart from a repo' do
    expect_command('helm repo add fakerepo https://example.com/fakerepo')
    expect_command('helm upgrade --install test fakerepo/fakechart --post-renderer build/kustomize.sh --post-renderer-args build --values build/values.yaml')
    run_plan('kubecm::deploy',
      {
        'release'      => 'test',
        'chart_source' => 'fakerepo/fakechart',
        'repo_url'     => 'https://example.com/fakerepo',
      })
  end

  it 'deploys a chart from an oci:// URI' do
    expect_command('helm upgrade --install test oci://example.com/fakerepo/fakechart --post-renderer build/kustomize.sh --post-renderer-args build --values build/values.yaml')
    run_plan('kubecm::deploy',
      {
        'release'      => 'test',
        'chart_source' => 'oci://example.com/fakerepo/fakechart',
      })
  end

  it 'deploys a local chart from a relative path' do
    expect_command('helm upgrade --install test ./mychart --post-renderer build/kustomize.sh --post-renderer-args build --values build/values.yaml')
    run_plan('kubecm::deploy',
      {
        'release'      => 'test',
        'chart_source' => 'mychart',
      })
  end

  it 'renders a chart to a specified file' do
    expect_command('helm template test /fakedir/build/chart --post-renderer build/kustomize.sh --post-renderer-args build --values build/values.yaml > test.yaml')
    run_plan('kubecm::deploy',
      {
        'release'   => 'test',
        'render_to' => 'test.yaml',
      })
  end

  it 'deploys without hooks if requested' do
    expect_command('helm upgrade --install test /fakedir/build/chart --no-hooks --post-renderer build/kustomize.sh --post-renderer-args build --values build/values.yaml')
    run_plan('kubecm::deploy',
      {
        'release' => 'test',
        'hooks'   => false,
      })
  end

  it 'deploys to the specified namespace' do
    expect_command('helm upgrade --install test /fakedir/build/chart --create-namespace --namespace test --post-renderer build/kustomize.sh --post-renderer-args build --values build/values.yaml')
    run_plan('kubecm::deploy',
      {
        'release'   => 'test',
        'namespace' => 'test',
      })
  end

  it 'deploys to the specified version' do
    expect_command('helm upgrade --install test /fakedir/build/chart --post-renderer build/kustomize.sh --post-renderer-args build --values build/values.yaml --version 1.2.3')
    run_plan('kubecm::deploy',
      {
        'release' => 'test',
        'version' => '1.2.3',
      })
  end

  it 'waits for the deployment if requested' do
    expect_command('helm upgrade --install test /fakedir/build/chart --post-renderer build/kustomize.sh --post-renderer-args build --values build/values.yaml --wait --timeout 1h')
    run_plan('kubecm::deploy',
      {
        'release' => 'test',
        'wait'    => true,
      })
  end
end
