# Puppet entrypoint for the kubecm::deploy plan
#
# This defines the following variables for use in your Hiera hierarchy
# and data, and declares other classes for your own custom variables.
#
#   * kubecm::deploy::release
#   * kubecm::deploy::chart
#   * kubecm::deploy::chart_source
#   * kubecm::deploy::namespace
#   * kubecm::deploy::parent
#   * kubecm::deploy::version
#
# @param include_key Hiera key mapping a list of custom classes to declare
# @api private
class kubecm::deploy (
  String $build_dir,
  String $include_key,
  String $resources_key,
  String $values_key,
  String $patches_key,
  Array[String] $remove_resources = [],
  Array[String] $subchart_manifests = [],
) {
  # Bring plan variables into class scope for lookups
  # (class parameters can't be used in lookups until after it's fully loaded)
  # lint:ignore:top_scope_facts
  $release      = $::release
  $chart        = $::chart
  $chart_source = $::chart_source
  $namespace    = pick_default($::namespace, 'default')
  $parent       = $::parent
  $version      = $::version
  # lint:endignore

  # Include custom classes that define other variables for lookups
  lookup($include_key, Array[String], 'unique', []).reverse.include

  $resources = lookup($resources_key, Hash, 'hash', {}) - $remove_resources
  $values    = lookup($values_key, Hash, 'deep', {})
  $patches   = lookup($patches_key, Hash, 'hash', {})

  file {
    $build_dir:
      ensure  => directory;

    "${build_dir}/resources.yaml":
      content => $resources.values.flatten.map |$r| { if $r.empty { '' } else { $r.stdlib::to_yaml } }.join;

    "${build_dir}/values.yaml":
      content => $values.stdlib::to_yaml;

    "${build_dir}/kustomization.yaml":
      content => {
        'resources' => $subchart_manifests + ['resources.yaml', 'helm.yaml'],
        'patches'   => $patches.keys.sort.map |$k| { $patches[$k] }.flatten.map |$p| {
          if $p['patch'] =~ String {
            $p
          } else {
            $p + { 'patch' => $p['patch'].stdlib::to_yaml }
          }
        },
      }.stdlib::to_yaml;

    "${build_dir}/kustomize.sh":
      mode   => '0755',
      source => 'puppet:///modules/kubecm/kustomize.sh';
  }

  if !$chart_source {
    if $version {
      $fake_chart_version = $version
    } else {
      $fake_chart_version = '0.1.0' # just something
    }

    file {
      "${build_dir}/chart":
        ensure  => directory,
        purge   => true, # clean out old files
        recurse => true; # recursively

      "${build_dir}/chart/Chart.yaml":
        content => {
          'apiVersion'  => 'v2',
          'name'        => $chart,
          'description' => 'KubeCM deployment',
          'type'        => 'application',
          'version'     => $fake_chart_version,
          'appVersion'  => $fake_chart_version,
        }.stdlib::to_yaml;
    }
  } elsif $chart_source =~ Stdlib::Filesource {
    file { "${build_dir}/chart":
      ensure  => directory,
      purge   => true,
      recurse => true,
      source  => $chart_source,
    }
  }
}
