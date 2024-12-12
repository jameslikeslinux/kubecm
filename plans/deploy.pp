# Install or upgrade a release
#
# @param release          Installation name (what is this deployment called)
# @param chart            Chart name, or your name for this deployment and set `chart_source`
# @param chart_source     Typically `repo_name/chart_name` or an `oci://` URI, but could be a local path,
#                           a valid Puppet file source, or `undef` for no chart (just Hiera resources).
# @param hooks            Enable or disable install hooks
# @param namespace        Kubernetes namespace to manage
# @param remove_resources A list of keys to remove from the resources map (i.e. don't deploy these!)
# @param render_to        Just save the fully-rendered chart to this yaml file
# @param repo_url         Optional URL of the Helm repo to add
# @param version          Optional Helm chart version
# @param wait             Wait for resources to become available
# @param subcharts        Additional charts to deploy as part of this one
# @param parent           Private. The parent release this one is being rendered for.
# @param build_dir        Scratch directory for compiling manifests
plan kubecm::deploy (
  String           $release,
  String           $chart            = $release,
  Optional[String] $chart_source     = undef,
  Boolean          $hooks            = true,
  Optional[String] $namespace        = undef,
  Array[String]    $remove_resources = [],
  Optional[String] $render_to        = undef,
  Optional[String] $repo_url         = undef,
  Optional[String] $version          = undef,
  Boolean          $wait             = false,
  Array[Hash]      $subcharts        = [],
  Optional[String] $parent           = undef,

  # Project settings
  # (set your own defaults in Hiera)
  String $build_dir     = lookup('kubecm::deploy::build_dir'),
  String $resources_key = lookup('kubecm::deploy::resources_key'),
  String $values_key    = lookup('kubecm::deploy::values_key'),
  String $patches_key   = lookup('kubecm::deploy::patches_key'),
) {
  $subchart_manifests = $subcharts.map |$subchart| {
    $manifest = "${subchart['release']}.yaml"
    run_plan('kubecm::deploy', $subchart + {
        parent    => $release,
        namespace => $namespace,
        render_to => "${build_dir}/${manifest}",
      }
    )
    $manifest
  }

  if $build_dir =~ Stdlib::Absolutepath {
    $build_dir_real = $build_dir
  } else {
    $pwd = run_command('pwd', 'localhost', 'Determine current working directory').first.value['stdout'].chomp
    $build_dir_real = file::join($pwd, $build_dir)
  }

  apply('localhost') {
    include kubecm::deploy # defines variables needed for lookups

    $resources = lookup($resources_key, Hash, 'hash', {}) - $remove_resources
    $values    = lookup($values_key, Hash, 'deep', {})
    $patches   = lookup($patches_key, Hash, 'hash', {})

    file {
      $build_dir_real:
        ensure  => directory;

      "${build_dir_real}/resources.yaml":
        content => $resources.values.flatten.map |$r| { if $r.empty { '' } else { $r.stdlib::to_yaml } }.join;

      "${build_dir_real}/values.yaml":
        content => $values.stdlib::to_yaml;

      "${build_dir_real}/kustomization.yaml":
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

      "${build_dir_real}/kustomize.sh":
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
        "${build_dir_real}/chart":
          ensure  => directory,
          purge   => true, # clean out old files
          recurse => true; # recursively

        "${build_dir_real}/chart/Chart.yaml":
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
      file { "${build_dir_real}/chart":
        ensure  => directory,
        purge   => true,
        recurse => true,
        source  => $chart_source,
      }
    }
  }.kubecm::print_report

  if !chart_source or $chart_source =~ Stdlib::Filesource {
    $chart_source_real = "${build_dir_real}/chart"
  } elsif $chart_source =~ /^(\w+)\// and $repo_url {
    $chart_source_real = $chart_source
    $repo_name = $1
    $helm_repo_add_cmd = "helm repo add ${repo_name.shellquote} ${repo_url.shellquote}"
    run_command($helm_repo_add_cmd, 'localhost', "Add Helm repo ${repo_name} at ${repo_url}")
  } elsif $chart_source =~ /^oci:/ {
    $chart_source_real = $chart_source
  } else {
    $chart_source_real = file::join('.', $chart_source)
  }

  $helm_cmd = [
    'helm',

    $render_to ? {
      undef   => ['upgrade', '--install'],
      default => 'template',
    },

    $release, $chart_source_real,

    $hooks ? {
      false   => '--no-hooks',
      default => [],
    },

    $namespace ? {
      undef   => [],
      default => ['--create-namespace', '--namespace', $namespace],
    },

    '--post-renderer', "${build_dir}/kustomize.sh",
    '--post-renderer-args', $build_dir,
    '--values', "${build_dir}/values.yaml",

    $version ? {
      undef   => [],
      default => ['--version', $version],
    },

    ($wait and !$render_to_real) ? {
      true    => ['--wait', '--timeout', '1h'],
      default => [],
    },
  ].flatten.shellquote

  if $render_to {
    $redirect = " > ${render_to.shellquote}"
    $cmd_verb = 'Render'
  } else {
    $redirect = ''
    $cmd_verb = 'Deploy'
  }

  $result = run_command("${helm_cmd}${redirect}", 'localhost', "${cmd_verb} ${release} from Helm chart ${chart_source_real}").first

  return $result
}
